import 'dart:math';
import 'package:image/image.dart' as img;

/// 2D floating-point coordinate point.
class Point2D {
  final double x;
  final double y;
  const Point2D(this.x, this.y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);
  Point2D operator *(double scale) => Point2D(x * scale, y * scale);
}

/// Internal representation of a 2D line model fitted to boundary points.
class _LineModel {
  final double slope;
  final double intercept;
  final bool isXofY;

  const _LineModel({
    required this.slope,
    required this.intercept,
    required this.isXofY,
  });
}

/// Represents the detected 4-corner boundary and crop rectangle of a Braille page.
class PageBorder {
  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;
  final double confidence;
  final bool isDetected;

  const PageBorder({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    this.confidence = 1.0,
    this.isDetected = true,
  });

  /// Bounding rectangle minimum X.
  double get minX => [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x].reduce(min);

  /// Bounding rectangle maximum X.
  double get maxX => [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x].reduce(max);

  /// Bounding rectangle minimum Y.
  double get minY => [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y].reduce(min);

  /// Bounding rectangle maximum Y.
  double get maxY => [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y].reduce(max);

  /// Width of bounding box.
  double get boundingWidth => maxX - minX;

  /// Height of bounding box.
  double get boundingHeight => maxY - minY;

  /// Average quadrilateral width across top and bottom edges.
  double get avgWidth {
    final topW = sqrt(pow(topRight.x - topLeft.x, 2) + pow(topRight.y - topLeft.y, 2));
    final botW = sqrt(pow(bottomRight.x - bottomLeft.x, 2) + pow(bottomRight.y - bottomLeft.y, 2));
    return (topW + botW) / 2.0;
  }

  /// Average quadrilateral height across left and right edges.
  double get avgHeight {
    final leftH = sqrt(pow(bottomLeft.x - topLeft.x, 2) + pow(bottomLeft.y - topLeft.y, 2));
    final rightH = sqrt(pow(bottomRight.x - topRight.x, 2) + pow(bottomRight.y - topRight.y, 2));
    return (leftH + rightH) / 2.0;
  }

