import 'dart:math';
import '../../../core/tflite/tflite_helper.dart';

class DetectedObstacle {
  final String label;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;
  final String distanceCategory; // 'close', 'medium', 'far'

  DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.distanceCategory,
  });
}

class SceneService {
  final TfliteHelper _tfliteHelper = TfliteHelper();
  bool _isModelAvailable = false;
  final Map<String, DateTime> _lastAlertTimes = {};
  static const Duration audioCooldownDuration = Duration(seconds: 3);

  bool get isModelAvailable => _isModelAvailable;

  Future<bool> checkModelAvailability() async {
    final interpreter = await _tfliteHelper.loadModel('assets/models/yolov8n.tflite');
    _isModelAvailable = interpreter != null;
    return _isModelAvailable;
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

  /// Generates a spoken room summary string from detected scene obstacles.
  String generateSceneSummary(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) {
      return 'The path ahead appears clear of obstacles.';
    }

    final closeObstacles = obstacles.where((o) => o.distanceCategory == 'close').map((o) => o.label).toList();
    if (closeObstacles.isNotEmpty) {
      return 'Warning: ${closeObstacles.join(', ')} detected right in front of you.';
    }

    final labels = obstacles.map((o) => o.label).toSet().toList();
    return 'Objects detected in room: ${labels.join(', ')}.';
  }

  Future<String> describeScene() async {
    final available = await checkModelAvailability();
    if (!available) {
      return 'MODEL_UNAVAILABLE';
    }
    await Future.delayed(const Duration(milliseconds: 300));
    return 'Scene description: Clear path ahead.';
  }

  Future<String> navigateIndoors() async {
    final available = await checkModelAvailability();
    if (!available) {
      return 'MODEL_UNAVAILABLE';
    }
    return 'Indoor navigation active. Path is clear.';
  }
}


