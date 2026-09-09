import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';
import '../data/braille_preprocessor.dart';
import 'braille_text_refiner.dart';
import 'yolo_braille_decoder.dart';

class BrailleService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final BraillePreprocessor _preprocessor = BraillePreprocessor();
  final PdfService pdfService = PdfService();
  bool _isModelAvailable = false;
  bool _isYoloModel = false;
  List<String> _labels = [];

  bool get isModelAvailable => _isModelAvailable;
  bool get isYoloModel => _isYoloModel;

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
    // 1. Try loading high-accuracy pretrained YOLOv8 Braille Object Detector
    var interpreter = await _tfliteHelper.loadModel('assets/models/yolov8_braille.tflite');
    if (interpreter != null) {
      _isModelAvailable = true;
      _isYoloModel = true;
      debugPrint('BrailleService: Pre-trained YOLOv8 Braille Object Detector loaded successfully.');
      return true;
    }

    // 2. Fallback to CNN patch classifier
    interpreter = await _tfliteHelper.loadModel('assets/models/braille_cnn.tflite');
    _isModelAvailable = interpreter != null;
    _isYoloModel = false;
    await _loadLabels();
    return _isModelAvailable;
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString('assets/labels/braille_labels.txt');
      final loaded = labelsData.split('\n').map((l) => l.replaceAll('\r', '')).toList();
      if (loaded.isNotEmpty) {
        if (loaded[0].isEmpty) loaded[0] = ' ';
        _labels = loaded.length >= 64 ? loaded.sublist(0, 64) : loaded;
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
      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        debugPrint('Failed to decode image at $imagePath.');
        return 'Could not decode image format.';
      }
      // Auto-orient based on smartphone camera EXIF metadata (fixes 90-deg rotated photos)
      final image = img.bakeOrientation(rawImage);

      if (hasModel && _tfliteHelper.interpreter != null) {
        if (_isYoloModel) {
          final recognizedText = await _processImageAndRunYoloInference(image);
          final refinedText = BrailleTextRefiner.refineOffline(recognizedText);
          final cleanedText = refinedText.replaceAll('?', '').replaceAll(' ', '').trim();
          return cleanedText.isNotEmpty ? refinedText : 'No Braille text detected. Please align camera over a Braille page.';
        }

        final List<int> detectedCellIndices = await _processImageAndRunInference(image);
        if (detectedCellIndices.isEmpty) {
          return 'No Braille text detected. Please align camera over a Braille page.';
        }
        final recognizedText = assembleBrailleText(detectedCellIndices);
        final cleanedText = recognizedText.replaceAll('?', '').replaceAll(' ', '').trim();
        return cleanedText.isNotEmpty ? recognizedText : 'No Braille text detected. Please align camera over a Braille page.';
      } else {
        // Fallback: Pure Dart cell grid & 6-dot heuristic analysis
        final cells = _preprocessor.extractCellData(image);
        if (cells.isEmpty || cells.every((c) => c.isEmpty)) {
          return 'No Braille text detected. Please align camera over a Braille page.';
        }
        final recognizedText = assembleBrailleFromCells(cells);
        final cleanedText = recognizedText.replaceAll('?', '').replaceAll(' ', '').trim();
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

  /// Letterboxes [src] to [targetWidth] x [targetHeight] by maintaining its aspect ratio
  /// and padding the remaining canvas with neutral gray (114, 114, 114).
  /// Preserves Braille cell topology and prevents aspect-ratio distortion across orientations.
  static img.Image letterbox(img.Image src, int targetWidth, int targetHeight) {
    final double scale = min(targetWidth / src.width, targetHeight / src.height);
    final int newW = (src.width * scale).round();
    final int newH = (src.height * scale).round();

    final resized = img.copyResize(src, width: newW, height: newH);
    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final int padX = ((targetWidth - newW) / 2).round();
    final int padY = ((targetHeight - newH) / 2).round();

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);
    return canvas;
  }

  /// Evaluates 4 camera orientations (0°, 270°, 90°, 180°), normalizes topology with letterbox,
  /// and runs YOLOv8 Braille object detection.
  Future<String> _processImageAndRunYoloInference(img.Image originalImage) async {
    final interpreter = _tfliteHelper.interpreter!;

    List<dynamic> bestOutput = [];
    double bestScore = -1.0;

    // Evaluate 4 possible camera orientations (0°, 270°, 90°, 180°)
    // Selects the orientation with the highest total Braille character detection confidence.
    final candidateAngles = [0, 270, 90, 180];

    for (final angle in candidateAngles) {
      img.Image currentImage = originalImage;
      if (angle != 0) {
        currentImage = img.copyRotate(originalImage, angle: angle);
      }

      // Preserve Braille cell aspect ratio and topology using letterbox padding
      final resized = letterbox(currentImage, 640, 640);

      final inputTensor = List.generate(
        1,
        (_) => List.generate(
          640,
          (y) => List.generate(
            640,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
          ),
        ),
      );

      final outputTensor = List.generate(
        1,
        (_) => List.generate(68, (_) => List.filled(8400, 0.0)),
      );

      interpreter.run(inputTensor, outputTensor);

      // Score this orientation: sum confidence of all candidate detections >= 0.30
      double currentScore = 0.0;
      int detectionCount = 0;
      final rawOut = outputTensor[0] as List;
      for (int i = 0; i < 8400; i++) {
        double maxProb = 0.0;
        int maxCls = 0;
        for (int c = 1; c < 64; c++) {
          final prob = (rawOut[4 + c][i] as num).toDouble();
          if (prob > maxProb) {
            maxProb = prob;
            maxCls = c;
          }
        }
        if (maxProb >= 0.30 && maxCls > 0) {
          currentScore += maxProb;
          detectionCount++;
        }
      }

      if (currentScore > bestScore) {
        bestScore = currentScore;
        bestOutput = outputTensor;
      }

      // If upright orientation (0°) has strong detections (> 70 high-confidence characters), stop early
      if (angle == 0 && detectionCount > 70) {
        break;
      }
    }

    if (bestOutput.isEmpty) {
      return '';
    }

    // Decode detections with NMS, line clustering, and reading-order reconstruction
    return YoloBrailleDecoder.decodeYoloOutput(
      bestOutput,
      confidenceThreshold: 0.30,
      iouThreshold: 0.40,
    );
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

        final List<double> luminances = [];
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
                luminances.add(luminance);
                if (luminance < minLum) minLum = luminance;
                if (luminance > maxLum) maxLum = luminance;
                return [luminance];
              },
            ),
          ),
        );

        final double patchContrast = maxLum - minLum;
        // Flat paper or uniform surface has near-zero contrast
        if (patchContrast < 22.0) {
          cellIndices.add(0); // 0 maps to empty space ' '
          continue;
        }

        // Statistical peak-to-background ratio filter:
        // Real Braille cells have smooth paper background with localized embossed dot peaks (ratio >= 2.3).
        // Textured non-Braille surfaces (wood grain, fabric, carpet) have uniform roughness (ratio < 2.2).
        luminances.sort();
        final double medianLum = luminances[392];
        final List<double> diffs = luminances.map((l) => (l - medianLum).abs()).toList();
        diffs.sort();
        final double bgRoughness = diffs[392]; // 50th percentile (background deviation)
        final double dotPeak = diffs[744];    // 95th percentile (dot bump contrast)
        final double peakToBgRatio = dotPeak / (bgRoughness + 0.001);

        if (peakToBgRatio < 2.3) {
          cellIndices.add(0); // Reject non-Braille textures
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

        if (bestClass == 0 || maxProb < 0.50) {
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

    // Return empty if no valid non-space Braille cells were found
    if (totalDetectedNonSpaceCount < 1) {
      return [];
    }

    return cellIndices;
  }

  /// Maps a class index (0..63) to its corresponding Braille character.
  String mapIndexToCharacter(int index) {
    if (index == 0) return ' ';
    final activeList = _labels.isNotEmpty ? _labels : defaultBrailleDictionary;
    if (index >= 0 && index < activeList.length) {
      final ch = activeList[index];
      return ch.isEmpty ? ' ' : ch;
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
