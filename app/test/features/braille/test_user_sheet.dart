import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/domain/page_border_detector.dart';
import 'package:visionmate/features/braille/domain/printed_braille_detector.dart';

void main() {
  test('Analyze user scanned sheet with PrintedBrailleDetector', () {
    var path = '../scratch/test_user_scanned_sheet.jpg';
    if (!File(path).existsSync()) {
      path = '../embossed_braille_recognition/testing/experiments/test_user_scanned_sheet.jpg';
    }
    final file = File(path);
    if (!file.existsSync()) {
      print('File not found: $path');
      return;
    }
    final bytes = file.readAsBytesSync();
    final raw = img.decodeImage(bytes)!;
    final image = img.bakeOrientation(raw);

    print('Image dimensions: ${image.width}x${image.height}');

    final dots = PrintedBrailleDetector.detectDots(image);
    print('Total dots detected: ${dots.length}');

    final lines = PrintedBrailleDetector.segmentDocumentLines(dots);
    print('Total segmented lines: ${lines.length}');
    for (int i = 0; i < lines.length; i++) {
      final lineCells = lines[i];
      final lineStr = lineCells.map((c) => (c.hasSpaceBefore ? ' ' : '') + (PrintedBrailleDetector.grade1Map[c.binaryCode] ?? '?')).join();
      final lineClean = PrintedBrailleDetector.cleanDecodedText(lineStr);
      print('Line $i (${lineCells.length} cells): raw="$lineStr" -> clean="$lineClean"');
    }

    final text = PrintedBrailleDetector.detectAndDecode(image);
    print('Final decoded text:\n$text');
  });

  test('Analyze page border detection on actual user sheet', () {
    var path = '../scratch/test_user_scanned_sheet.jpg';
    if (!File(path).existsSync()) {
      path = '../embossed_braille_recognition/testing/experiments/test_user_scanned_sheet.jpg';
    }
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    final raw = img.decodeImage(bytes)!;
    final image = img.bakeOrientation(raw);

    final border = PageBorderDetector.detectPageBorder(image);
    print('Detected border on user sheet: isDetected=${border.isDetected}, summary=${border.coordinatesSummary}');
    print('Bounding box: minX=${border.minX}, maxX=${border.maxX}, minY=${border.minY}, maxY=${border.maxY}');
    print('Image dimensions: ${image.width}x${image.height}');

    final rectified = PageBorderDetector.cropAndRectifyPage(image, border);
    print('Rectified dimensions: ${rectified.width}x${rectified.height}');
    final textCropped = PrintedBrailleDetector.detectAndDecode(rectified);
    print('Decoded text from rectified image:\n$textCropped');
  });
}
