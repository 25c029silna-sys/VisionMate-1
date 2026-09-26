import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/braille/domain/yolo_braille_decoder.dart';
import 'package:visionmate/features/braille/domain/braille_text_refiner.dart';

void main() {
  group('Braille Pipeline Enhancements - YoloBrailleDecoder', () {
    test('extractDetections projects canvas coordinates back to original image space with offset', () {
      // Create mock raw YOLO output tensor [1, 68, 1]
      // Box at center (320, 320, 40, 60) in 640x640 canvas
      final rawOut = List.generate(
        1,
        (_) => List.generate(
          68,
          (channel) {
            if (channel == 0) return [320.0]; // cx
            if (channel == 1) return [320.0]; // cy
            if (channel == 2) return [40.0];  // w
            if (channel == 3) return [60.0];  // h
            if (channel == 4 + 32) return [0.95]; // class 32 (binary 100000 -> 'a')
            return [0.0];
          },
        ),
      );

      // Letterbox with scale = 0.5, padX = 20, padY = 50, and slice offsetY = 400
      final detections = YoloBrailleDecoder.extractDetections(
        rawOut,
        scale: 0.5,
        padX: 20.0,
        padY: 50.0,
        offsetX: 0.0,
        offsetY: 400.0,
        confidenceThreshold: 0.25,
      );

      expect(detections.length, 1);
      final d = detections.first;
      expect(d.classIndex, 32);
      expect(d.binaryCode, '100000');
      // x1 = (300 - 20) / 0.5 = 560
      expect(d.x1, closeTo(560.0, 0.1));
      // y1 = (290 - 50) / 0.5 + 400 = 480 + 400 = 880
      expect(d.y1, closeTo(880.0, 0.1));
    });

    test('reconstructFromDetections groups detections into reading order and eliminates duplicate NMS boxes', () {
      // 2 overlapping detections for the same character in the seam
      final d1 = BrailleDetection(
        x1: 100, y1: 100, x2: 140, y2: 160,
        cx: 120, cy: 130, width: 40, height: 60,
        classIndex: 32, confidence: 0.90, binaryCode: '100000', // 'a'
      );
      final d2 = BrailleDetection(
        x1: 102, y1: 101, x2: 141, y2: 161,
        cx: 121, cy: 131, width: 39, height: 60,
        classIndex: 32, confidence: 0.95, binaryCode: '100000', // 'a' (duplicate)
      );
      final d3 = BrailleDetection(
        x1: 160, y1: 100, x2: 200, y2: 160,
        cx: 180, cy: 130, width: 40, height: 60,
        classIndex: 48, confidence: 0.92, binaryCode: '110000', // 'b'
      );

      final text = YoloBrailleDecoder.reconstructFromDetections([d1, d2, d3], iouThreshold: 0.40);
      expect(text, 'ab');
    });

    test('reconstructFromDetections inserts word space when gap >= 1.55 * medianW', () {
      // Word 1: "a" at cx = 100, width = 40
      final d1 = BrailleDetection(
        x1: 80, y1: 100, x2: 120, y2: 160,
        cx: 100, cy: 130, width: 40, height: 60,
        classIndex: 32, confidence: 0.90, binaryCode: '100000', // 'a'
      );
      // Word 2: "b" at cx = 180 (gap cx - lastCx = 80 >= 1.55 * 40 = 62)
      final d2 = BrailleDetection(
        x1: 160, y1: 100, x2: 200, y2: 160,
        cx: 180, cy: 130, width: 40, height: 60,
        classIndex: 48, confidence: 0.90, binaryCode: '110000', // 'b'
      );

      final text = YoloBrailleDecoder.reconstructFromDetections([d1, d2], iouThreshold: 0.40);
      expect(text, 'a b');
    });

    test('extractDetections retains class 32 (letter a) with normal confidence >= 0.28', () {
      final rawOut = List.generate(
        1,
        (_) => List.generate(
          68,
          (channel) {
            if (channel == 0) return [320.0];
            if (channel == 1) return [320.0];
            if (channel == 2) return [40.0];
            if (channel == 3) return [60.0];
            if (channel == 4 + 32) return [0.35]; // Confidence 0.35 (< 0.48, but >= 0.28)
            return [0.0];
          },
        ),
      );

      final detections = YoloBrailleDecoder.extractDetections(
        rawOut,
        confidenceThreshold: 0.28,
      );

      expect(detections.length, 1);
      expect(detections.first.classIndex, 32);
      expect(detections.first.binaryCode, '100000');
    });
  });

  group('Braille Pipeline Enhancements - BrailleTextRefiner', () {
    test('does not use custom dictionary substitutions', () {
      final input = 'fr and chn cd go to rm';
      final refined = BrailleTextRefiner.refineOffline(input);
      // Confirms custom dictionaries (which expanded 'fr' -> 'friends', 'c' -> 'can') are removed
      expect(refined, equals('fr and chn cd go to rm'));
    });

    test('preserves raw letters and does not expand single letters without liblouis', () {
      final input = 'c y go to rm';
      final refined = BrailleTextRefiner.refineOffline(input);
      expect(refined, equals('c y go to rm'));
    });

    test('context guards single-letter words on noise-heavy lines', () {
      // Line with noise should not turn 'e' into 'every', 'm' into 'more', 'd' into 'do'
      final noisyLine = 'e 15 uncqou m ade d';
      final refined = BrailleTextRefiner.refineOffline(noisyLine);
      expect(refined.contains('every'), isFalse);
      expect(refined.contains('more'), isFalse);
    });

    test('filters out pure noise lines', () {
      final input = '''
swami and friends
u::
x'' sha
o
it was monday morning
::
''';
      final refined = BrailleTextRefiner.refineOffline(input);
      final lines = refined.split('\n');
      expect(lines.any((l) => l == 'u::'), isFalse);
      expect(lines.any((l) => l == 'o'), isFalse);
      expect(refined, contains('swami and friends'));
      expect(refined, contains('it was monday morning'));
    });
  });
}
