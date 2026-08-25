import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';
import '../data/braille_preprocessor.dart';

class BrailleService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final BraillePreprocessor _preprocessor = BraillePreprocessor();
  final PdfService pdfService = PdfService();
  bool _isModelAvailable = false;
  List<String> _labels = [];

  bool get isModelAvailable => _isModelAvailable;

  /// Default 64-class Braille cell character map dictionary fallback (matching 6-dot binary order).
  static const List<String> defaultBrailleDictionary = [
    ' ', ',', '?', '?', '?', '?', '?', '?',
    '\'', '-', '*', '?', '/', '?', '(', '#',
    '"', '?', ':', ')', 'i', '?', 'j', 'w',
    ';', '?', '!', '?', 's', '?', 't', '?',
    'a', '?', 'e', '?', 'c', '?', 'd', '?',
    'k', 'u', 'o', 'z', 'm', 'x', 'n', 'y',
    'b', '?', 'h', '?', 'f', '?', 'g', '?',
    'l', 'v', 'r', '?', 'p', '?', 'q', '?'
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
      final loaded = labelsData.split('\n').map((l) => l.trimRight()).toList();
      if (loaded.isNotEmpty) {
        _labels = loaded;
        return;
      }
    } catch (e) {
      debugPrint('BrailleService: Failed to load labels asset, falling back to default dictionary.');
    }
    _labels = List.from(defaultBrailleDictionary);
  }

  /// Classifies a photographed Braille page into structured digital text.
  /// Uses TFLite CNN inference when available, or heuristic cell grid processing as fallback.
  Future<String> classifyBraille(String imagePath) async {
    final hasModel = await checkModelAvailability();

    try {
      debugPrint('Classifying Braille page image at $imagePath (TFLite Model Active: $hasModel)...');
      final file = File(imagePath);
      if (!file.existsSync()) {
        debugPrint('Image file at $imagePath does not exist.');
        return hasModel ? 'No image captured. Please try again.' : 'MODEL_UNAVAILABLE';
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Failed to decode image at $imagePath.');
        return 'Could not decode image format.';
      }

      if (hasModel && _tfliteHelper.interpreter != null) {
        final List<int> detectedCellIndices = await _processImageAndRunInference(image);
        if (detectedCellIndices.isEmpty) {
          return 'No Braille text detected. Please align camera over a Braille page.';
        }
        final recognizedText = assembleBrailleText(detectedCellIndices);
        final cleanedText = recognizedText.replaceAll('?', '').trim();
        return cleanedText.isNotEmpty ? recognizedText : 'No Braille text detected. Please align camera over a Braille page.';
      } else {
        // Fallback: Pure Dart cell grid & 6-dot heuristic analysis
        final cells = _preprocessor.extractCellData(image);
        if (cells.isEmpty || cells.every((c) => c.isEmpty)) {
          return 'No Braille text detected. Please align camera over a Braille page.';
        }
        final recognizedText = assembleBrailleFromCells(cells);
        final cleanedText = recognizedText.replaceAll('?', '').trim();
        return cleanedText.isNotEmpty ? recognizedText : 'No Braille text detected. Please align camera over a Braille page.';
      }
    } catch (e, stack) {
      debugPrint('Braille classification error: $e\n$stack');
      return 'Error during Braille processing: $e';
    }
  }

  /// Map 6-element boolean dot list [d1, d2, d3, d4, d5, d6] to Braille character
  String map6DotsToCharacter(List<bool> dots) {
    if (dots.length < 6 || dots.every((d) => !d)) return ' ';

    final pattern = dots.map((d) => d ? '1' : '0').join();
    const map = {
      '100000': 'a', '110000': 'b', '100100': 'c', '100110': 'd', '100010': 'e',
      '110100': 'f', '110110': 'g', '110010': 'h', '010100': 'i', '010110': 'j',
      '101000': 'k', '111000': 'l', '101100': 'm', '101110': 'n', '101010': 'o',
      '111100': 'p', '111110': 'q', '111010': 'r', '011100': 's', '011110': 't',
      '101001': 'u', '111001': 'v', '010111': 'w', '101101': 'x', '101111': 'y',
      '101011': 'z', '001111': '#', '000001': ',',
    };

    return map[pattern] ?? '?';
  }

  String assembleBrailleFromCells(List<BrailleCellData> cells) {
    final buffer = StringBuffer();
    bool isNumberMode = false;
    bool isCapitalMode = false;

    final numberMap = {
      'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
      'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0',
    };

    int lastRow = -1;

    for (final cell in cells) {
      if (cell.row != lastRow && lastRow != -1) {
        buffer.write(' ');
      }
      lastRow = cell.row;

      if (cell.isEmpty) {
        isNumberMode = false;
        isCapitalMode = false;
        buffer.write(' ');
        continue;
      }

      final rawChar = map6DotsToCharacter(cell.dots);

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

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Exports recognized Braille text to a PDF file saved in device storage.
  Future<File> exportBrailleTextToPdf(String textContent, {String title = 'Recognized_Braille_Document'}) async {
    return await pdfService.generatePdfFromText(title: title, textContent: textContent);
  }

  /// Scales image to standard resolution, detects Braille dot/cell regions, and runs TFLite inference.
  Future<List<int>> _processImageAndRunInference(img.Image originalImage) async {
    final interpreter = _tfliteHelper.interpreter!;
    final List<int> cellIndices = [];
    int totalDetectedNonSpaceCount = 0;

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

        // Require at least 0.35 confidence for a non-space Braille character class
        if (bestClass == 0 || maxProb < 0.35) {
          cellIndices.add(0);
        } else {
          cellIndices.add(bestClass);
          lineValidCount++;
          totalDetectedNonSpaceCount++;
        }
      }

      if (lineValidCount > 0) {
        cellIndices.add(0); // Line space separator
      }
    }

    // Require at least 2 valid character detections to consider the photo a Braille image
    if (totalDetectedNonSpaceCount < 2) {
      return [];
    }

    return cellIndices;
  }

  /// Maps a class index (0..63) to its corresponding Braille character.
  String mapIndexToCharacter(int index) {
    final activeList = _labels.isNotEmpty ? _labels : defaultBrailleDictionary;
    if (index >= 0 && index < activeList.length) {
      return activeList[index];
    }
    return '?';
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
