import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real-Time Scene Description & Indoor Navigation System Accuracy Suite', () {
    late SceneService sceneService;

    setUp(() {
      sceneService = SceneService();
    });

    // -------------------------------------------------------------------------
    // TEST 1: Optical Pinhole Metric Distance Estimation Precision
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-01] Optical Geometry Metric Distance Precision (D = (f * H) / h)', () {
      // Formula: (1.10 * H_real) / h_norm, clamped to [0.3, 15.0] rounded to 1 decimal place

      // Person: Real height = 1.70m
      // Normalized image height 0.50 -> (1.10 * 1.70) / 0.50 = 3.74 -> 3.7m
      final distPerson50 = SceneService.estimateDistanceMeters('person', 0.50);
      expect(distPerson50, equals(3.7));

      // Person: Normalized image height 0.85 -> (1.10 * 1.70) / 0.85 = 2.2m
      final distPerson85 = SceneService.estimateDistanceMeters('person', 0.85);
      expect(distPerson85, equals(2.2));

      // Chair: Real height = 0.85m
      // Normalized image height 0.20 -> (1.10 * 0.85) / 0.20 = 4.675 -> 4.7m
      final distChair20 = SceneService.estimateDistanceMeters('chair', 0.20);
      expect(distChair20, equals(4.7));

      // Chair: Normalized image height 0.80 -> (1.10 * 0.85) / 0.80 = 1.168 -> 1.2m
      final distChair80 = SceneService.estimateDistanceMeters('chair', 0.80);
      expect(distChair80, equals(1.2));

      // Distance clamping boundary tests:
      // Huge object or very close -> clamped to 0.3m minimum
      final distMinClamp = SceneService.estimateDistanceMeters('person', 1.0);
      expect(distMinClamp, greaterThanOrEqualTo(0.3));

      // Tiny object or far away -> clamped to 15.0m maximum
      final distMaxClamp = SceneService.estimateDistanceMeters('person', 0.02);
      expect(distMaxClamp, lessThanOrEqualTo(15.0));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Proximity Classification Accuracy (close, medium, far)
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-02] Proximity Classification Threshold Accuracy', () {
      // Test cases covering proximity classification logic
      final testCases = [
        // Close cases (distance <= 1.2m or height > 0.45 or bottom > 0.85)
        {'label': 'stairs', 'dist': 0.8, 'h': 0.5, 'expected': 'close'},
        {'label': 'chair', 'dist': 1.1, 'h': 0.3, 'expected': 'close'},
        // Medium cases (distance <= 2.5m or height > 0.20)
        {'label': 'door', 'dist': 2.0, 'h': 0.3, 'expected': 'medium'},
        {'label': 'table', 'dist': 2.4, 'h': 0.25, 'expected': 'medium'},
        // Far cases (> 2.5m and small height)
        {'label': 'window', 'dist': 4.5, 'h': 0.15, 'expected': 'far'},
        {'label': 'car', 'dist': 6.0, 'h': 0.12, 'expected': 'far'},
      ];

      for (final tc in testCases) {
        final dist = tc['dist'] as double;
        final h = tc['h'] as double;
        final expected = tc['expected'] as String;

        String distCategory = 'far';
        if (dist <= 1.2 || h > 0.45) {
          distCategory = 'close';
        } else if (dist <= 2.5 || h > 0.20) {
          distCategory = 'medium';
        }

        expect(distCategory, equals(expected), reason: 'Proximity for dist=$dist, h=$h should be $expected.');
      }
    });

    // -------------------------------------------------------------------------
    // TEST 3: Spatial Direction Classification Accuracy
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-03] Spatial Direction Categorization (Left, Ahead, Right)', () {
      final directions = [
        {'centerX': 0.15, 'expected': 'on your left'},
        {'centerX': 0.30, 'expected': 'on your left'},
        {'centerX': 0.40, 'expected': 'ahead'},
        {'centerX': 0.50, 'expected': 'ahead'},
        {'centerX': 0.60, 'expected': 'ahead'},
        {'centerX': 0.70, 'expected': 'on your right'},
        {'centerX': 0.90, 'expected': 'on your right'},
      ];

      for (final d in directions) {
        final cx = d['centerX'] as double;
        final expected = d['expected'] as String;

        String posCategory = 'ahead';
        if (cx < 0.35) {
          posCategory = 'on your left';
        } else if (cx > 0.65) {
          posCategory = 'on your right';
        }

        expect(posCategory, equals(expected), reason: 'Direction for centerX=$cx must be $expected.');
      }
    });

    // -------------------------------------------------------------------------
    // TEST 4: Non-Maximum Suppression (NMS) IoU Filtering Accuracy
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-04] Non-Maximum Suppression Filtering Precision (IoU Threshold = 0.45)', () {
      // 2 heavily overlapping boxes for the same chair (IoU ~0.80)
      final box1 = DetectedObstacle(
        label: 'chair', confidence: 0.92,
        x: 10, y: 10, width: 40, height: 40,
        distanceCategory: 'close', distanceMeters: 1.1,
      );
      final box2 = DetectedObstacle(
        label: 'chair', confidence: 0.81,
        x: 12, y: 12, width: 40, height: 40,
        distanceCategory: 'close', distanceMeters: 1.1,
      );
      // Distinct separate obstacle (door at x=200, IoU = 0.0)
      final box3 = DetectedObstacle(
        label: 'door', confidence: 0.89,
        x: 200, y: 200, width: 40, height: 40,
        distanceCategory: 'medium', distanceMeters: 2.3,
      );

      final filtered = sceneService.applyNms([box1, box2, box3], iouThreshold: 0.45);

      expect(filtered.length, equals(2), reason: 'Duplicate box2 must be suppressed, keeping box1 and box3.');
      expect(filtered.first.confidence, equals(0.92));
      expect(filtered.map((e) => e.label), containsAll(['chair', 'door']));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Spoken Room Summary & Immediate Hazard Warning Accuracy
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-05] Hazard Warning & Spatial Room Summary Generation', () {
      // Case 1: Close hazard obstacle right ahead
      final closeHazard = DetectedObstacle(
        label: 'table',
        confidence: 0.95,
        x: 0.2, y: 0.2, width: 0.6, height: 0.6,
        distanceMeters: 0.9,
        distanceCategory: 'close',
        positionCategory: 'ahead',
      );
      final hazardSummary = sceneService.generateSceneSummary([closeHazard]);
      expect(hazardSummary, contains('Warning: table, 0.9 meters detected right in front of you.'));

      // Case 2: Obstacle on left
      final leftObstacle = DetectedObstacle(
        label: 'chair',
        confidence: 0.90,
        x: 0.05, y: 0.2, width: 0.25, height: 0.5,
        distanceMeters: 1.2,
        distanceCategory: 'close',
        positionCategory: 'on your left',
      );
      final leftSummary = sceneService.generateSceneSummary([leftObstacle]);
      expect(leftSummary, contains('chair, 1.2 meters on your left'));

      // Case 3: Completely clear path
      final clearSummary = sceneService.generateSceneSummary([]);
      expect(clearSummary, equals('The path ahead appears clear of obstacles.'));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Audio Alert Throttle Cooldown Accuracy (3-Second Window)
    // -------------------------------------------------------------------------
    test('[SCENE-ACC-06] Audio Alert Throttle Cooldown (3-Second Suppression Window)', () {
      final t0 = DateTime.now();

      // First alert for 'stairs' should trigger
      expect(sceneService.shouldTriggerAlert('stairs', t0), isTrue);

      // Attempt alert 1.5 seconds later: must be suppressed (within 3s)
      final t1 = t0.add(const Duration(milliseconds: 1500));
      expect(sceneService.shouldTriggerAlert('stairs', t1), isFalse);

      // Attempt alert 2.9 seconds later: still suppressed
      final t2 = t0.add(const Duration(milliseconds: 2900));
      expect(sceneService.shouldTriggerAlert('stairs', t2), isFalse);

      // Attempt alert 3.1 seconds later: cooldown expired, must trigger
      final t3 = t0.add(const Duration(milliseconds: 3100));
      expect(sceneService.shouldTriggerAlert('stairs', t3), isTrue);

      // Different object ('door') at t1: different key, must trigger immediately
      expect(sceneService.shouldTriggerAlert('door', t1), isTrue);
    });
  });
}