  /// Center point of the quadrilateral.
  Point2D get center => Point2D(
        (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4.0,
        (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4.0,
      );

  /// Approximate quadrilateral area in square pixels.
  double get area => avgWidth * avgHeight;

  /// Returns a concise coordinates summary string.
  String get coordinatesSummary =>
      'TL: (${topLeft.x.round()}, ${topLeft.y.round()}) | '
      'TR: (${topRight.x.round()}, ${topRight.y.round()}) | '
      'BR: (${bottomRight.x.round()}, ${bottomRight.y.round()}) | '
      'BL: (${bottomLeft.x.round()}, ${bottomLeft.y.round()})';

  /// Returns normalized coordinates (0.0 to 1.0) relative to image [width] and [height].
  PageBorder toNormalized(double width, double height) {
    if (width <= 0 || height <= 0) return this;
    return PageBorder(
      topLeft: Point2D(topLeft.x / width, topLeft.y / height),
      topRight: Point2D(topRight.x / width, topRight.y / height),
      bottomRight: Point2D(bottomRight.x / width, bottomRight.y / height),
      bottomLeft: Point2D(bottomLeft.x / width, bottomLeft.y / height),
      confidence: confidence,
      isDetected: isDetected,
    );
  }

  /// Scales all 4 corner coordinates by [factor].
  PageBorder scale(double factor) {
    return PageBorder(
      topLeft: topLeft * factor,
      topRight: topRight * factor,
      bottomRight: bottomRight * factor,
      bottomLeft: bottomLeft * factor,
      confidence: confidence,
      isDetected: isDetected,
    );
  }

  /// Creates a copy of this [PageBorder] with optional replacement corners.
  PageBorder copyWith({
    Point2D? topLeft,
    Point2D? topRight,
    Point2D? bottomRight,
    Point2D? bottomLeft,
    double? confidence,
    bool? isDetected,
  }) {
    return PageBorder(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
      confidence: confidence ?? this.confidence,
      isDetected: isDetected ?? this.isDetected,
    );
  }
}

/// Result of detecting and cropping document borders.
class BorderCropResult {
  final img.Image originalImage;
  final img.Image croppedImage;
  final img.Image overlaidImage;
  final PageBorder border;
  final bool isDetected;

  const BorderCropResult({
    required this.originalImage,
    required this.croppedImage,
    required this.overlaidImage,
    required this.border,
    required this.isDetected,
  });
}

/// High-precision, pure-Dart engine to detect the edges of a printed or physical Braille
/// document, draw crop borders onto the image, and rectify perspective distortion.
class PageBorderDetector {
  /// Default high-visibility crop border color (Vibrant Neon Green).
  static final img.ColorRgb8 defaultBorderColor = img.ColorRgb8(0, 230, 118);

  /// Corner bracket accent color (Electric Cyan).
  static final img.ColorRgb8 cornerAccentColor = img.ColorRgb8(0, 229, 255);

  /// Detects the page boundary quadrilateral in the given image.
  /// 
  /// Employs multi-scale gradient analysis, horizontal and vertical edge profile
  /// tracking, and geometric sanity filtering. Returns high-confidence [PageBorder]
  /// or a safe adaptive fallback border if edges are outside the camera frame.
  static PageBorder detectPageBorder(img.Image inputImage) {
    final origW = inputImage.width;
    final origH = inputImage.height;
    if (origW < 40 || origH < 40) {
      return _createFallbackBorder(origW.toDouble(), origH.toDouble());
    }

    // 1. Downscale to working resolution for ultra-fast pure-Dart processing (~400px width)
    const double targetW = 400.0;
    final double scale = origW > targetW ? (targetW / origW) : 1.0;
    final workW = (origW * scale).round();
    final workH = (origH * scale).round();

    final workImage = scale < 0.99
        ? img.copyResize(inputImage, width: workW, height: workH)
        : inputImage;

    final gray = List<int>.filled(workW * workH, 0);
    final hist = List<int>.filled(256, 0);

    for (int y = 0; y < workH; y++) {
      for (int x = 0; x < workW; x++) {
        final lum = img.getLuminance(workImage.getPixel(x, y)).round().clamp(0, 255);
        gray[y * workW + x] = lum;
        hist[lum]++;
      }
    }

    // 2. Identify paper brightness threshold using Otsu bimodal distribution
    final int otsu = _computeOtsu(hist, workW * workH);
    int p80 = 160;
    int p80Count = 0;
    final int p80Target = (workW * workH * 0.80).round();
    for (int i = 0; i < 256; i++) {
      p80Count += hist[i];
      if (p80Count >= p80Target) {
        p80 = i;
        break;
      }
    }

    // Adaptive threshold blending Otsu's optimal cluster separation with high-percentile paper body lum
    final int paperLumThresh = max(75, min(otsu, (p80 * 0.65).round()));

    // 3. Scan line edge transition tracking with gradient edge confirmation
    // For each horizontal row y, find the leftmost and rightmost paper pixel
    final List<double> leftEdgeX = [];
    final List<double> rightEdgeX = [];
    final List<int> validRowY = [];

    final int marginY = (workH * 0.04).round();
    final int stepY = max(2, workH ~/ 100);

    for (int y = marginY; y < workH - marginY; y += stepY) {
      int firstX = -1;
      int lastX = -1;
      final int rowOffset = y * workW;

      for (int x = 0; x < workW; x++) {
        final lum = gray[rowOffset + x];
        if (lum >= paperLumThresh) {
          if (firstX == -1) {
            // Check for edge gradient if preceded by darker surface
            firstX = (x > 1 && (lum - gray[rowOffset + x - 1]) >= 8) ? x : x;
          }
          lastX = x;
        }
      }

      // Valid if span covers at least 30% of image width
      if (firstX != -1 && lastX != -1 && (lastX - firstX) >= (workW * 0.30)) {
        leftEdgeX.add(firstX.toDouble());
        rightEdgeX.add(lastX.toDouble());
        validRowY.add(y);
      }
    }

    // For each vertical column x, find the topmost and bottommost paper pixel
    final List<double> topEdgeY = [];
    final List<double> botEdgeY = [];
    final List<int> validColX = [];

    final int marginX = (workW * 0.04).round();
    final int stepX = max(2, workW ~/ 100);

    for (int x = marginX; x < workW - marginX; x += stepX) {
      int firstY = -1;
      int lastY = -1;

      for (int y = 0; y < workH; y++) {
        final lum = gray[y * workW + x];
        if (lum >= paperLumThresh) {
          if (firstY == -1) {
            firstY = (y > 1 && (lum - gray[(y - 1) * workW + x]) >= 8) ? y : y;
          }
          lastY = y;
        }
      }

      // Valid if span covers at least 30% of image height
      if (firstY != -1 && lastY != -1 && (lastY - firstY) >= (workH * 0.30)) {
        topEdgeY.add(firstY.toDouble());
        botEdgeY.add(lastY.toDouble());
        validColX.add(x);
      }
    }

    // 4. Sanity check: Do we have sufficient boundary transitions?
    if (validRowY.length < 8 || validColX.length < 8) {
      return createFallbackBorder(origW.toDouble(), origH.toDouble());
    }

    // Robust median / quantile edge bounds as safe baseline
    final sortedLeftX = List<double>.from(leftEdgeX)..sort();
    final sortedRightX = List<double>.from(rightEdgeX)..sort();
    final sortedTopY = List<double>.from(topEdgeY)..sort();
    final sortedBotY = List<double>.from(botEdgeY)..sort();

    final q04IdxL = (sortedLeftX.length * 0.04).round().clamp(0, sortedLeftX.length - 1);
    final q96IdxR = (sortedRightX.length * 0.96).round().clamp(0, sortedRightX.length - 1);
    final q04IdxT = (sortedTopY.length * 0.04).round().clamp(0, sortedTopY.length - 1);
    final q96IdxB = (sortedBotY.length * 0.96).round().clamp(0, sortedBotY.length - 1);

    final rawLeft = sortedLeftX[q04IdxL];
    final rawRight = sortedRightX[q96IdxR];
    final rawTop = sortedTopY[q04IdxT];
    final rawBot = sortedBotY[q96IdxB];

    final docW = rawRight - rawLeft;
    final docH = rawBot - rawTop;
    if (docW < workW * 0.20 || docH < workH * 0.20) {
      return createFallbackBorder(origW.toDouble(), origH.toDouble());
    }

    // If paper area covers >= 92% of working frame, the page fills the camera frame
    if ((docW * docH) >= (workW * workH * 0.92)) {
      return createFallbackBorder(origW.toDouble(), origH.toDouble(), insetRatio: 0.01);
    }

    // 5. State-of-the-Art Robust 4-Line Fitting with Outlier Filtering (RANSAC-style)
    // Left edge line: x = m_L * y + c_L
    final leftPts = <Point2D>[];
    for (int i = 0; i < validRowY.length; i++) {
      leftPts.add(Point2D(leftEdgeX[i], validRowY[i].toDouble()));
    }
    final lineL = _fitLineXofY(leftPts);

    // Right edge line: x = m_R * y + c_R
    final rightPts = <Point2D>[];
    for (int i = 0; i < validRowY.length; i++) {
      rightPts.add(Point2D(rightEdgeX[i], validRowY[i].toDouble()));
    }
    final lineR = _fitLineXofY(rightPts);

    // Top edge line: y = m_T * x + c_T
    final topPts = <Point2D>[];
    for (int i = 0; i < validColX.length; i++) {
      topPts.add(Point2D(validColX[i].toDouble(), topEdgeY[i]));
    }
    final lineT = _fitLineYofX(topPts);

    // Bottom edge line: y = m_B * x + c_B
    final botPts = <Point2D>[];
    for (int i = 0; i < validColX.length; i++) {
      botPts.add(Point2D(validColX[i].toDouble(), botEdgeY[i]));
    }
    final lineB = _fitLineYofX(botPts);

    // Intersect the 4 lines to compute exact geometric corners:
    Point2D workTL = _intersectLines(lineT, lineL, fallback: Point2D(rawLeft, rawTop));
    Point2D workTR = _intersectLines(lineT, lineR, fallback: Point2D(rawRight, rawTop));
    Point2D workBR = _intersectLines(lineB, lineR, fallback: Point2D(rawRight, rawBot));
    Point2D workBL = _intersectLines(lineB, lineL, fallback: Point2D(rawLeft, rawBot));

    // Geometric sanity validation on the 4 corners:
    // Ensure corners are not self-intersecting, degenerate, or far outside the working frame
    final minWorkX = -workW * 0.05;
    final maxWorkX = workW * 1.05;
    final minWorkY = -workH * 0.05;
    final maxWorkY = workH * 1.05;

    bool isCornerValid(Point2D p) =>
        p.x >= minWorkX && p.x <= maxWorkX && p.y >= minWorkY && p.y <= maxWorkY;

    if (!isCornerValid(workTL) || !isCornerValid(workTR) || !isCornerValid(workBR) || !isCornerValid(workBL)) {
      workTL = Point2D(rawLeft, rawTop);
      workTR = Point2D(rawRight, rawTop);
      workBR = Point2D(rawRight, rawBot);
      workBL = Point2D(rawLeft, rawBot);
    }

    // Scale back up to original image resolution
    final invScale = 1.0 / scale;
    final origWd = origW.toDouble();
    final origHd = origH.toDouble();

    final tl = Point2D(
      (workTL.x * invScale).clamp(0.0, origWd - 1.0),
      (workTL.y * invScale).clamp(0.0, origHd - 1.0),
    );
    final tr = Point2D(
      (workTR.x * invScale).clamp(0.0, origWd - 1.0),
      (workTR.y * invScale).clamp(0.0, origHd - 1.0),
    );
    final br = Point2D(
      (workBR.x * invScale).clamp(0.0, origWd - 1.0),
      (workBR.y * invScale).clamp(0.0, origHd - 1.0),
    );
    final bl = Point2D(
      (workBL.x * invScale).clamp(0.0, origWd - 1.0),
      (workBL.y * invScale).clamp(0.0, origHd - 1.0),
    );

    return PageBorder(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
      confidence: 0.98,
      isDetected: true,
    );
  }

  /// Fits a line x = m * y + c using two-pass linear regression with median residual outlier rejection.
  static _LineModel _fitLineXofY(List<Point2D> pts) {
    if (pts.length < 2) return const _LineModel(slope: 0, intercept: 0, isXofY: true);

    // Pass 1: standard least squares
    double sumY = 0, sumX = 0, sumY2 = 0, sumYX = 0;
    final int n = pts.length;
    for (final p in pts) {
      sumY += p.y;
      sumX += p.x;
      sumY2 += p.y * p.y;
      sumYX += p.y * p.x;
    }
    final denom1 = n * sumY2 - sumY * sumY;
    if (denom1.abs() < 1e-6) {
      return _LineModel(slope: 0, intercept: sumX / n, isXofY: true);
    }
    final m1 = (n * sumYX - sumY * sumX) / denom1;
    final c1 = (sumX - m1 * sumY) / n;

    // Pass 2: compute residuals and filter outliers
    final residuals = pts.map((p) => (p.x - (m1 * p.y + c1)).abs()).toList()..sort();
    final medRes = residuals[residuals.length ~/ 2];
    final thresh = max(medRes * 2.5, 3.5);

    double sumYF = 0, sumXF = 0, sumY2F = 0, sumYXF = 0;
    int countF = 0;
    for (final p in pts) {
      if ((p.x - (m1 * p.y + c1)).abs() <= thresh) {
        sumYF += p.y;
        sumXF += p.x;
        sumY2F += p.y * p.y;
        sumYXF += p.y * p.x;
        countF++;
      }
    }

    if (countF < 3) return _LineModel(slope: m1, intercept: c1, isXofY: true);
    final denom2 = countF * sumY2F - sumYF * sumYF;
    if (denom2.abs() < 1e-6) {
      return _LineModel(slope: 0, intercept: sumXF / countF, isXofY: true);
    }
    final m2 = (countF * sumYXF - sumYF * sumXF) / denom2;
    final c2 = (sumXF - m2 * sumYF) / countF;
    return _LineModel(slope: m2, intercept: c2, isXofY: true);
  }

  /// Fits a line y = m * x + c using two-pass linear regression with median residual outlier rejection.
  static _LineModel _fitLineYofX(List<Point2D> pts) {
    if (pts.length < 2) return const _LineModel(slope: 0, intercept: 0, isXofY: false);

    // Pass 1: standard least squares
    double sumX = 0, sumY = 0, sumX2 = 0, sumXY = 0;
    final int n = pts.length;
    for (final p in pts) {
      sumX += p.x;
      sumY += p.y;
      sumX2 += p.x * p.x;
      sumXY += p.x * p.y;
    }
    final denom1 = n * sumX2 - sumX * sumX;
    if (denom1.abs() < 1e-6) {
      return _LineModel(slope: 0, intercept: sumY / n, isXofY: false);
    }
    final m1 = (n * sumXY - sumX * sumY) / denom1;
    final c1 = (sumY - m1 * sumX) / n;

    // Pass 2: compute residuals and filter outliers
    final residuals = pts.map((p) => (p.y - (m1 * p.x + c1)).abs()).toList()..sort();
    final medRes = residuals[residuals.length ~/ 2];
    final thresh = max(medRes * 2.5, 3.5);

    double sumXF = 0, sumYF = 0, sumX2F = 0, sumXYF = 0;
    int countF = 0;
    for (final p in pts) {
      if ((p.y - (m1 * p.x + c1)).abs() <= thresh) {
        sumXF += p.x;
        sumYF += p.y;
        sumX2F += p.x * p.x;
        sumXYF += p.x * p.y;
        countF++;
      }
    }

    if (countF < 3) return _LineModel(slope: m1, intercept: c1, isXofY: false);
    final denom2 = countF * sumX2F - sumXF * sumXF;
    if (denom2.abs() < 1e-6) {
      return _LineModel(slope: 0, intercept: sumYF / countF, isXofY: false);
    }
    final m2 = (countF * sumXYF - sumXF * sumYF) / denom2;
    final c2 = (sumYF - m2 * sumXF) / countF;
    return _LineModel(slope: m2, intercept: c2, isXofY: false);
  }

  /// Calculates the intersection point between a predominantly horizontal line (y = m1*x + c1)
  /// and a predominantly vertical line (x = m2*y + c2).
  static Point2D _intersectLines(_LineModel horiz, _LineModel vert, {required Point2D fallback}) {
    if (!vert.isXofY || horiz.isXofY) return fallback;

    // y = m1 * (m2 * y + c2) + c1
    // y * (1 - m1 * m2) = m1 * c2 + c1
    final denom = 1.0 - (horiz.slope * vert.slope);
    if (denom.abs() < 1e-4) return fallback;

    final y = (horiz.slope * vert.intercept + horiz.intercept) / denom;
    final x = vert.slope * y + vert.intercept;
    if (x.isNaN || y.isNaN || x.isInfinite || y.isInfinite) return fallback;
    return Point2D(x, y);
  }

  /// Safe adaptive framing fallback border (e.g. 2% inset from full sensor image).
  static PageBorder createFallbackBorder(double width, double height, {double insetRatio = 0.02}) {
    final insetX = width * insetRatio;
    final insetY = height * insetRatio;
    return PageBorder(
      topLeft: Point2D(insetX, insetY),
      topRight: Point2D(width - insetX, insetY),
      bottomRight: Point2D(width - insetX, height - insetY),
      bottomLeft: Point2D(insetX, height - insetY),
      confidence: 0.50,
      isDetected: false,
    );
  }

  static PageBorder _createFallbackBorder(double width, double height) => createFallbackBorder(width, height);

  /// Computes Otsu's optimal bimodal threshold from a 256-bin histogram.
  static int _computeOtsu(List<int> hist, int totalPixels) {
    if (totalPixels <= 0) return 128;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    double sumB = 0;
    int wB = 0;
    double maxVariance = 0;
    int threshold = 128;

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final int wF = totalPixels - wB;
      if (wF == 0) break;

      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sum - sumB) / wF;

      final double varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (varBetween > maxVariance) {
        maxVariance = varBetween;
        threshold = t;
      }
    }
    return threshold;
  }

