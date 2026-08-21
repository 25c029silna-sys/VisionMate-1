import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';

class BrailleService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final PdfService pdfService = PdfService();
  bool _isModelAvailable = false;
  List<String> _labels = [];

  bool get isModelAvailable => _isModelAvailable;

  /// Default 64-class Braille cell character map dictionary fallback.
  static const List<String> defaultBrailleDictionary = [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
    'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
    'u', 'v', 'w', 'x', 'y', 'z',
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
    '.', ',', ';', ':', '!', '?', "'", '"', '-', '(',
    ')', '/', '@', '#', '\$', '%', '&', '*', '+', '=',
    '<', '>', '[', ']', '{', '}', '_', ' '
  ];

  Future<bool> checkModelAvailability() async {
    final interpreter = await _tfliteHelper.loadModel('assets/models/braille_cnn.tflite');
    _isModelAvailable = interpreter != null;
    await _loadLabels();
    return _isModelAvailable;
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString('assets/labels/braille_labels.txt');
      _labels = labelsData.split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty).toList();
    } catch (e) {
      debugPrint('BrailleService: Failed to load labels asset, falling back to default dictionary.');
      _labels = List.from(defaultBrailleDictionary);
    }
  }

  /// Classifies a photographed Braille page into structured digital text
  /// by segmenting image into cells and running real TFLite CNN inference.
  Future<String> classifyBraille(String imagePath) async {
    final available = await checkModelAvailability();
    if (!available || _tfliteHelper.interpreter == null) {
      return 'MODEL_UNAVAILABLE';
    }

    try {
      debugPrint('Classifying Braille page image at $imagePath...');
      final file = File(imagePath);
      if (!file.existsSync()) {
        debugPrint('Image file at $imagePath does not exist.');
        return 'No image captured. Please try again.';
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Failed to decode image at $imagePath.');
        return 'Could not decode image format.';
      }

      final List<int> detectedCellIndices = await _processImageAndRunInference(image);
      if (detectedCellIndices.isEmpty) {
        return 'No Braille text detected. Align camera over Braille cells.';
      }

      final recognizedText = assembleBrailleText(detectedCellIndices);
      return recognizedText.isNotEmpty ? recognizedText : 'No readable Braille text found.';
    } catch (e, stack) {
      debugPrint('Braille classification error: $e\n$stack');
      return 'Error during Braille processing: $e';
    }
  }

  /// Exports recognized Braille text to a PDF file saved in device storage.
  Future<File> exportBrailleTextToPdf(String textContent, {String title = 'Recognized_Braille_Document'}) async {
    return await pdfService.generatePdfFromText(title: title, textContent: textContent);
  }

  /// Scales image to standard resolution, detects Braille dot/cell regions, and runs TFLite inference.
  Future<List<int>> _processImageAndRunInference(img.Image originalImage) async {
    final interpreter = _tfliteHelper.interpreter!;
    final List<int> cellIndices = [];

    // 1. Resize high-res photos to standard 800px width to stabilize cell aspect ratios
    img.Image scaledImage = originalImage;
    if (originalImage.width > 800) {
      scaledImage = img.copyResize(originalImage, width: 800);
    }

    // 2. Grayscale conversion
    final grayscale = img.grayscale(scaledImage);
    final width = grayscale.width;
    final height = grayscale.height;

    // 3. Adaptive cell grid cropping (6 rows by 10 columns within central document frame)
    const int numRows = 6;
    const int numCols = 10;

    // Margin crop (exclude outer 5% width and 10% height)
    final int startX = (width * 0.05).toInt();
    final int startY = (height * 0.10).toInt();
    final int gridW = (width * 0.90).toInt();
    final int gridH = (height * 0.80).toInt();

    final int cellW = gridW ~/ numCols;
    final int cellH = gridH ~/ numRows;

    for (int r = 0; r < numRows; r++) {
      int lineValidCount = 0;
      for (int c = 0; c < numCols; c++) {
        final int cropX = startX + c * cellW;
        final int cropY = startY + r * cellH;

        if (cropX + cellW > width || cropY + cellH > height) continue;

        final patch = img.copyCrop(
          grayscale,
          x: cropX,
          y: cropY,
          width: cellW,
          height: cellH,
        );

        final resizedPatch = img.copyResize(patch, width: 28, height: 28);

        double minLum = 255.0;
        double maxLum = 0.0;

        // Prepare TFLite input tensor shape [1, 28, 28, 1] raw 0..255 float32
        // (Rescaling(1./255) layer inside the TFLite model performs the 0..1 normalization)
        final inputTensor = List.generate(
          1,
          (_) => List.generate(
            28,
            (y) => List.generate(
              28,
              (x) {
                final pixel = resizedPatch.getPixel(x, y);
                final luminance = img.getLuminance(pixel).toDouble();
                if (luminance < minLum) minLum = luminance;
                if (luminance > maxLum) maxLum = luminance;
                return [luminance];
              },
            ),
          ),
        );

        // Require minimum luminance variance (35 out of 255) within cell patch to avoid background noise
        double patchContrast = maxLum - minLum;
        if (patchContrast < 35.0) {
          cellIndices.add(0); // 0 maps to empty space ' '
          continue;
        }

        final outputTensor = List.generate(1, (_) => List.filled(64, 0.0));
        interpreter.run(inputTensor, outputTensor);

        final List<double> probs = List<double>.from(outputTensor[0]);
        int bestClass = 0;
        double maxProb = probs[0];
        for (int i = 1; i < probs.length; i++) {
          if (probs[i] > maxProb) {
            maxProb = probs[i];
            bestClass = i;
          }
        }

        // If class is 0 or low probability, treat as space ' '
        if (bestClass == 0 || maxProb < 0.20) {
          cellIndices.add(0);
        } else {
          cellIndices.add(bestClass);
          lineValidCount++;
        }
      }

      if (lineValidCount > 0) {
        cellIndices.add(0); // Line space separator
      }
    }

    return cellIndices;
  }

  /// Maps a class index (0..63) to its corresponding Braille character.
  String mapIndexToCharacter(int index) {
    final activeList = _labels.isNotEmpty ? _labels : defaultBrailleDictionary;
    if (index >= 0 && index < activeList.length) {
      return activeList[index];
    }
    return ' ';
  }

  /// Reconstructs a list of cell indices into continuous structured text with stateful decoding.
  /// Handles Braille number signs (#) and capitalization (,).
  String assembleBrailleText(List<int> cellIndices) {
    final buffer = StringBuffer();
    bool isNumberMode = false;
    bool isCapitalMode = false;

    final numberMap = {
      'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
      'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0',
    };

    for (final idx in cellIndices) {
      final rawChar = mapIndexToCharacter(idx);

      if (rawChar == '#') {
        isNumberMode = true;
        continue;
      }

      if (rawChar == ',') {
        isCapitalMode = true;
        continue;
      }

      if (rawChar == ' ') {
        isNumberMode = false;
        isCapitalMode = false;
        buffer.write(' ');
        continue;
      }

      String charToWrite = rawChar;

      if (isNumberMode && numberMap.containsKey(rawChar)) {
        charToWrite = numberMap[rawChar]!;
      } else if (isCapitalMode) {
        charToWrite = rawChar.toUpperCase();
        isCapitalMode = false;
      }

      buffer.write(charToWrite);
    }

    // Clean multiple consecutive spaces
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void dispose() {
    _tfliteHelper.dispose();
  }
}
