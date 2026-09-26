import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/domain/printed_braille_detector.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';

/// Helper to render synthetic printed Braille characters onto an in-memory canvas.
/// Standard 2x3 column-major mapping:
/// Dot 1: row 0, col 0 | Dot 4: row 0, col 1
/// Dot 2: row 1, col 0 | Dot 5: row 1, col 1
/// Dot 3: row 2, col 0 | Dot 6: row 2, col 1
img.Image renderSyntheticPrintedBraille(
  List<List<int>> wordsDots, {
  bool inverted = false,
  double dotPitch = 24.0,
  int dotRadius = 5,
}) {
  const int width = 500;
  const int height = 250;
  final canvas = img.Image(width: width, height: height);

  final bgColor = inverted ? img.ColorRgb8(20, 20, 20) : img.ColorRgb8(245, 245, 245);
  final dotColor = inverted ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(15, 15, 15);

  img.fill(canvas, color: bgColor);

  double startX = 60.0;
  final double startY = 80.0;
  final double interCellPitch = dotPitch * 2.3;

  for (final cellDots in wordsDots) {
    if (cellDots.isEmpty) {
      // Space between words corresponds to an empty cell
      startX += interCellPitch;
      continue;
    }

    for (final dotNum in cellDots) {
      int row = 0;
      int col = 0;
      switch (dotNum) {
        case 1: row = 0; col = 0; break;
        case 2: row = 1; col = 0; break;
        case 3: row = 2; col = 0; break;
        case 4: row = 0; col = 1; break;
        case 5: row = 1; col = 1; break;
        case 6: row = 2; col = 1; break;
      }

      final cx = (startX + col * dotPitch).round();
      final cy = (startY + row * dotPitch).round();

      img.fillCircle(canvas, x: cx, y: cy, radius: dotRadius, color: dotColor);
    }

    startX += interCellPitch;
  }

  return canvas;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrintedBrailleDetector Unit & Integration Tests', () {
    test('grade1Map correctly maps standard English Braille alphabet and numbers', () {
      expect(PrintedBrailleDetector.grade1Map['100000'], 'a');
      expect(PrintedBrailleDetector.grade1Map['110000'], 'b');
      expect(PrintedBrailleDetector.grade1Map['100100'], 'c');
      expect(PrintedBrailleDetector.grade1Map['111000'], 'l');
      expect(PrintedBrailleDetector.grade1Map['001111'], '#');
      expect(PrintedBrailleDetector.grade1Map['000001'], ',');
    });

    test('suppressOverlappingDots suppresses duplicate nearby centroids', () {
      final dots = [
        PrintedDot(x: 100.0, y: 100.0, radius: 5.0, area: 78.5, circularity: 0.90),
        PrintedDot(x: 101.5, y: 101.0, radius: 5.0, area: 78.5, circularity: 0.82), // Duplicate
        PrintedDot(x: 150.0, y: 100.0, radius: 5.0, area: 78.5, circularity: 0.88), // Distinct
      ];

      final kept = PrintedBrailleDetector.suppressOverlappingDots(dots);
      expect(kept.length, 2);
      expect(kept.first.x, closeTo(100.0, 0.1));
      expect(kept.last.x, closeTo(150.0, 0.1));
    });

    test('rejects linear and rectangular noise while preserving circular dots', () {
      const int width = 300;
      const int height = 200;
      final canvas = img.Image(width: width, height: height);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

      // 1. Genuine circular dot at (100, 100)
      img.fillCircle(canvas, x: 100, y: 100, radius: 7, color: img.ColorRgb8(0, 0, 0));

      // 2. Long non-circular line at (200, 50..150)
      img.fillRect(canvas, x1: 200, y1: 50, x2: 202, y2: 150, color: img.ColorRgb8(0, 0, 0));

      final detected = PrintedBrailleDetector.detectDots(canvas);
      // The long line has extremely low circularity and should be rejected
      expect(detected.length, 1);
      expect(detected.first.x, closeTo(100.0, 2.0));
      expect(detected.first.y, closeTo(100.0, 2.0));
    });

    test('detects and decodes dark-on-light printed Braille sequence "cab"', () {
      // 'c' = [1, 4], 'a' = [1], 'b' = [1, 2]
      final canvas = renderSyntheticPrintedBraille([
        [1, 4], // 'c'
        [1],    // 'a'
        [1, 2], // 'b'
      ], inverted: false);

      final decoded = PrintedBrailleDetector.detectAndDecode(canvas);
      expect(decoded, 'cab');
    });

    test('detects and decodes light-on-dark (inverted digital) printed Braille', () {
      // 'b' = [1, 2], 'a' = [1], 't' = [2, 3, 4, 5]
      final canvas = renderSyntheticPrintedBraille([
        [1, 2],       // 'b'
        [1],          // 'a'
        [2, 3, 4, 5], // 't'
      ], inverted: true);

      final decoded = PrintedBrailleDetector.detectAndDecode(canvas);
      expect(decoded, 'bat');
    });

    test('decodes numeric mode digits preceded by number sign (#)', () {
      // '#' = [3, 4, 5, 6], 'a' = [1] -> '1', 'b' = [1, 2] -> '2', 'c' = [1, 4] -> '3'
      final canvas = renderSyntheticPrintedBraille([
        [3, 4, 5, 6], // '#'
        [1],          // 'a' -> '1'
        [1, 2],       // 'b' -> '2'
        [1, 4],       // 'c' -> '3'
      ], inverted: false);

      final decoded = PrintedBrailleDetector.detectAndDecode(canvas);
      expect(decoded, '123');
    });

    test('decodes multiple words separated by inter-word gap', () {
      // "hi" + space + "go"
      // 'h' = [1, 2, 5], 'i' = [2, 4], space = [], 'g' = [1, 2, 4, 5], 'o' = [1, 3, 5]
      final canvas = renderSyntheticPrintedBraille([
        [1, 2, 5],       // 'h'
        [2, 4],          // 'i'
        [],              // space
        [1, 2, 4, 5],    // 'g'
        [1, 3, 5],       // 'o'
      ]);

      final decoded = PrintedBrailleDetector.detectAndDecode(canvas);
      expect(decoded, 'hi go');
    });

    test('empty / uniform image returns empty string gracefully', () {
      final canvas = img.Image(width: 200, height: 200);
      img.fill(canvas, color: img.ColorRgb8(240, 240, 240));

      final decoded = PrintedBrailleDetector.detectAndDecode(canvas);
      expect(decoded, isEmpty);
    });

    test('BrailleService integration uses printed mode by default', () async {
      final service = BrailleService();
      expect(service.recognitionMode, BrailleRecognitionMode.printed);

      // Create temporary synthetic image file
      final canvas = renderSyntheticPrintedBraille([
        [1, 4], // 'c'
        [1],    // 'a'
        [1, 2], // 'b'
      ]);
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/test_printed_braille_cab.png');
      await tempFile.writeAsBytes(img.encodePng(canvas));

      try {
        final result = await service.classifyBraille(tempFile.path);
        expect(result, 'cab');
      } finally {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
        service.dispose();
      }
    });
  });
}
