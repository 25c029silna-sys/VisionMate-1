import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';
import '../data/braille_preprocessor.dart';
import 'braille_text_refiner.dart';
import 'page_border_detector.dart';
import 'printed_braille_detector.dart';
import 'yolo_braille_decoder.dart';

/// Selectable Braille recognition pipeline mode.
enum BrailleRecognitionMode {
  /// Active default: Pure-Dart computer vision engine optimized for non-embossed
  /// (printed, flat, digital, or packaging) Braille text.
  printed,

  /// Preserved for future expansion: Deep-learning YOLOv8 engine trained on
  /// physical embossed paper pages (shadow-dipole detection).
  embossed,
}

/// Comprehensive scan result containing recognized Braille text, detected paper border,
/// and rendered demonstration image buffers for live border recognition demonstration.
class BrailleScanResult {
  final String text;
  final PageBorder pageBorder;
  final bool isBorderDetected;
  final Uint8List? annotatedImageBytes; // Image with vibrant neon green border & cyan corner brackets
  final Uint8List? croppedImageBytes;   // Rectified paper image strictly containing content inside border
  final Uint8List? originalImageBytes;  // Raw input image bytes
  final int originalWidth;
  final int originalHeight;
  final int croppedWidth;
  final int croppedHeight;
  final Duration elapsed;
  final String? debugStatus;

  BrailleScanResult({
    required this.text,
    required this.pageBorder,
    required this.isBorderDetected,
    this.annotatedImageBytes,
    this.croppedImageBytes,
    this.originalImageBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.croppedWidth,
    required this.croppedHeight,
    required this.elapsed,
    this.debugStatus,
  });

  bool get hasContent => text.trim().isNotEmpty && !text.contains('No Braille text detected');
  double get clutterReductionRatio =>
      (originalWidth > 0 && originalHeight > 0)
          ? max(0.0, 1.0 - ((croppedWidth * croppedHeight) / (originalWidth * originalHeight)))
          : 0.0;
}

class LetterboxResult {
  final img.Image image;
  final double scale;
  final int padX;
  final int padY;

  LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

class BrailleService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final BraillePreprocessor _preprocessor = BraillePreprocessor();
  final PdfService pdfService = PdfService();
  bool _isModelAvailable = false;
  bool _isYoloModel = false;
  List<String> _labels = [];

  /// Current recognition pipeline mode. Defaults to non-embossed printed Braille.
  BrailleRecognitionMode recognitionMode = BrailleRecognitionMode.printed;

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