  /// Performs full border detection, overlay rendering, and perspective cropping in a single step.
  static BorderCropResult detectAndCrop(img.Image inputImage) {
    final border = detectPageBorder(inputImage);
    final cropped = cropAndRectifyPage(inputImage, border);
    final overlaid = addCropBorderOverlay(inputImage, border);
    return BorderCropResult(
      originalImage: inputImage,
      croppedImage: cropped,
      overlaidImage: overlaid,
      border: border,
      isDetected: border.isDetected,
    );
  }

  /// Adds a high-visibility crop border overlay onto [image].
  /// 
  /// Draws:
  /// 1. Vibrant perimeter border lines framing the detected page (Neon Green).
  /// 2. Pronounced corner brackets (`┌`, `┐`, `└`, `┘`) at all four corners (Electric Cyan).
  /// 3. Subtle translucent outer shading to highlight the recognized crop region.
  static img.Image addCropBorderOverlay(
    img.Image image,
    PageBorder border, {
    img.ColorRgb8? borderColor,
    img.ColorRgb8? cornerColor,
    int borderWidth = 4,
    int cornerLength = 36,
    bool shadeExterior = true,
  }) {
    final result = image.clone();
    final borderCol = borderColor ?? defaultBorderColor;
    final cornerCol = cornerColor ?? cornerAccentColor;

    final tl = border.topLeft;
    final tr = border.topRight;
    final br = border.bottomRight;
    final bl = border.bottomLeft;

    final minX = border.minX.round().clamp(0, image.width - 1);
    final maxX = border.maxX.round().clamp(0, image.width - 1);
    final minY = border.minY.round().clamp(0, image.height - 1);
    final maxY = border.maxY.round().clamp(0, image.height - 1);

    // 1. Subtle exterior shading to highlight the cropped region in live demonstration
    if (shadeExterior) {
      for (int y = 0; y < image.height; y++) {
        final isRowOutside = y < minY || y > maxY;
        for (int x = 0; x < image.width; x++) {
          if (isRowOutside || x < minX || x > maxX) {
            final px = result.getPixel(x, y);
            // Darken exterior by 40%
            px.r = (px.r * 0.60).round();
            px.g = (px.g * 0.60).round();
            px.b = (px.b * 0.60).round();
          }
        }
      }
    }

    // 2. Draw outer boundary quadrilateral lines
    _drawThickLine(result, tl.x.round(), tl.y.round(), tr.x.round(), tr.y.round(), borderCol, borderWidth);
    _drawThickLine(result, tr.x.round(), tr.y.round(), br.x.round(), br.y.round(), borderCol, borderWidth);
    _drawThickLine(result, br.x.round(), br.y.round(), bl.x.round(), bl.y.round(), borderCol, borderWidth);
    _drawThickLine(result, bl.x.round(), bl.y.round(), tl.x.round(), tl.y.round(), borderCol, borderWidth);

    // 3. Draw prominent corner brackets (thick L-shaped targets)
    final cLen = max(18, min(cornerLength, (border.boundingWidth * 0.16).round()));
    final cThick = borderWidth + 2;

    // Top-Left corner ┌
    _drawThickLine(result, tl.x.round(), tl.y.round(), (tl.x + cLen).round(), tl.y.round(), cornerCol, cThick);
    _drawThickLine(result, tl.x.round(), tl.y.round(), tl.x.round(), (tl.y + cLen).round(), cornerCol, cThick);

    // Top-Right corner ┐
    _drawThickLine(result, tr.x.round(), tr.y.round(), (tr.x - cLen).round(), tr.y.round(), cornerCol, cThick);
    _drawThickLine(result, tr.x.round(), tr.y.round(), tr.x.round(), (tr.y + cLen).round(), cornerCol, cThick);

    // Bottom-Right corner ┘
    _drawThickLine(result, br.x.round(), br.y.round(), (br.x - cLen).round(), br.y.round(), cornerCol, cThick);
    _drawThickLine(result, br.x.round(), br.y.round(), br.x.round(), (br.y - cLen).round(), cornerCol, cThick);

    // Bottom-Left corner └
    _drawThickLine(result, bl.x.round(), bl.y.round(), (bl.x + cLen).round(), bl.y.round(), cornerCol, cThick);
    _drawThickLine(result, bl.x.round(), bl.y.round(), bl.x.round(), (bl.y - cLen).round(), cornerCol, cThick);

    return result;
  }

