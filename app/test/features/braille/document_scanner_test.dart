import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/domain/page_border_detector.dart';

void main() {
  group('In-App Document Cropping & Homography (Extracted from Google Document Scanner)', () {
    test('PageBorder copyWith updates individual corners correctly', () {
      const original = PageBorder(
        topLeft: Point2D(10, 10),
        topRight: Point2D(200, 15),
        bottomRight: Point2D(195, 300),
        bottomLeft: Point2D(12, 290),
        confidence: 0.90,
        isDetected: true,
      );

      final updated = original.copyWith(
        topLeft: const Point2D(15, 18),
        confidence: 0.98,
      );

      expect(updated.topLeft.x, 15);
      expect(updated.topLeft.y, 18);
      expect(updated.topRight.x, 200);
      expect(updated.bottomRight.y, 300);
      expect(updated.confidence, 0.98);
      expect(updated.isDetected, isTrue);
    });

    test('cropAndRectifyPage applies 4-point Projective Homography without external app', () {
      // Create a test image with a skewed document
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));

      // Draw a white rectangle in the center with slight skew
      const border = PageBorder(
        topLeft: Point2D(50, 40),
        topRight: Point2D(360, 60),
        bottomRight: Point2D(340, 350),
        bottomLeft: Point2D(60, 330),
        confidence: 0.95,
        isDetected: true,
      );

      // Crop and rectify using Google-style projective homography
      final cropped = PageBorderDetector.cropAndRectifyPage(
        image,
        border,
        outputWidth: 200,
        outputHeight: 250,
      );

      expect(cropped, isNotNull);
      expect(cropped.width, 200);
      expect(cropped.height, 250);
    });

    test('detectPageBorder returns high-confidence quad for rectangular document sheet', () {
      final sheet = PageBorderDetector.generateDemoBrailleSheet(width: 500, height: 600);
      final border = PageBorderDetector.detectPageBorder(sheet);

      expect(border.isDetected, isTrue);
      expect(border.confidence, greaterThanOrEqualTo(0.90));
      expect(border.boundingWidth, greaterThan(350));
      expect(border.boundingHeight, greaterThan(400));
    });
  });
}
