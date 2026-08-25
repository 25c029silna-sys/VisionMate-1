import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';

void main() {
  group('SceneService NMS, Audio Cooldown & Scene Summary Tests', () {
    late SceneService sceneService;

    setUp(() {
      sceneService = SceneService();
    });

    test('estimateDistanceMeters calculates accurate distance in meters based on height', () {
      // Person (1.7m real height) filling 50% of the screen height (h = 0.5)
      // d = 1.10 * 1.70 / 0.5 = 3.74 -> 3.7 meters
      final personDist = SceneService.estimateDistanceMeters('person', 0.5);
      expect(personDist, equals(3.7));

      // Chair (0.85m real height) filling 85% of screen height (h = 0.85)
      // d = 1.10 * 0.85 / 0.85 = 1.1 meters
      final chairDist = SceneService.estimateDistanceMeters('chair', 0.85);
      expect(chairDist, equals(1.1));

      // Table (0.75m real height) filling 25% of screen height (h = 0.25)
      // d = 1.10 * 0.75 / 0.25 = 3.3 meters
      final tableDist = SceneService.estimateDistanceMeters('dining table', 0.25);
      expect(tableDist, equals(3.3));

      // Clamping limits
      final veryClose = SceneService.estimateDistanceMeters('chair', 1.0);
      expect(veryClose, greaterThanOrEqualTo(0.3));

      final veryFar = SceneService.estimateDistanceMeters('person', 0.01);
      expect(veryFar, lessThanOrEqualTo(15.0));
    });

    test('preprocessLetterbox preserves aspect ratio and pads correctly without distortion', () {
      // Create a 4:3 image (800x600)
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));

      final preprocessed = SceneService.preprocessLetterbox(image, targetWidth: 300, targetHeight: 300);

      expect(preprocessed.inputTensor.length, equals(1));
      expect(preprocessed.inputTensor[0].length, equals(300));
      expect(preprocessed.inputTensor[0][0].length, equals(300));
      expect(preprocessed.inputTensor[0][0][0].length, equals(3));

      // Aspect ratio of 800x600 scaled to 300x300 has scale = 300/800 = 0.375
      // scaledW = 300, scaledH = 225
      // padX = 0, padY = (300 - 225) / 2 / 300 = 37 / 300 = 0.1233
      expect(preprocessed.padX, equals(0.0));
      expect(preprocessed.padY, greaterThan(0.0));
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

    test('generateSceneSummary returns warning with metric distance for close obstacles', () {
      final closeObstacle = DetectedObstacle(
        label: 'stairs',
        confidence: 0.95,
        x: 0,
        y: 0,
        width: 0.8,
        height: 0.8,
        distanceMeters: 0.8,
        distanceCategory: 'close',
      );

      final summary = sceneService.generateSceneSummary([closeObstacle]);
      expect(summary, contains('Warning: stairs, 0.8 meters detected right in front of you.'));
    });

    test('generateSceneSummary returns clear path when no obstacles detected', () {
      final summary = sceneService.generateSceneSummary([]);
      expect(summary, equals('The path ahead appears clear of obstacles.'));
    });

    test('generateSceneSummary includes spatial directions and metric distances for medium and far obstacles', () {
      final obstacles = [
        DetectedObstacle(
          label: 'table',
          confidence: 0.88,
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          distanceMeters: 2.1,
          distanceCategory: 'medium',
          positionCategory: 'on your left',
        ),
        DetectedObstacle(
          label: 'door',
          confidence: 0.92,
          x: 0.8,
          y: 0.1,
          width: 0.15,
          height: 0.3,
          distanceMeters: 4.5,
          distanceCategory: 'far',
          positionCategory: 'on your right',
        ),
      ];

      final summary = sceneService.generateSceneSummary(obstacles);
      expect(summary, contains('table, 2.1 meters on your left'));
      expect(summary, contains('door, 4.5 meters on your right'));
    });
  });
}

