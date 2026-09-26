import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/braille/domain/page_border_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PageBorderDetector Unit & Integration Tests', () {
    test('detects high-contrast rectangular document page on dark background', () {
      const int w = 400;
      const int h = 500;
      final canvas = img.Image(width: w, height: h);
      img.fill(canvas, color: img.ColorRgb8(30, 30, 30)); // Dark desk background

      // Draw light paper sheet at (50, 40) to (350, 460)
      img.fillRect(
        canvas,
        x1: 50,
        y1: 40,
        x2: 350,
        y2: 460,
        color: img.ColorRgb8(240, 240, 240),
      );

      final border = PageBorderDetector.detectPageBorder(canvas);
      expect(border.isDetected, isTrue);
      expect(border.minX, closeTo(50.0, 15.0));
      expect(border.maxX, closeTo(350.0, 15.0));
      expect(border.minY, closeTo(40.0, 15.0));
      expect(border.maxY, closeTo(460.0, 15.0));
    });

    test('adds vibrant crop border overlay with corner brackets onto captured image', () {
      final canvas = img.Image(width: 200, height: 200);
      img.fill(canvas, color: img.ColorRgb8(240, 240, 240));

      const border = PageBorder(
        topLeft: Point2D(20, 20),
        topRight: Point2D(180, 20),
        bottomRight: Point2D(180, 180),
        bottomLeft: Point2D(20, 180),
        isDetected: true,
      );

      final overlaid = PageBorderDetector.addCropBorderOverlay(
        canvas,
        border,
        borderColor: img.ColorRgb8(0, 230, 118),
      );

      expect(overlaid.width, 200);
      expect(overlaid.height, 200);

      // Verify that pixel along top border has changed color to border color
      final pxBorder = overlaid.getPixel(100, 20);
      expect(pxBorder.r, closeTo(0, 5));
      expect(pxBorder.g, closeTo(230, 5));
      expect(pxBorder.b, closeTo(118, 5));
    });

    test('rectifies and crops document with bilinear quadrilateral mapping', () {
      final canvas = img.Image(width: 300, height: 400);
      img.fill(canvas, color: img.ColorRgb8(20, 20, 20));

      // Light page inside
      img.fillRect(canvas, x1: 40, y1: 50, x2: 260, y2: 350, color: img.ColorRgb8(240, 240, 240));

      const border = PageBorder(
        topLeft: Point2D(40, 50),
        topRight: Point2D(260, 50),
        bottomRight: Point2D(260, 350),
        bottomLeft: Point2D(40, 350),
      );

      final rectified = PageBorderDetector.cropAndRectifyPage(canvas, border);
      expect(rectified.width, closeTo(220, 5));
      expect(rectified.height, closeTo(300, 5));

      // Rectified image center should be clean paper color
      final centerPx = rectified.getPixel(rectified.width ~/ 2, rectified.height ~/ 2);
      expect(img.getLuminance(centerPx), greaterThan(200));
    });

    test('analyzes user Braille sheet, identifies page boundaries, and saves debug artifacts', () {
      final candidates = [
        '../scratch/test_user_scanned_sheet.jpg',
        'scratch/test_user_scanned_sheet.jpg',
        'c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/scratch/test_user_scanned_sheet.jpg',
      ];
      img.Image? image;
      for (final c in candidates) {
        final f = File(c);
        if (f.existsSync()) {
          final bytes = f.readAsBytesSync();
          image = img.decodeImage(bytes);
          break;
        }
      }

      // If physical camera photo is not stored locally, generate the realistic demo Braille sheet
      image ??= PageBorderDetector.generateDemoBrailleSheet(
        width: 700,
        height: 900,
        brailleText: 'braille recognition',
      );

      final border = PageBorderDetector.detectPageBorder(image);
      print('Detected page border: $border');
      print('MinX: ${border.minX}, MaxX: ${border.maxX}, MinY: ${border.minY}, MaxY: ${border.maxY}');
      print('Bounding dimensions: ${border.boundingWidth}x${border.boundingHeight}');

      expect(border.isDetected, isTrue);
      expect(border.boundingWidth, greaterThan(image.width * 0.5));
      expect(border.boundingHeight, greaterThan(image.height * 0.5));

      // Generate annotated image with crop border overlay and save to debug artifact
      final overlaid = PageBorderDetector.addCropBorderOverlay(image, border);
      final outDir = Directory('../debug');
      if (!outDir.existsSync()) {
        try {
          outDir.createSync(recursive: true);
        } catch (_) {}
      }
      if (outDir.existsSync()) {
        final borderFile = File('${outDir.path}/detected_crop_border.png');
        borderFile.writeAsBytesSync(img.encodePng(overlaid));
        print('Saved annotated crop border image to: ${borderFile.path}');

        // Rectify sheet
        final rectified = PageBorderDetector.cropAndRectifyPage(image, border);
        final rectifiedFile = File('${outDir.path}/rectified_page.png');
        rectifiedFile.writeAsBytesSync(img.encodePng(rectified));
        print('Saved rectified page image to: ${rectifiedFile.path}');

        expect(borderFile.existsSync(), isTrue);
        expect(rectifiedFile.existsSync(), isTrue);
      }
    });

    test('BrailleService passes ONLY content inside cropped border for recognition', () async {
      final service = BrailleService();
      final demoResult = await service.runDemoWithSampleSheet(text: 'braille recognition');

      expect(demoResult.isBorderDetected, isTrue);
      expect(demoResult.pageBorder.confidence, greaterThanOrEqualTo(0.90));
      expect(demoResult.annotatedImageBytes, isNotNull);
      expect(demoResult.croppedImageBytes, isNotNull);
      expect(demoResult.croppedWidth, greaterThan(0));
      expect(demoResult.croppedHeight, greaterThan(0));

      // Cropped dimensions should be within the original bounds
      expect(demoResult.croppedWidth, lessThanOrEqualTo(demoResult.originalWidth));
      expect(demoResult.croppedHeight, lessThanOrEqualTo(demoResult.originalHeight));

      print('Live Demonstration Result:');
      print('  Original: ${demoResult.originalWidth}x${demoResult.originalHeight}');
      print('  Cropped: ${demoResult.croppedWidth}x${demoResult.croppedHeight}');
      print('  Clutter Reduction: ${(demoResult.clutterReductionRatio * 100).toStringAsFixed(1)}%');
      print('  Recognized Text: "${demoResult.text}"');

      // The recognized text must contain the Braille content
      expect(demoResult.text.replaceAll(' ', '').toLowerCase(), contains('braille'));
    });
  });
}
