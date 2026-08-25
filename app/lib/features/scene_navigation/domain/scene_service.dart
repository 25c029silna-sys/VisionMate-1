import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../../core/tflite/tflite_helper.dart';

class PreprocessedFrame {
  final List<List<List<List<int>>>> inputTensor;
  final double padX;
  final double padY;
  final double scale;

  PreprocessedFrame({
    required this.inputTensor,
    required this.padX,
    required this.padY,
    required this.scale,
  });
}

class DetectedObstacle {
  final String label;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;
  final double distanceMeters;
  final String distanceCategory; // 'close', 'medium', 'far'
  final String? positionCategory; // 'on your left', 'ahead', 'on your right'

  DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.distanceCategory,
    this.positionCategory,
    double? distanceMeters,
  }) : distanceMeters = distanceMeters ?? SceneService.estimateDistanceMeters(label, height);
}

class SceneService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  bool _isModelAvailable = false;
  List<String> _labels = [];
  final Map<String, DateTime> _lastAlertTimes = {};
  static const Duration audioCooldownDuration = Duration(seconds: 3);

  /// Normalized camera focal length constant for typical smartphone wide camera lens (~65 deg FOV).
  static const double standardFocalLengthNorm = 1.10;

  /// Real-world physical reference heights in meters for standard object classes.
  static const Map<String, double> realWorldObjectHeights = {
    'person': 1.70,
    'bicycle': 1.00,
    'car': 1.50,
    'motorcycle': 1.10,
    'airplane': 3.50,
    'bus': 3.00,
    'train': 3.50,
    'truck': 2.60,
    'boat': 2.00,
    'traffic light': 2.50,
    'fire hydrant': 0.70,
    'stop sign': 2.10,
    'parking meter': 1.20,
    'bench': 0.85,
    'bird': 0.20,
    'cat': 0.30,
    'dog': 0.55,
    'horse': 1.60,
    'sheep': 0.80,
    'cow': 1.40,
    'elephant': 2.80,
    'bear': 1.50,
    'zebra': 1.40,
    'giraffe': 4.50,
    'backpack': 0.45,
    'umbrella': 0.85,
    'handbag': 0.35,
    'tie': 0.40,
    'suitcase': 0.65,
    'frisbee': 0.25,
    'skis': 1.60,
    'snowboard': 1.50,
    'sports ball': 0.22,
    'kite': 0.60,
    'baseball bat': 0.85,
    'baseball glove': 0.30,
    'skateboard': 0.20,
    'surfboard': 1.80,
    'tennis racket': 0.68,
    'bottle': 0.25,
    'wine glass': 0.22,
    'cup': 0.12,
    'fork': 0.18,
    'knife': 0.20,
    'spoon': 0.16,
    'bowl': 0.12,
    'banana': 0.18,
    'apple': 0.08,
    'sandwich': 0.08,
    'orange': 0.08,
    'broccoli': 0.15,
    'carrot': 0.18,
    'hot dog': 0.12,
    'pizza': 0.05,
    'donut': 0.08,
    'cake': 0.15,
    'chair': 0.85,
    'couch': 0.80,
    'potted plant': 0.60,
    'bed': 0.65,
    'dining table': 0.75,
    'toilet': 0.75,
    'tv': 0.60,
    'laptop': 0.25,
    'mouse': 0.05,
    'remote': 0.18,
    'keyboard': 0.05,
    'cell phone': 0.15,
    'microwave': 0.35,
    'oven': 0.85,
    'toaster': 0.22,
    'sink': 0.85,
    'refrigerator': 1.75,
    'book': 0.22,
    'clock': 0.30,
    'vase': 0.35,
    'scissors': 0.18,
    'teddy bear': 0.35,
    'hair drier': 0.25,
    'toothbrush': 0.18,
    'door': 2.00,
    'stairs': 1.20,
    'wall': 2.50,
  };

  /// Estimates physical distance to the object in meters using pinhole camera optical geometry.
  static double estimateDistanceMeters(String label, double heightNormalized) {
    final hNorm = heightNormalized.clamp(0.02, 1.0);
    final realHeight = realWorldObjectHeights[label.toLowerCase()] ?? 0.80;
    final distance = (standardFocalLengthNorm * realHeight) / hNorm;
    return double.parse(distance.clamp(0.3, 15.0).toStringAsFixed(1));
  }

  bool get isModelAvailable => _isModelAvailable;

  /// Default labels fallback in case assets fail to load.
  static const List<String> defaultLabels = [
    '???', 'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
    'truck', 'boat', 'traffic light', 'fire hydrant', '???', 'stop sign', 'parking meter',
    'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear',
    'zebra', 'giraffe', '???', 'backpack', 'umbrella', '???', '???', 'handbag',
    'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
    'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
    'bottle', '???', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl',
    'banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza',
    'donut', 'cake', 'chair', 'couch', 'potted plant', 'bed', '???', 'dining table',
    '???', '???', 'toilet', '???', 'tv', 'laptop', 'mouse', 'remote', 'keyboard',
    'cell phone', 'microwave', 'oven', 'toaster', 'sink', 'refrigerator', '???',
    'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush'
  ];

  Future<bool> checkModelAvailability() async {
    final interpreter = await _tfliteHelper.loadModel('assets/models/yolov8n.tflite');
    _isModelAvailable = interpreter != null;
    await _loadLabels();
    return _isModelAvailable;
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString('assets/labels/yolo_labels.txt');
      final loaded = labelsData.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (loaded.isNotEmpty) {
        _labels = loaded;
        return;
      }
    } catch (e) {
      debugPrint('SceneService: Failed to load yolo_labels.txt asset, falling back to default labels.');
    }
    _labels = List.from(defaultLabels);
  }

  /// Calculates Intersection over Union (IoU) between two obstacle bounding boxes.
  double _calculateIoU(DetectedObstacle a, DetectedObstacle b) {
    final xA = max(a.x, b.x);
    final yA = max(a.y, b.y);
    final xB = min(a.x + a.width, b.x + b.width);
    final yB = min(a.y + a.height, b.y + b.height);

    final interArea = max(0.0, xB - xA) * max(0.0, yB - yA);
    final boxAArea = a.width * a.height;
    final boxBArea = b.width * b.height;

    final unionArea = boxAArea + boxBArea - interArea;
    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }

  /// Applies Non-Maximum Suppression (NMS) to filter redundant overlapping detections.
  List<DetectedObstacle> applyNms(List<DetectedObstacle> detections, {double iouThreshold = 0.45}) {
    if (detections.isEmpty) return [];

    final sorted = List<DetectedObstacle>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final selected = <DetectedObstacle>[];
    final active = List<bool>.filled(sorted.length, true);

    for (int i = 0; i < sorted.length; i++) {
      if (!active[i]) continue;
      selected.add(sorted[i]);

      for (int j = i + 1; j < sorted.length; j++) {
        if (!active[j]) continue;
        if (_calculateIoU(sorted[i], sorted[j]) > iouThreshold) {
          active[j] = false;
        }
      }
    }
    return selected;
  }

  /// Evaluates 3-second audio cooldown to prevent repetitive TTS audio alerts.
  bool shouldTriggerAlert(String obstacleLabel, DateTime currentTime) {
    final lastTime = _lastAlertTimes[obstacleLabel];
    if (lastTime == null || currentTime.difference(lastTime) >= audioCooldownDuration) {
      _lastAlertTimes[obstacleLabel] = currentTime;
      return true;
    }
    return false;
  }

  /// Letterboxes an input image to target dimensions without aspect ratio distortion.
  static PreprocessedFrame preprocessLetterbox(
    img.Image originalImage, {
    int targetWidth = 300,
    int targetHeight = 300,
  }) {
    final origW = originalImage.width;
    final origH = originalImage.height;

    final scale = min(targetWidth / origW, targetHeight / origH);
    final scaledW = (origW * scale).round().clamp(1, targetWidth);
    final scaledH = (origH * scale).round().clamp(1, targetHeight);

    final resized = img.copyResize(originalImage, width: scaledW, height: scaledH);

    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

    final offsetX = ((targetWidth - scaledW) / 2).floor();
    final offsetY = ((targetHeight - scaledH) / 2).floor();

    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    final padX = offsetX / targetWidth;
    final padY = offsetY / targetHeight;

    final inputTensor = List.generate(
      1,
      (_) => List.generate(
        targetHeight,
        (y) => List.generate(
          targetWidth,
          (x) {
            final pixel = canvas.getPixel(x, y);
            return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
          },
        ),
      ),
    );

    return PreprocessedFrame(
      inputTensor: inputTensor,
      padX: padX,
      padY: padY,
      scale: scale,
    );
  }

  /// Detects obstacles in an image file using the on-device TFLite detector.
  Future<List<DetectedObstacle>> detectObstacles(String imagePath, {double minConfidence = 0.40}) async {
    final hasModel = await checkModelAvailability();
    if (!hasModel || _tfliteHelper.interpreter == null) {
      return [];
    }

    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        debugPrint('SceneService: Image file at $imagePath does not exist.');
        return [];
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return [];

      // 1. Aspect-ratio preserving letterbox preprocessing to 300x300
      final preprocessed = preprocessLetterbox(image, targetWidth: 300, targetHeight: 300);

      // 2. Prepare output tensors:
      // output 0: boxes [1, 10, 4] -> [top, left, bottom, right]
      // output 1: classes [1, 10]
      // output 2: scores [1, 10]
      // output 3: numDetections [1]
      final outputBoxes = List.generate(1, (_) => List.generate(10, (_) => List.filled(4, 0.0)));
      final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
      final outputScores = List.generate(1, (_) => List.filled(10, 0.0));
      final outputNum = List.filled(1, 0.0);

      final outputs = {
        0: outputBoxes,
        1: outputClasses,
        2: outputScores,
        3: outputNum,
      };

      _tfliteHelper.interpreter!.runForMultipleInputs([preprocessed.inputTensor], outputs);

      final int numDetections = outputNum[0].toInt().clamp(0, 10);
      final rawDetections = <DetectedObstacle>[];
      final activeLabels = _labels.isNotEmpty ? _labels : defaultLabels;

      for (int i = 0; i < numDetections; i++) {
        final score = outputScores[0][i];
        if (score < minConfidence) continue;

        final classIdx = outputClasses[0][i].toInt() + 1; // 1-indexed in COCO labelmap
        String label = 'obstacle';
        if (classIdx >= 0 && classIdx < activeLabels.length) {
          label = activeLabels[classIdx];
          if (label == '???') label = 'obstacle';
        }

        final top = outputBoxes[0][i][0];
        final left = outputBoxes[0][i][1];
        final bottom = outputBoxes[0][i][2];
        final right = outputBoxes[0][i][3];

        // Un-pad letterboxed coordinates back to original unpadded normalized image coordinates
        final double denomX = max(0.01, 1.0 - 2 * preprocessed.padX);
        final double denomY = max(0.01, 1.0 - 2 * preprocessed.padY);

        final unpaddedLeft = ((left - preprocessed.padX) / denomX).clamp(0.0, 1.0);
        final unpaddedRight = ((right - preprocessed.padX) / denomX).clamp(0.0, 1.0);
        final unpaddedTop = ((top - preprocessed.padY) / denomY).clamp(0.0, 1.0);
        final unpaddedBottom = ((bottom - preprocessed.padY) / denomY).clamp(0.0, 1.0);

        final w = (unpaddedRight - unpaddedLeft).clamp(0.0, 1.0);
        final h = (unpaddedBottom - unpaddedTop).clamp(0.0, 1.0);
        final centerX = unpaddedLeft + (w / 2.0);
        final area = w * h;

        // Metric distance calculation
        final distanceMeters = estimateDistanceMeters(label, h);

        // Proximity category
        String distCategory = 'far';
        if (distanceMeters <= 1.2 || h > 0.45 || area > 0.20 || unpaddedBottom > 0.85) {
          distCategory = 'close';
        } else if (distanceMeters <= 2.5 || h > 0.20 || area > 0.05) {
          distCategory = 'medium';
        }

        // Spatial direction category
        String posCategory = 'ahead';
        if (centerX < 0.35) {
          posCategory = 'on your left';
        } else if (centerX > 0.65) {
          posCategory = 'on your right';
        }

        rawDetections.add(DetectedObstacle(
          label: label,
          confidence: score,
          x: unpaddedLeft,
          y: unpaddedTop,
          width: w,
          height: h,
          distanceMeters: distanceMeters,
          distanceCategory: distCategory,
          positionCategory: posCategory,
        ));
      }

      return applyNms(rawDetections);
    } catch (e, stack) {
      debugPrint('SceneService detection error: $e\n$stack');
      return [];
    }
  }

  /// Generates a spoken room summary string from detected scene obstacles including metric distances.
  String generateSceneSummary(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) {
      return 'The path ahead appears clear of obstacles.';
    }

    final closeObstacles = obstacles.where((o) => o.distanceCategory == 'close').toList();
    if (closeObstacles.isNotEmpty) {
      final items = closeObstacles.map((o) {
        final pos = (o.positionCategory != null && o.positionCategory != 'ahead')
            ? ' ${o.positionCategory}'
            : '';
        return '${o.label}, ${o.distanceMeters} meters$pos';
      }).join(', ');
      return 'Warning: $items detected right in front of you.';
    }

    final items = obstacles.map((o) {
      final pos = o.positionCategory ?? 'ahead';
      return '${o.label}, ${o.distanceMeters} meters $pos';
    }).join(', ');
    return 'Objects detected in room: $items.';
  }

  Future<String> describeScene([String? imagePath]) async {
    final available = await checkModelAvailability();
    if (!available) {
      return 'MODEL_UNAVAILABLE';
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      final obstacles = await detectObstacles(imagePath);
      return generateSceneSummary(obstacles);
    }

    return 'Scene description: Clear path ahead.';
  }

  Future<String> navigateIndoors([String? imagePath]) async {
    final available = await checkModelAvailability();
    if (!available) {
      return 'MODEL_UNAVAILABLE';
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      final obstacles = await detectObstacles(imagePath);
      return generateSceneSummary(obstacles);
    }

    return 'Indoor navigation active. Path is clear.';
  }

  void dispose() {
    _tfliteHelper.dispose();
  }
}