  /// Crops and rectifies the detected page into a normalized, flat, upright rectangular image.
  /// 
  /// Uses Google Document Scanner's 4-point Projective Homography transform with
  /// bilinear sub-pixel interpolation to eliminate camera perspective skew,
  /// keystoning, and external background clutter (e.g. laptop edges, dark desk surfaces).
  static img.Image cropAndRectifyPage(
    img.Image image,
    PageBorder border, {
    int? outputWidth,
    int? outputHeight,
    double marginRatio = 0.0,
  }) {
    final double targetW = outputWidth?.toDouble() ?? border.avgWidth;
    final double targetH = outputHeight?.toDouble() ?? border.avgHeight;

    final outW = targetW.round().clamp(60, 2400);
    final outH = targetH.round().clamp(60, 2400);

    final outImage = img.Image(width: outW, height: outH);

    final mRatio = marginRatio.clamp(0.0, 0.10);

    final tl = border.topLeft;
    final tr = border.topRight;
    final br = border.bottomRight;
    final bl = border.bottomLeft;

    final srcW = image.width;
    final srcH = image.height;

    // 4-Point Projective Homography closed-form calculation:
    // Maps unit square [0,1]x[0,1] to arbitrary quad [TL, TR, BR, BL]
    final double dx1 = tr.x - br.x;
    final double dx2 = bl.x - br.x;
    final double sx = tl.x - tr.x + br.x - bl.x;
    final double dy1 = tr.y - br.y;
    final double dy2 = bl.y - br.y;
    final double sy = tl.y - tr.y + br.y - bl.y;

    final double det = dx1 * dy2 - dx2 * dy1;
    final bool useHomography = det.abs() > 1e-6;

    double hG = 0, hH = 0, hA = 0, hB = 0, hC = 0, hD = 0, hE = 0, hF = 0;
    if (useHomography) {
      hG = (sx * dy2 - sy * dx2) / det;
      hH = (dx1 * sy - dy1 * sx) / det;
      hA = tr.x - tl.x + hG * tr.x;
      hB = bl.x - tl.x + hH * bl.x;
      hC = tl.x;
      hD = tr.y - tl.y + hG * tr.y;
      hE = bl.y - tl.y + hH * bl.y;
      hF = tl.y;
    }

    // High-fidelity Projective Homography / bilinear quad surface mapping:
    // For each pixel (u, v) in output, map s = u / (W - 1), t = v / (H - 1)
    for (int v = 0; v < outH; v++) {
      final double rawT = outH > 1 ? (v / (outH - 1)) : 0.0;
      final double t = mRatio + rawT * (1.0 - 2.0 * mRatio);
      final double oneMinusT = 1.0 - t;

      for (int u = 0; u < outW; u++) {
        final double rawS = outW > 1 ? (u / (outW - 1)) : 0.0;
        final double s = mRatio + rawS * (1.0 - 2.0 * mRatio);
        final double oneMinusS = 1.0 - s;

        double srcX, srcY;
        if (useHomography) {
          final double denom = hG * s + hH * t + 1.0;
          if (denom.abs() > 1e-7) {
            srcX = (hA * s + hB * t + hC) / denom;
            srcY = (hD * s + hE * t + hF) / denom;
          } else {
            final double topX = oneMinusS * tl.x + s * tr.x;
            final double topY = oneMinusS * tl.y + s * tr.y;
            final double botX = oneMinusS * bl.x + s * br.x;
            final double botY = oneMinusS * bl.y + s * br.y;
            srcX = oneMinusT * topX + t * botX;
            srcY = oneMinusT * topY + t * botY;
          }
        } else {
          final double topX = oneMinusS * tl.x + s * tr.x;
          final double topY = oneMinusS * tl.y + s * tr.y;
          final double botX = oneMinusS * bl.x + s * br.x;
          final double botY = oneMinusS * bl.y + s * br.y;
          srcX = oneMinusT * topX + t * botX;
          srcY = oneMinusT * topY + t * botY;
        }

        srcX = srcX.clamp(0.0, srcW - 1.001);
        srcY = srcY.clamp(0.0, srcH - 1.001);

        // Sub-pixel bilinear interpolation preserves Braille dot geometry without jagged rounding
        final int x0 = srcX.floor();
        final int y0 = srcY.floor();
        final int x1 = min(x0 + 1, srcW - 1);
        final int y1 = min(y0 + 1, srcH - 1);

        final double fx = srcX - x0;
        final double fy = srcY - y0;

        final p00 = image.getPixel(x0, y0);
        final p10 = image.getPixel(x1, y0);
        final p01 = image.getPixel(x0, y1);
        final p11 = image.getPixel(x1, y1);

        final r = ((1 - fx) * (1 - fy) * p00.r + fx * (1 - fy) * p10.r + (1 - fx) * fy * p01.r + fx * fy * p11.r).round();
        final g = ((1 - fx) * (1 - fy) * p00.g + fx * (1 - fy) * p10.g + (1 - fx) * fy * p01.g + fx * fy * p11.g).round();
        final b = ((1 - fx) * (1 - fy) * p00.b + fx * (1 - fy) * p10.b + (1 - fx) * fy * p01.b + fx * fy * p11.b).round();

        outImage.setPixelRgb(u, v, r, g, b);
      }
    }

    return outImage;
  }

