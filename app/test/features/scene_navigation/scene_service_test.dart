import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';

void main() {
  group('SceneService NMS, Audio Cooldown & Scene Summary Tests', () {
    late SceneService sceneService;

    setUp(() {
      sceneService = SceneService();
    });

    test('applyNms suppresses overlapping bounding boxes above IoU threshold', () {
      final box1 = DetectedObstacle(
        label: 'chair',
        confidence: 0.90,
        x: 10,
        y: 10,
        width: 50,
        height: 50,
        distanceCategory: 'close',
      );

      // Highly overlapping box (IoU > 0.8)
      final box2 = DetectedObstacle(
        label: 'chair',
        confidence: 0.75,
        x: 12,
        y: 12,
        width: 50,
        height: 50,
        distanceCategory: 'close',
      );

      // Non-overlapping box
      final box3 = DetectedObstacle(
        label: 'door',
        confidence: 0.85,
        x: 200,
        y: 200,
        width: 50,
        height: 50,
        distanceCategory: 'far',
      );

      final nmsResults = sceneService.applyNms([box1, box2, box3]);
      expect(nmsResults, hasLength(2));
      expect(nmsResults.first.label, equals('chair'));
      expect(nmsResults.last.label, equals('door'));
    });

    test('shouldTriggerAlert respects 3-second audio cooldown window', () {
      final now = DateTime.now();

      // First alert for 'chair' -> Should trigger
      expect(sceneService.shouldTriggerAlert('chair', now), isTrue);

      // Repeated alert after 1 second -> Should be suppressed by cooldown
      expect(sceneService.shouldTriggerAlert('chair', now.add(const Duration(seconds: 1))), isFalse);

      // Repeated alert after 3.5 seconds -> Should trigger
      expect(sceneService.shouldTriggerAlert('chair', now.add(const Duration(milliseconds: 3500))), isTrue);
    });

    test('generateSceneSummary returns warning for close obstacles', () {
      final closeObstacle = DetectedObstacle(
        label: 'stairs',
        confidence: 0.95,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        distanceCategory: 'close',
      );

      final summary = sceneService.generateSceneSummary([closeObstacle]);
      expect(summary, contains('Warning: stairs detected right in front of you.'));
    });
  });
}