  /// Classifies a photographed Braille page with automatic paper border detection and cropping.
  /// 
  /// 1. Identifies the edges and 4-corner boundary of the paper document using [PageBorderDetector].
  /// 2. Crops and rectifies the page so ONLY the content inside the cropped border is passed
  ///    to the Braille recognition engine.
  /// 3. Returns detailed [BrailleScanResult] with recognized text, detected border coordinates,
  ///    and visual demonstration image buffers for live demonstration.
  Future<BrailleScanResult> scanBrailleWithBorderCrop(
    String imagePath, {
    bool enableBorderCrop = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      debugPrint('Scanning Braille image with border crop at $imagePath (Mode: ${recognitionMode.name})...');
      final file = File(imagePath);
      if (!file.existsSync()) {
        debugPrint('Image file at $imagePath does not exist.');
        return BrailleScanResult(
          text: 'No image captured. Please try again.',
          pageBorder: PageBorderDetector.createFallbackBorder(100, 100),
          isBorderDetected: false,
          originalWidth: 0,
          originalHeight: 0,
          croppedWidth: 0,
          croppedHeight: 0,
          elapsed: stopwatch.elapsed,
          debugStatus: 'File not found',
        );
      }

      final bytes = await file.readAsBytes();
      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        debugPrint('Failed to decode image at $imagePath.');
        return BrailleScanResult(
          text: 'Could not decode image format.',
          pageBorder: PageBorderDetector.createFallbackBorder(100, 100),
          isBorderDetected: false,
          originalWidth: 0,
          originalHeight: 0,
          croppedWidth: 0,
          croppedHeight: 0,
          elapsed: stopwatch.elapsed,
          debugStatus: 'Decode error',
        );
      }

      // Auto-orient based on smartphone camera EXIF metadata (fixes 90-deg rotated photos)
      final image = img.bakeOrientation(rawImage);
      return await scanBrailleFromImage(
        image,
        enableBorderCrop: enableBorderCrop,
        rawBytes: bytes,
        stopwatch: stopwatch,
      );
    } catch (e, stack) {
      debugPrint('Braille classification error: $e\n$stack');
      return BrailleScanResult(
        text: 'Error during Braille processing: $e',
        pageBorder: PageBorderDetector.createFallbackBorder(100, 100),
        isBorderDetected: false,
        originalWidth: 0,
        originalHeight: 0,
        croppedWidth: 0,
        croppedHeight: 0,
        elapsed: stopwatch.elapsed,
        debugStatus: 'Error: $e',
      );
    }
  }

  /// Processes an [img.Image] directly with paper border recognition, cropping, and Braille decoding.
  Future<BrailleScanResult> scanBrailleFromImage(
    img.Image image, {
    bool enableBorderCrop = true,
    PageBorder? borderOverride,
    Uint8List? rawBytes,
    Stopwatch? stopwatch,
    String? debugStatus,
  }) async {
    final timer = stopwatch ?? (Stopwatch()..start());
    final origW = image.width;
    final origH = image.height;

    // 1. Identify paper edges and 4-corner boundary
    final PageBorder detectedBorder = borderOverride ?? PageBorderDetector.detectPageBorder(image);
    debugPrint('Detected page border: $detectedBorder (Confidence: ${detectedBorder.confidence}, Detected: ${detectedBorder.isDetected})');

    // 2. Crop to detected border so ONLY content inside the border is passed to Braille recognition
    final img.Image croppedImage = enableBorderCrop
        ? PageBorderDetector.cropAndRectifyPage(image, detectedBorder, marginRatio: 0.0)
        : image;

    // 3. Render visual demonstration overlay with neon green border and cyan corner brackets
    final img.Image overlayImage = PageBorderDetector.addCropBorderOverlay(image, detectedBorder);

    // Encode demonstration images for live UI display
    Uint8List? annotatedBytes;
    Uint8List? croppedBytes;
    Uint8List? origBytes = rawBytes;
    try {
      annotatedBytes = Uint8List.fromList(img.encodePng(overlayImage));
      croppedBytes = Uint8List.fromList(img.encodePng(croppedImage));
      origBytes ??= Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      debugPrint('Demo image encoding note: $e');
    }

    String recognizedText = '';

    // --- ACTIVE PIPELINE: Dual Auto-Adaptive Braille Engine ---
    if (recognitionMode == BrailleRecognitionMode.printed) {
      // ONLY content inside cropped border is passed for Braille recognition!
      // Passes isAlreadyCropped: true to preserve edge dots and autoOrient: true for rotation resilience
      final rawDecoded = PrintedBrailleDetector.detectAndDecode(
        croppedImage,
        isAlreadyCropped: enableBorderCrop || borderOverride != null,
        autoOrient: true,
      );
      if (rawDecoded.trim().isNotEmpty) {
        final refined = BrailleTextRefiner.refineOffline(rawDecoded);
        final cleaned = refined.replaceAll('?', '').replaceAll(' ', '').trim();
        recognizedText = cleaned.isNotEmpty ? refined : '';
      }

      // Seamless fallback: If the page is an embossed tactile Braille document
      // (where printed detection produces no text or excessive '?'), attempt YOLOv8 detection
      if (recognizedText.isEmpty || recognizedText.contains('?')) {
        final hasModel = await checkModelAvailability();
        if (hasModel && _isYoloModel && _tfliteHelper.interpreter != null) {
          try {
            final yoloDecoded = await _processImageAndRunYoloInference(croppedImage);
            if (yoloDecoded.trim().isNotEmpty) {
              final refinedYolo = BrailleTextRefiner.refineOffline(yoloDecoded);
              final cleanedYolo = refinedYolo.replaceAll('?', '').replaceAll(' ', '').trim();
              if (cleanedYolo.isNotEmpty && (recognizedText.isEmpty || cleanedYolo.length > recognizedText.length)) {
                recognizedText = refinedYolo;
                debugPrint('BrailleService: Auto-switched to embossed YOLOv8 pipeline for higher-accuracy detection.');
              }
            }
          } catch (e) {
            debugPrint('BrailleService: YOLO fallback note: $e');
          }
        }
      }

      if (recognizedText.isEmpty) {
        recognizedText = 'No Braille text detected. Please align camera over a Braille page.';
      }
    } else {
      // --- PRESERVED PIPELINE: Embossed (Tactile Paper) Braille ---
      final hasModel = await checkModelAvailability();
      if (hasModel && _tfliteHelper.interpreter != null) {
        if (_isYoloModel) {
          final rawDecoded = await _processImageAndRunYoloInference(croppedImage);
          final refined = BrailleTextRefiner.refineOffline(rawDecoded);
          final cleaned = refined.replaceAll('?', '').replaceAll(' ', '').trim();
          recognizedText = cleaned.isNotEmpty ? refined : 'No Braille text detected. Please align camera over a Braille page.';
        } else {
          final List<int> detectedCellIndices = await _processImageAndRunInference(croppedImage);
          if (detectedCellIndices.isNotEmpty) {
            recognizedText = assembleBrailleText(detectedCellIndices);
            final cleaned = recognizedText.replaceAll('?', '').replaceAll(' ', '').trim();
            if (cleaned.isEmpty) {
              recognizedText = 'No Braille text detected. Please align camera over a Braille page.';
            }
          } else {
            recognizedText = 'No Braille text detected. Please align camera over a Braille page.';
          }
        }
      } else {
        final cells = _preprocessor.extractCellData(croppedImage);
        if (cells.isNotEmpty && !cells.every((c) => c.isEmpty)) {
          recognizedText = assembleBrailleFromCells(cells);
          final cleaned = recognizedText.replaceAll('?', '').replaceAll(' ', '').trim();
          if (cleaned.isEmpty) {
            recognizedText = 'No Braille text detected. Please align camera over a Braille page.';
          }
        } else {
          recognizedText = 'No Braille text detected. Please align camera over a Braille page.';
        }
      }
    }

    timer.stop();
    return BrailleScanResult(
      text: recognizedText,
      pageBorder: detectedBorder,
      isBorderDetected: detectedBorder.isDetected,
      annotatedImageBytes: annotatedBytes,
      croppedImageBytes: croppedBytes,
      originalImageBytes: origBytes,
      originalWidth: origW,
      originalHeight: origH,
      croppedWidth: croppedImage.width,
      croppedHeight: croppedImage.height,
      elapsed: timer.elapsed,
      debugStatus: debugStatus ?? 'Completed in ${timer.elapsedMilliseconds}ms',
    );
  }

  /// Runs an instant live demonstration of the border recognition and crop feature using a
  /// synthesized document page placed on a darker desk.
  Future<BrailleScanResult> runDemoWithSampleSheet({String text = 'braille recognition'}) async {
    final sampleImage = PageBorderDetector.generateDemoBrailleSheet(brailleText: text);
    return await scanBrailleFromImage(sampleImage, enableBorderCrop: true);
  }

  /// Classifies a photographed Braille page into structured digital text.
  /// 
  /// Applies automatic paper border detection and cropping so ONLY the content inside
  /// the cropped border is passed for Braille recognition.
  Future<String> classifyBraille(String imagePath) async {
    final scanResult = await scanBrailleWithBorderCrop(imagePath, enableBorderCrop: true);
    return scanResult.text;
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

  /// Cleans and sanitizes a raw spoken document name for use as a PDF title and filename.
  /// Strips conversational carrier prefixes (e.g. "save as", "call it"), illegal characters,
  /// and formats words to Title Case.
  static String cleanPdfName(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return '';

    // Strip common conversational carrier prefixes
    final prefixPatterns = [
      RegExp(r'^(?:please\s+)?(?:save\s+as|save\s+pdf\s+as|save\s+it\s+as|save\s+pdf\s+named|save\s+document\s+as|save\s+document\s+named|export\s+as|export\s+pdf\s+as|export\s+pdf\s+named|export\s+document\s+as|export\s+pdf|save\s+pdf|name\s+it|call\s+it|titled|title|named|as)(?:$|\s+)', caseSensitive: false),
      RegExp(r'^(?:i\s+want\s+to\s+call\s+it|call\s+this|save\s+with\s+name|with\s+name)(?:$|\s+)', caseSensitive: false),
    ];
    for (final p in prefixPatterns) {
      cleaned = cleaned.replaceFirst(p, '').trim();
    }

    // Strip trailing conversational carriers or punctuation commonly captured by STT engines
    cleaned = cleaned.replaceAll(RegExp(r'[\.\,\!\?]+$'), '').trim();
    // Remove invalid filesystem filename characters: \ / : * ? " < > |
    cleaned = cleaned.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    // Collapse internal whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) return '';

    // Format into Title Case for clean presentation
    final words = cleaned.split(' ');
    final titleCased = words.map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
    }).join(' ');

    return titleCased;
  }

  /// Extracts a custom PDF name from a voice command string if present.
  /// Returns null if no custom name is specified (e.g. user just said "save pdf").
  static String? extractPdfNameFromCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return null;

    // Pattern 1: explicit indicator "as", "named", "called", "with name", "titled"
    // e.g. "save pdf as biology notes", "export as chapter 1", "save named my document"
    final explicitMatch = RegExp(
      r'(?:save|export|create)\s+(?:the\s+)?(?:pdf|document|file)?\s*(?:as|named|called|with\s+name|titled)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (explicitMatch != null && explicitMatch.group(1) != null) {
      final candidate = cleanPdfName(explicitMatch.group(1)!);
      if (candidate.isNotEmpty) return candidate;
    }

    // Pattern 2: "pdf as <name>" or "pdf named <name>"
    final pdfAsMatch = RegExp(
      r'(?:pdf|document)\s+(?:as|named|called|titled)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (pdfAsMatch != null && pdfAsMatch.group(1) != null) {
      final candidate = cleanPdfName(pdfAsMatch.group(1)!);
      if (candidate.isNotEmpty) return candidate;
    }

    // Pattern 3: "save pdf <name>" or "export pdf <name>" where <name> is at least one word
    // but not command modifiers like "now", "please", "file", "document"
    final savePdfMatch = RegExp(
      r'(?:save|export)\s+(?:the\s+)?(?:pdf|document)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (savePdfMatch != null && savePdfMatch.group(1) != null) {
      final candidate = cleanPdfName(savePdfMatch.group(1)!);
      final lowerCandidate = candidate.toLowerCase();
      if (lowerCandidate != 'now' &&
          lowerCandidate != 'please' &&
          lowerCandidate != 'file' &&
          lowerCandidate != 'document' &&
          candidate.isNotEmpty) {
        return candidate;
      }
    }

    return null;
  }

  /// Result of letterboxing with scaling factor and padding offsets
  static LetterboxResult letterboxDetails(img.Image src, int targetWidth, int targetHeight) {
    final double scale = min(targetWidth / src.width, targetHeight / src.height);
    final int newW = (src.width * scale).round();
    final int newH = (src.height * scale).round();

    final resized = img.copyResize(src, width: newW, height: newH);
    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final int padX = ((targetWidth - newW) / 2).round();
    final int padY = ((targetHeight - newH) / 2).round();

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);
    return LetterboxResult(
      image: canvas,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }

  /// Letterboxes [src] to [targetWidth] x [targetHeight] by maintaining its aspect ratio
  /// and padding the remaining canvas with neutral gray (114, 114, 114).
  /// Preserves Braille cell topology and prevents aspect-ratio distortion across orientations.
  static img.Image letterbox(img.Image src, int targetWidth, int targetHeight) {
    return letterboxDetails(src, targetWidth, targetHeight).image;
  }

  /// Runs YOLOv8 TFLite inference on a 640x640 preprocessed image and returns the raw output tensor.
  List<dynamic> _runInferenceOn640(img.Image image640) {
    final inputTensor = List.generate(
      1,
      (_) => List.generate(
        640,
        (y) => List.generate(
          640,
          (x) {
            final pixel = image640.getPixel(x, y);
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

    _tfliteHelper.interpreter!.run(inputTensor, outputTensor);
    return outputTensor;
  }

  /// Evaluates 4 camera orientations (0°, 270°, 90°, 180°), selects optimal angle,
  /// executes multi-tile high-resolution sliced inference on tall document pages,
  /// and reconstructs text in natural reading order.
  Future<String> _processImageAndRunYoloInference(img.Image originalImage) async {
    List<dynamic> bestOutput = [];
    double bestScore = -1.0;
    int bestAngle = 0;
    LetterboxResult? bestLb;

    // Evaluate 4 possible camera orientations (0°, 270°, 90°, 180°)
    // Selects the orientation with the highest total Braille character detection confidence.
    final candidateAngles = [0, 270, 90, 180];

    for (final angle in candidateAngles) {
      img.Image currentImage = originalImage;
      if (angle != 0) {
        currentImage = img.copyRotate(originalImage, angle: angle);
      }

      // Preserve Braille cell aspect ratio and topology using letterbox padding
      final lb = letterboxDetails(currentImage, 640, 640);
      final outputTensor = _runInferenceOn640(lb.image);

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

      // Upright orientation (0°) is strongly prioritized because camera photos are already
      // auto-oriented upright by EXIF metadata via img.bakeOrientation().
      if (angle == 0) {
        bestScore = currentScore;
        bestAngle = 0;
        bestOutput = outputTensor;
        bestLb = lb;

        // If upright orientation has confident detections (>= 25 characters), lock 0° immediately
        if (detectionCount >= 25) {
          break;
        }
      } else {
        // Only switch away from 0° if the alternate angle has significantly higher confidence (>= 1.6x)
        // or if 0° had almost zero detections (bestScore < 3.0)
        final thresholdScore = bestScore <= 3.0 ? bestScore : bestScore * 1.6;
        if (currentScore > thresholdScore) {
          bestScore = currentScore;
          bestAngle = angle;
          bestOutput = outputTensor;
          bestLb = lb;
        }
      }
    }

    img.Image orientedImage = originalImage;
    if (bestAngle != 0) {
      orientedImage = img.copyRotate(originalImage, angle: bestAngle);
    }

    final int w = orientedImage.width;
    final int h = orientedImage.height;
    final List<BrailleDetection> allCandidates = [];

    // If tall portrait page (H > 1.15 * W), perform high-resolution multi-tile sliced inference
    // This doubles/triples pixel resolution per embossed Braille dot, preventing 640x640 blur.
    if (h > (w * 1.15) && h >= 400) {
      // Slice 1: Top 58% of document height
      final int topH = (h * 0.58).round();
      final cropTop = img.copyCrop(orientedImage, x: 0, y: 0, width: w, height: topH);
      final lbTop = letterboxDetails(cropTop, 640, 640);
      final outTop = _runInferenceOn640(lbTop.image);
      allCandidates.addAll(YoloBrailleDecoder.extractDetections(
        outTop,
        scale: lbTop.scale,
        padX: lbTop.padX.toDouble(),
        padY: lbTop.padY.toDouble(),
        offsetX: 0.0,
        offsetY: 0.0,
        confidenceThreshold: 0.28,
      ));

      // Slice 2: Bottom 58% of document height (16% central seam overlap: 0.42 to 1.0)
      final int bottomY = (h * 0.42).round();
      final int bottomH = h - bottomY;
      final cropBottom = img.copyCrop(orientedImage, x: 0, y: bottomY, width: w, height: bottomH);
      final lbBottom = letterboxDetails(cropBottom, 640, 640);
      final outBottom = _runInferenceOn640(lbBottom.image);
      allCandidates.addAll(YoloBrailleDecoder.extractDetections(
        outBottom,
        scale: lbBottom.scale,
        padX: lbBottom.padX.toDouble(),
        padY: lbBottom.padY.toDouble(),
        offsetX: 0.0,
        offsetY: bottomY.toDouble(),
        confidenceThreshold: 0.28,
      ));

      // Also merge the full-page pass detections for macro-cohesion
      if (bestLb != null && bestOutput.isNotEmpty) {
        allCandidates.addAll(YoloBrailleDecoder.extractDetections(
          bestOutput,
          scale: bestLb.scale,
          padX: bestLb.padX.toDouble(),
          padY: bestLb.padY.toDouble(),
          offsetX: 0.0,
          offsetY: 0.0,
          confidenceThreshold: 0.32,
        ));
      }
    } else {
      // Landscape or square crop: single letterbox pass
      if (bestLb != null && bestOutput.isNotEmpty) {
        allCandidates.addAll(YoloBrailleDecoder.extractDetections(
          bestOutput,
          scale: bestLb.scale,
          padX: bestLb.padX.toDouble(),
          padY: bestLb.padY.toDouble(),
          offsetX: 0.0,
          offsetY: 0.0,
          confidenceThreshold: 0.28,
        ));
      }
    }

    if (allCandidates.isEmpty) {
      return '';
    }

    // Decode unified detections across slices with global NMS and reading-order reconstruction
    return YoloBrailleDecoder.reconstructFromDetections(
      allCandidates,
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