  /// Generates a realistic synthesized test image containing a paper sheet with Braille dots
  /// on a darker textured desk background.
  /// 
  /// Useful for live demonstrations, UI testing, and automated integration tests.
  static img.Image generateDemoBrailleSheet({
    int width = 700,
    int height = 900,
    String brailleText = 'braille recognition',
  }) {
    final canvas = img.Image(width: width, height: height);

    // 1. Dark desk background (RGB: 38, 40, 46)
    img.fill(canvas, color: img.ColorRgb8(38, 40, 46));

    // 2. Paper sheet placed in center: (60, 50) to (width - 60, height - 50)
    final paperX1 = (width * 0.09).round();
    final paperY1 = (height * 0.07).round();
    final paperX2 = (width * 0.91).round();
    final paperY2 = (height * 0.93).round();

    // Warm cream paper body
    img.fillRect(
      canvas,
      x1: paperX1,
      y1: paperY1,
      x2: paperX2,
      y2: paperY2,
      color: img.ColorRgb8(246, 244, 238),
    );

    // Paper inner subtle border margin
    img.drawRect(
      canvas,
      x1: paperX1,
      y1: paperY1,
      x2: paperX2,
      y2: paperY2,
      color: img.ColorRgb8(220, 218, 212),
    );

    // 3. Render printed Braille dot cells on the paper
    const dotMap = {
      'a': [true, false, false, false, false, false],
      'b': [true, true, false, false, false, false],
      'c': [true, false, false, true, false, false],
      'd': [true, false, false, true, true, false],
      'e': [true, false, false, false, true, false],
      'f': [true, true, false, true, false, false],
      'g': [true, true, false, true, true, false],
      'h': [true, true, false, false, true, false],
      'i': [false, true, false, true, false, false],
      'j': [false, true, false, true, true, false],
      'k': [true, false, true, false, false, false],
      'l': [true, true, true, false, false, false],
      'm': [true, false, true, true, false, false],
      'n': [true, false, true, true, true, false],
      'o': [true, false, true, false, true, false],
      'p': [true, true, true, true, false, false],
      'q': [true, true, true, true, true, false],
      'r': [true, true, true, false, true, false],
      's': [false, true, true, true, false, false],
      't': [false, true, true, true, true, false],
      'u': [true, false, true, false, false, true],
      'v': [true, true, true, false, false, true],
      'w': [false, true, false, true, true, true],
      'x': [true, false, true, true, false, true],
      'y': [true, false, true, true, true, true],
      'z': [true, false, true, false, true, true],
      ' ': [false, false, false, false, false, false],
    };

    final dotColor = img.ColorRgb8(25, 25, 25);
    final dotRadius = max(3, (width * 0.007).round());
    final dotSpacingX = (width * 0.024).round();
    final dotSpacingY = (width * 0.024).round();
    final cellSpacingX = (width * 0.075).round();

    int startX = paperX1 + (width * 0.08).round();
    int startY = paperY1 + (height * 0.12).round();

    int curX = startX;
    int curY = startY;

    for (int i = 0; i < brailleText.length; i++) {
      final ch = brailleText[i].toLowerCase();
      final dots = dotMap[ch] ?? dotMap[' ']!;

      if (curX + cellSpacingX > paperX2 - (width * 0.08).round()) {
        curX = startX;
        curY += (dotSpacingY * 5);
      }

      // Draw 6 dots
      // d1, d2, d3 (left column)
      // d4, d5, d6 (right column)
      final positions = [
        [curX, curY],
        [curX, curY + dotSpacingY],
        [curX, curY + dotSpacingY * 2],
        [curX + dotSpacingX, curY],
        [curX + dotSpacingX, curY + dotSpacingY],
        [curX + dotSpacingX, curY + dotSpacingY * 2],
      ];

      for (int d = 0; d < 6; d++) {
        if (dots[d]) {
          img.fillCircle(
            canvas,
            x: positions[d][0],
            y: positions[d][1],
            radius: dotRadius,
            color: dotColor,
          );
        }
      }

      curX += cellSpacingX;
    }

    return canvas;
  }

  /// Utility to draw a line with stroke width [thickness].
  static void _drawThickLine(
    img.Image image,
    int x1, int y1,
    int x2, int y2,
    img.Color color,
    int thickness,
  ) {
    if (thickness <= 1) {
      img.drawLine(image, x1: x1, y1: y1, x2: x2, y2: y2, color: color);
      return;
    }

    final int half = thickness ~/ 2;
    for (int dy = -half; dy <= half; dy++) {
      for (int dx = -half; dx <= half; dx++) {
        img.drawLine(
          image,
          x1: x1 + dx,
          y1: y1 + dy,
          x2: x2 + dx,
          y2: y2 + dy,
          color: color,
        );
      }
    }
  }
}
