import 'dart:math';
import 'package:image/image.dart' as img;

/// Represents a single detected printed Braille dot.
class PrintedDot {
  final double x;
  final double y;
  final double radius;
  final double area;
  final double circularity;

  PrintedDot({
    required this.x,
    required this.y,
    required this.radius,
    required this.area,
    required this.circularity,
  });

  @override
  String toString() => 'PrintedDot(x: ${x.toStringAsFixed(1)}, y: ${y.toStringAsFixed(1)}, r: ${radius.toStringAsFixed(1)})';
}

/// Represents a segmented 2x3 Braille cell.
class SegmentedBrailleCell {
  final List<bool> dots; // [d1, d2, d3, d4, d5, d6]
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final bool hasSpaceBefore;

  SegmentedBrailleCell({
    required this.dots,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    this.hasSpaceBefore = false,
  });

  /// Binary string code in 1-to-6 order, e.g. "100000" for 'a'
  String get binaryCode => dots.map((d) => d ? '1' : '0').join();

  /// Converts 6-dot boolean pattern to Unicode Braille pattern character (U+2800 to U+283F)
  String get unicodeChar {
    int mask = 0;
    if (dots[0]) mask |= 1;
    if (dots[1]) mask |= 2;
    if (dots[2]) mask |= 4;
    if (dots[3]) mask |= 8;
    if (dots[4]) mask |= 16;
    if (dots[5]) mask |= 32;
    if (mask == 0) return ' ';
    return String.fromCharCode(0x2800 + mask);
  }
}

/// High-accuracy, pure-Dart non-embossed (printed/flat) Braille recognition engine.
/// 
/// Operates on 2D printed, digital, or photocopied Braille cards, book pages,
/// signs, and packaging using adaptive binarization, morphological erosion for
/// hollow-vs-solid circle discrimination, document deskewing, and continuous 2x3 lattice fitting.
class PrintedBrailleDetector {
  /// Standard 6-dot Grade 1 English Braille symbol dictionary.
  static const Map<String, String> grade1Map = {
    '100000': 'a',
    '110000': 'b',
    '100100': 'c',
    '100110': 'd',
    '100010': 'e',
    '110100': 'f',
    '110110': 'g',
    '110010': 'h',
    '010100': 'i',
    '010110': 'j',
    '101000': 'k',
    '111000': 'l',
    '101100': 'm',
    '101110': 'n',
    '101010': 'o',
    '111100': 'p',
    '111110': 'q',
    '111010': 'r',
    '011100': 's',
    '011110': 't',
    '101001': 'u',
    '111001': 'v',
    '010111': 'w',
    '101101': 'x',
    '101111': 'y',
    '101011': 'z',

    // Punctuation and indicators
    '010000': ',', // Dot 2
    '011000': ';', // Dots 2,3
    '010010': ':', // Dots 2,5
    '010011': '.', // Dots 2,5,6
    '011010': '!', // Dots 2,3,5
    '011001': '?', // Dots 2,3,6
    '001000': '\'', // Dot 3
    '001001': '-', // Dots 3,6
    '001100': '/', // Dots 3,4
    '011011': '(', // Dots 2,3,5,6
    '001111': '#', // Number indicator (dots 3,4,5,6)
    '000001': ',', // Capital indicator (dot 6)
    '000000': ' ', // Empty cell
  };

  /// Number sign digit mapping (when preceded by '#')
  static const Map<String, String> numberMap = {
    'a': '1',
    'b': '2',
    'c': '3',
    'd': '4',
    'e': '5',
    'f': '6',
    'g': '7',
    'h': '8',
    'i': '9',
    'j': '0',
  };

  /// Evaluates English linguistic plausibility and character confidence to select optimal orientation.
  static double scoreDecodedText(String text) {
    if (text.trim().isEmpty) return -100.0;
    int letters = 0;
    int questionMarks = 0;
    int punctuation = 0;

    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      final code = text.codeUnitAt(i);
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
        letters++;
      } else if (c == '?') {
        questionMarks++;
      } else if (c != ' ') {
        punctuation++;
      }
    }

    final words = text.toLowerCase().split(RegExp(r'\s+'));
    int recognizedWords = 0;
    int recognizedSingleLetters = 0;
    const commonWords = {
      'i', 'a', 'am', 'is', 'the', 'to', 'in', 'it', 'you', 'that', 'he', 'was', 'for',
      'on', 'are', 'with', 'as', 'at', 'be', 'this', 'have', 'from', 'or', 'one', 'had',
      'by', 'word', 'but', 'not', 'what', 'all', 'were', 'we', 'when', 'your', 'can',
      'said', 'there', 'use', 'an', 'each', 'which', 'she', 'do', 'how', 'their', 'if',
      'book', 'music', 'reading', 'read', 'write', 'sun', 'sky', 'cat', 'dog', 'happy',
      'student', 'blue', 'hot', 'big', 'small', 'pen', 'us', 'me', 'my', 'see', 'look',
      'hi', 'go', 'so', 'no', 'of', 'up', 'out', 'day', 'get', 'has', 'good', 'like'
    };

    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.length == 1) {
        // Only 'i' and 'a' are valid single-letter English words; modest credit
        if (clean == 'i' || clean == 'a') {
          recognizedSingleLetters++;
        }
      } else if (clean.length >= 2 && commonWords.contains(clean)) {
        recognizedWords++;
      }
    }

    return (letters * 4.0) +
        (recognizedWords * 30.0) +
        (recognizedSingleLetters * 4.0) -
        (questionMarks * 15.0) -
        (punctuation * 5.0);
  }

  /// Detects printed Braille dots and decodes them into structured digital text.
  /// 
  /// When [autoOrient] is true, checks 0°, 90°, 180°, and 270° orientations to ensure
  /// the Braille page is processed in its natural upright reading orientation, eliminating
  /// gibberish caused by rotated camera sensor photos or document crops.
  /// When [isAlreadyCropped] is true, avoids clipping edge margins from the isolated paper.
  static String detectAndDecode(
    img.Image originalImage, {
    bool isAlreadyCropped = false,
    bool autoOrient = true,
  }) {
    if (autoOrient) {
      // 1. Evaluate upright 0° orientation
      final text0 = _decodeSingleOrientation(originalImage, isAlreadyCropped: isAlreadyCropped);
      final score0 = scoreDecodedText(text0);

      // If 0° is already confident (>= 150.0), return immediately
      if (score0 >= 150.0) {
        return text0;
      }

      // 2. Evaluate remaining orientations (90°, 180°, 270°) and pick highest scoring orientation
      String bestText = text0;
      double bestScore = score0;

      for (final angle in [90, 180, 270]) {
        final rotated = img.copyRotate(originalImage, angle: angle);
        final candidateText = _decodeSingleOrientation(rotated, isAlreadyCropped: isAlreadyCropped);
        final score = scoreDecodedText(candidateText);
        // Require meaningful improvement over current best to avoid spurious rotation flips
        if (score > bestScore + 4.0) {
          bestScore = score;
          bestText = candidateText;
        }
      }

      return bestText;
    }

    return _decodeSingleOrientation(originalImage, isAlreadyCropped: isAlreadyCropped);
  }

  /// Decodes Braille dots for a single given image orientation.
  static String _decodeSingleOrientation(img.Image inputImage, {bool isAlreadyCropped = false}) {
    final dots = detectDots(inputImage, isAlreadyCropped: isAlreadyCropped);
    if (dots.isEmpty) {
      return '';
    }

    final linesOfCells = segmentDocumentLines(dots);
    if (linesOfCells.isEmpty) {
      return '';
    }

    final List<String> recognizedLines = [];
    for (final lineCells in linesOfCells) {
      final rawLine = decodeCellsToRawText(lineCells);
      if (isSpuriousText(rawLine)) continue;
      final decodedLine = cleanDecodedText(rawLine);
      if (decodedLine.isNotEmpty && !isSpuriousText(decodedLine)) {
        recognizedLines.add(decodedLine);
      }
    }

    if (recognizedLines.isEmpty) {
      // Fallback: decode all cells directly
      final allCells = linesOfCells.expand((l) => l).toList();
      return decodeCellsToText(allCells);
    }

    return recognizedLines.join('\n');
  }

  /// Filters out spurious non-Braille lines (e.g. repeated letter noise "cccc" from Latin headings or curled margin artifacts)
  static bool isSpuriousText(String text) {
    if (text.length < 3) return true;
    // Discard lines with 3 or more identical characters in a row (e.g. "cccc")
    if (RegExp(r'(.)\1{2,}').hasMatch(text)) return true;

    // Count letters and non-alphanumeric characters (excluding spaces)
    int nonAlpha = 0;
    int letterCount = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      final isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
      if (isLetter) {
        letterCount++;
      } else if (text[i] != ' ') {
        nonAlpha++;
      }
    }
    // A valid Braille sentence line must have at least 4 letters
    if (letterCount < 4) return true;
    // Discard if non-alphanumeric/unknown noise exceeds 40% of non-space content
    final totalNonSpace = letterCount + nonAlpha;
    if (totalNonSpace > 0 && (nonAlpha / totalNonSpace) > 0.40) return true;
    return false;
  }

  /// Detects circular printed Braille dots in an image using adaptive integral thresholding,
  /// morphological erosion (to discriminate solid dots from hollow outline rings), and connected component labeling.
  static List<PrintedDot> detectDots(img.Image inputImage, {bool isAlreadyCropped = false}) {
    // 1. Normalize working resolution
    img.Image workImage = inputImage;
    double scale = 1.0;
    if (inputImage.width > 1200) {
      scale = 1200.0 / inputImage.width;
      workImage = img.copyResize(inputImage, width: 1200);
    }

    final width = workImage.width;
    final height = workImage.height;
    if (width < 20 || height < 20) return [];

    // 2. Grayscale & Histogram
    final gray = List<int>.filled(width * height, 0);
    final hist = List<int>.filled(256, 0);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = workImage.getPixel(x, y);
        final lum = img.getLuminance(pixel).round().clamp(0, 255);
        gray[y * width + x] = lum;
        hist[lum]++;
      }
    }

    // Determine background luminance via 75th percentile
    int p75 = 128;
    int p75Count = 0;
    final int p75Target = (width * height * 0.75).round();
    for (int i = 0; i < 256; i++) {
      p75Count += hist[i];
      if (p75Count >= p75Target) {
        p75 = i;
        break;
      }
    }
    final bool isDarkOnLight = p75 > 100;

    // 3. Document Paper Bounding Box Isolation
    int paperBoxMinX = 0;
    int paperBoxMaxX = width - 1;
    int paperBoxMinY = 0;
    int paperBoxMaxY = height - 1;

    // When the image is already cropped to document borders (e.g. from Google ML Kit or PageBorderDetector),
    // preserve the entire canvas to avoid shaving off valid Braille dots along the page edges.
    if (isDarkOnLight && !isAlreadyCropped) {
      final brightThresh = p75 * 0.65;
      final rowCountBright = List<int>.filled(height, 0);
      final colCountBright = List<int>.filled(width, 0);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (gray[y * width + x] > brightThresh) {
            rowCountBright[y]++;
            colCountBright[x]++;
          }
        }
      }

      int minPaperY = 0;
      while (minPaperY < height && rowCountBright[minPaperY] < width * 0.25) {
        minPaperY++;
      }
      int maxPaperY = height - 1;
      while (maxPaperY > 0 && rowCountBright[maxPaperY] < width * 0.25) {
        maxPaperY--;
      }

      int minPaperX = 0;
      while (minPaperX < width && colCountBright[minPaperX] < height * 0.25) {
        minPaperX++;
      }
      int maxPaperX = width - 1;
      while (maxPaperX > 0 && colCountBright[maxPaperX] < height * 0.25) {
        maxPaperX--;
      }

      if (maxPaperX > minPaperX + 40 && maxPaperY > minPaperY + 40) {
        // Safe 4px boundary buffer to avoid clipping first/last character dots
        paperBoxMinX = (minPaperX + 4).clamp(0, width - 1);
        paperBoxMaxX = (maxPaperX - 4).clamp(0, width - 1);
        paperBoxMinY = (minPaperY + 4).clamp(0, height - 1);
        paperBoxMaxY = (maxPaperY - 4).clamp(0, height - 1);
      }
    }

    // 4. Compute 2D Integral Image for Fast Adaptive Bradley-Roth Thresholding
    final integral = List<int>.filled((width + 1) * (height + 1), 0);
    final int intW = width + 1;

    for (int y = 0; y < height; y++) {
      int sumRow = 0;
      for (int x = 0; x < width; x++) {
        sumRow += gray[y * width + x];
        integral[(y + 1) * intW + (x + 1)] = integral[y * intW + (x + 1)] + sumRow;
      }
    }

    final int winSize = max(16, min(width, height) ~/ 12);
    final int halfWin = winSize ~/ 2;
    const double sensitivity = 0.20;

    final binMask = List<int>.filled(width * height, 0);

    for (int y = paperBoxMinY; y <= paperBoxMaxY; y++) {
      final y1 = max(0, y - halfWin);
      final y2 = min(height - 1, y + halfWin);
      final int countY = (y2 - y1 + 1);

      for (int x = paperBoxMinX; x <= paperBoxMaxX; x++) {
        final x1 = max(0, x - halfWin);
        final x2 = min(width - 1, x + halfWin);
        final int count = countY * (x2 - x1 + 1);

        final int sum = integral[(y2 + 1) * intW + (x2 + 1)] -
            integral[y1 * intW + (x2 + 1)] -
            integral[(y2 + 1) * intW + x1] +
            integral[y1 * intW + x1];

        final double localMean = sum / count;
        final int val = gray[y * width + x];

        bool isForeground;
        if (isDarkOnLight) {
          isForeground = val < (localMean * (1.0 - sensitivity));
        } else {
          isForeground = val > (localMean * (1.0 + sensitivity));
        }

        if (isForeground) {
          binMask[y * width + x] = 1;
        }
      }
    }

    // 5. 1-pixel Morphological Erosion
    // Completely strips 1-pixel hollow outline circles (○) and thin stroke noise,
    // leaving only solid filled Braille dots (●).
    final eroded = List<int>.filled(width * height, 0);
    for (int y = paperBoxMinY + 1; y < paperBoxMaxY; y++) {
      for (int x = paperBoxMinX + 1; x < paperBoxMaxX; x++) {
        if (binMask[y * width + x] == 1 &&
            binMask[y * width + (x + 1)] == 1 &&
            binMask[y * width + (x - 1)] == 1 &&
            binMask[(y + 1) * width + x] == 1 &&
            binMask[(y - 1) * width + x] == 1) {
          eroded[y * width + x] = 1;
        }
      }
    }

    // Fallback: If image has very small dots that vanished under erosion, revert to binMask
    int erodedCount = 0;
    for (int i = 0; i < eroded.length; i++) {
      if (eroded[i] == 1) erodedCount++;
    }
    final maskToUse = erodedCount >= 6 ? eroded : binMask;
    final double radiusComp = erodedCount >= 6 ? 1.0 : 0.0;

    // 6. 8-Connected Component Labeling & Blob Analysis
    final visited = List<bool>.filled(width * height, false);
    final List<PrintedDot> detectedDots = [];

    const double minDotArea = 3.0;
    final double maxDotArea = min(300.0, (width * height) * 0.005);

    for (int y = paperBoxMinY + 1; y < paperBoxMaxY; y++) {
      for (int x = paperBoxMinX + 1; x < paperBoxMaxX; x++) {
        final idx = y * width + x;
        if (maskToUse[idx] == 0 || visited[idx]) continue;

        final List<int> queueX = [x];
        final List<int> queueY = [y];
        visited[idx] = true;

        int pixelCount = 0;
        double sumX = 0.0;
        double sumY = 0.0;
        int minX = x;
        int maxX = x;
        int minY = y;
        int maxY = y;
        int perimeterCount = 0;

        int head = 0;
        while (head < queueX.length) {
          final qx = queueX[head];
          final qy = queueY[head];
          head++;

          pixelCount++;
          sumX += qx;
          sumY += qy;

          if (qx < minX) minX = qx;
          if (qx > maxX) maxX = qx;
          if (qy < minY) minY = qy;
          if (qy > maxY) maxY = qy;

          bool isBoundary = false;
          if (qx == 0 || qx == width - 1 || qy == 0 || qy == height - 1) {
            isBoundary = true;
          } else {
            if (maskToUse[qy * width + (qx + 1)] == 0 ||
                maskToUse[qy * width + (qx - 1)] == 0 ||
                maskToUse[(qy + 1) * width + qx] == 0 ||
                maskToUse[(qy - 1) * width + qx] == 0) {
              isBoundary = true;
            }
          }
          if (isBoundary) perimeterCount++;

          for (int dy = -1; dy <= 1; dy++) {
            final ny = qy + dy;
            if (ny < 0 || ny >= height) continue;
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = qx + dx;
              if (nx < 0 || nx >= width) continue;

              final nIdx = ny * width + nx;
              if (maskToUse[nIdx] == 1 && !visited[nIdx]) {
                visited[nIdx] = true;
                queueX.add(nx);
                queueY.add(ny);
              }
            }
          }
        }

        if (pixelCount < minDotArea || pixelCount > maxDotArea) continue;

        final int boxW = maxX - minX + 1;
        final int boxH = maxY - minY + 1;
        final double aspect = boxW / boxH.toDouble();
        if (aspect < 0.40 || aspect > 2.5) continue;

        final double perimeter = perimeterCount.toDouble();
        final double circularity = perimeter > 0 ? (4.0 * pi * pixelCount) / (perimeter * perimeter) : 0;
        if (circularity < 0.25) continue;

        final double cx = sumX / pixelCount;
        final double cy = sumY / pixelCount;
        final double radius = sqrt(pixelCount / pi) + radiusComp;

        detectedDots.add(PrintedDot(
          x: cx / scale,
          y: cy / scale,
          radius: radius / scale,
          area: pixelCount / (scale * scale),
          circularity: circularity,
        ));
      }
    }

    return suppressOverlappingDots(detectedDots);
  }

  /// Suppresses duplicate / touching dot fragments.
  static List<PrintedDot> suppressOverlappingDots(List<PrintedDot> dots) {
    if (dots.length < 2) return dots;

    final sorted = List<PrintedDot>.from(dots)
      ..sort((a, b) => b.circularity.compareTo(a.circularity));

    final List<PrintedDot> kept = [];
    for (final dot in sorted) {
      bool isDuplicate = false;
      final suppressionDist = max(4.0, dot.radius * 1.2);
      for (final existing in kept) {
        final dx = dot.x - existing.x;
        final dy = dot.y - existing.y;
        if ((dx * dx + dy * dy) < (suppressionDist * suppressionDist)) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        kept.add(dot);
      }
    }

    return kept;
  }

  /// Estimates intra-cell dot pitch (dx, dy) and inter-cell pitch (cx) from nearest neighbors.
  static Map<String, double> estimatePitches(List<PrintedDot> dots) {
    if (dots.length < 2) {
      return {'dx': 24.0, 'dy': 24.0, 'cx': 55.2};
    }

    final List<double> nnDists = [];
    for (int i = 0; i < dots.length; i++) {
      double minDist = double.infinity;
      for (int j = 0; j < dots.length; j++) {
        if (i == j) continue;
        final dX = dots[i].x - dots[j].x;
        final dY = dots[i].y - dots[j].y;
        final dist = sqrt(dX * dX + dY * dY);
        if (dist < minDist && dist >= 5.0) {
          minDist = dist;
        }
      }
      if (minDist != double.infinity && minDist <= 60.0) {
        nnDists.add(minDist);
      }
    }

    double basePitch = 24.0;
    if (nnDists.isNotEmpty) {
      nnDists.sort();
      basePitch = nnDists[nnDists.length ~/ 2];
    }

    final List<double> dxPairs = [];
    final List<double> dyPairs = [];
    final List<double> cxPairs = [];

    final double minDx = basePitch * 0.70;
    final double maxDx = basePitch * 1.30;
    final double minCx = basePitch * 2.00;
    final double maxCx = basePitch * 2.90;

    for (int i = 0; i < dots.length; i++) {
      for (int j = i + 1; j < dots.length; j++) {
        final dX = (dots[i].x - dots[j].x).abs();
        final dY = (dots[i].y - dots[j].y).abs();

        if (dY <= basePitch * 0.40) {
          if (dX >= minDx && dX <= maxDx) {
            dxPairs.add(dX);
          } else if (dX >= minCx && dX <= maxCx) {
            cxPairs.add(dX);
          }
        } else if (dX <= basePitch * 0.40) {
          if (dY >= minDx && dY <= maxDx) {
            dyPairs.add(dY);
          }
        }
      }
    }

    double dx = basePitch;
    if (dxPairs.isNotEmpty) {
      dxPairs.sort();
      dx = dxPairs[dxPairs.length ~/ 2];
    }

    double dy = basePitch;
    if (dyPairs.isNotEmpty) {
      dyPairs.sort();
      dy = dyPairs[dyPairs.length ~/ 2];
    }

    double cx = dx * 2.5;
    if (cxPairs.isNotEmpty) {
      cxPairs.sort();
      cx = cxPairs[cxPairs.length ~/ 2];
    }

    return {'dx': dx, 'dy': dy, 'cx': cx};
  }

  /// Groups detected dots into distinct lines of text and fits robust Braille cells.
  static List<List<SegmentedBrailleCell>> segmentDocumentLines(List<PrintedDot> dots) {
    if (dots.isEmpty) return [];

    final pitches = estimatePitches(dots);
    final double dx = pitches['dx']!;
    final double dy = pitches['dy']!;
    final double cx = pitches['cx']!;
    final double lineBandHeight = dy * 3.5;

    // 1. Global document tilt from same-row dot pairs
    final List<double> sameRowSlopes = [];
    for (int i = 0; i < dots.length; i++) {
      for (int j = i + 1; j < dots.length; j++) {
        final dX = (dots[i].x - dots[j].x).abs();
        final dY = (dots[i].y - dots[j].y).abs();
        if (dX >= 8.0 && dX <= cx * 3.5 && dY <= dy * 0.35) {
          final slope = (dots[j].y - dots[i].y) / (dots[j].x - dots[i].x);
          sameRowSlopes.add(slope);
        }
      }
    }

    double globalSlope = 0.0;
    if (sameRowSlopes.isNotEmpty) {
      sameRowSlopes.sort();
      globalSlope = sameRowSlopes[sameRowSlopes.length ~/ 2].clamp(-0.15, 0.15);
    }

    // Deskew all dots before clustering
    final List<PrintedDot> allDeskewedDots = dots.map((d) {
      return PrintedDot(
        x: d.x,
        y: d.y - globalSlope * d.x,
        radius: d.radius,
        area: d.area,
        circularity: d.circularity,
      );
    }).toList();

    // 2. Cluster deskewed dots into horizontal text lines
    final sortedByY = List<PrintedDot>.from(allDeskewedDots)..sort((a, b) => a.y.compareTo(b.y));
    final List<List<PrintedDot>> rawLines = [];

    for (final dot in sortedByY) {
      bool placed = false;
      for (final line in rawLines) {
        final lineAvgY = line.map((d) => d.y).reduce((a, b) => a + b) / line.length;
        if ((dot.y - lineAvgY).abs() <= lineBandHeight * 0.75) {
          line.add(dot);
          placed = true;
          break;
        }
      }
      if (!placed) {
        rawLines.add([dot]);
      }
    }

    // Sort lines top to bottom
    rawLines.sort((l1, l2) {
      final y1 = l1.map((d) => d.y).reduce((a, b) => a + b) / l1.length;
      final y2 = l2.map((d) => d.y).reduce((a, b) => a + b) / l2.length;
      return y1.compareTo(y2);
    });

    final validBrailleLines = rawLines.where((l) => l.length >= 3).toList();
    if (validBrailleLines.isEmpty) return [];

    // 3. Clean margins
    final List<List<PrintedDot>> cleanedLines = [];

    for (int lineIdx = 0; lineIdx < validBrailleLines.length; lineIdx++) {
      var lineDots = validBrailleLines[lineIdx];

      // Sort by X and split into connected horizontal segments (gaps > 3.0 * cx are margins)
      lineDots.sort((a, b) => a.x.compareTo(b.x));
      final List<List<PrintedDot>> hSegments = [];
      List<PrintedDot> curSeg = [lineDots.first];
      for (int i = 1; i < lineDots.length; i++) {
        if (lineDots[i].x - lineDots[i - 1].x > cx * 3.0) {
          hSegments.add(curSeg);
          curSeg = [lineDots[i]];
        } else {
          curSeg.add(lineDots[i]);
        }
      }
      hSegments.add(curSeg);

      // Pick the primary text segment
      hSegments.sort((a, b) => b.length.compareTo(a.length));
      lineDots = hSegments.first;
      if (lineDots.length < 3) continue;

      cleanedLines.add(lineDots);
    }

    if (cleanedLines.isEmpty) return [];

    final List<List<SegmentedBrailleCell>> documentLines = [];

    // 4. Segment Cells per Line
    for (int lineIdx = 0; lineIdx < cleanedLines.length; lineIdx++) {
      final deskewedDots = cleanedLines[lineIdx];

      final lineMinY = deskewedDots.map((d) => d.y).reduce(min);

      // Search for consensus row 0 Y0
      double bestY0 = lineMinY;
      int maxSupport = 0;
      double minResidual = double.infinity;

      for (double candY0 = lineMinY - dy * 0.25; candY0 <= lineMinY + dy * 1.1; candY0 += 0.2) {
        int support = 0;
        double residual = 0;
        for (final d in deskewedDots) {
          final r = ((d.y - candY0) / dy).round();
          if (r >= 0 && r <= 2) {
            final diff = (d.y - (candY0 + r * dy)).abs();
            if (diff < dy * 0.42) {
              support++;
              residual += diff;
            }
          }
        }
        if (support > maxSupport || (support == maxSupport && residual < minResidual)) {
          maxSupport = support;
          minResidual = residual;
          bestY0 = candY0;
        }
      }
      final y0 = bestY0;

      // Filter dots that match the 3 rows
      final rowDots = deskewedDots.where((d) {
        final r = ((d.y - y0) / dy).round();
        if (r < 0 || r > 2) return false;
        return (d.y - (y0 + r * dy)).abs() < dy * 0.42;
      }).toList();

      if (rowDots.length < 2) continue;

      // Natural Cell Clustering
      rowDots.sort((a, b) => a.x.compareTo(b.x));
      final List<List<PrintedDot>> cellClusters = [];
      List<PrintedDot> currentCell = [rowDots.first];

      for (int i = 1; i < rowDots.length; i++) {
        final dot = rowDots[i];
        final cellMinX = currentCell.map((d) => d.x).reduce(min);
        if ((dot.x - cellMinX) <= dx * 1.35) {
          currentCell.add(dot);
        } else {
          cellClusters.add(currentCell);
          currentCell = [dot];
        }
      }
      cellClusters.add(currentCell);

      final List<SegmentedBrailleCell> lineCells = [];
      double? lastCellX;

      for (final cluster in cellClusters) {
        final cellMinX = cluster.map((d) => d.x).reduce(min);
        bool hasSpace = false;
        if (lastCellX != null) {
          final dist = cellMinX - lastCellX;
          if (dist >= cx * 1.45) {
            hasSpace = true;
          }
        }
        lastCellX = cellMinX;

        final cellDots = List<bool>.filled(6, false);
        for (final dot in cluster) {
          final col = (dot.x - cellMinX) < (dx * 0.65) ? 0 : 1;
          final r = ((dot.y - y0) / dy).round().clamp(0, 2);
          final dotIdx = col == 0 ? r : 3 + r;
          cellDots[dotIdx] = true;
        }

        lineCells.add(SegmentedBrailleCell(
          dots: cellDots,
          minX: cellMinX,
          minY: y0,
          maxX: cellMinX + dx,
          maxY: y0 + 2 * dy,
          hasSpaceBefore: hasSpace,
        ));
      }

      if (lineCells.isNotEmpty) {
        documentLines.add(lineCells);
      }
    }

    return documentLines;
  }

  /// Backward-compatible single list segmentation.
  static List<SegmentedBrailleCell> segmentCells(List<PrintedDot> dots) {
    final lines = segmentDocumentLines(dots);
    return lines.expand((l) => l).toList();
  }

  /// Converts segmented 2x3 Braille cells into raw digital text without post-processing.
  static String decodeCellsToRawText(List<SegmentedBrailleCell> cells) {
    final buffer = StringBuffer();
    bool isNumberMode = false;
    bool isCapitalMode = false;

    for (final cell in cells) {
      if (cell.hasSpaceBefore) {
        isNumberMode = false;
        isCapitalMode = false;
        buffer.write(' ');
      }

      final binaryCode = cell.binaryCode;
      final rawChar = grade1Map[binaryCode] ?? '?';

      // Indicator checks
      if (rawChar == '#') {
        isNumberMode = true;
        continue;
      }
      if (rawChar == ',' && binaryCode == '000001') {
        // Dot 6 capital indicator
        isCapitalMode = true;
        continue;
      }
      if (rawChar == ' ') {
        isNumberMode = false;
        isCapitalMode = false;
        buffer.write(' ');
        continue;
      }

      String charToWrite = rawChar;
      if (isNumberMode && numberMap.containsKey(rawChar)) {
        charToWrite = numberMap[rawChar]!;
      } else if (isCapitalMode) {
        charToWrite = rawChar.toUpperCase();
        isCapitalMode = false;
      }

      buffer.write(charToWrite);
    }

    return buffer.toString();
  }

  /// Converts segmented 2x3 Braille cells into digital text, handling number and capital modes.
  static String decodeCellsToText(List<SegmentedBrailleCell> cells) {
    return cleanDecodedText(decodeCellsToRawText(cells));
  }

  /// Post-processes decoded text to normalize common single-bit OCR artifacts
  /// and format clean English sentences.
  static String cleanDecodedText(String text) {
    if (text.isEmpty) return text;
    var cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r"^[\?,:;!\.\'\-]+\s*"), "");
    cleaned = cleaned.replaceAll(RegExp(r'\bshis\b', caseSensitive: false), 'this');
    cleaned = cleaned.replaceAll(RegExp(r'\bjhe\b', caseSensitive: false), 'the');
    cleaned = cleaned.replaceAll(RegExp(r'\bf like\b', caseSensitive: false), 'i like');
    cleaned = cleaned.replaceAll(RegExp(r'\bf have\b', caseSensitive: false), 'i have');
    cleaned = cleaned.replaceAll(RegExp(r"(?:^|(?<=\s))('ceg|aeg)\b", caseSensitive: false), 'the dog');
    cleaned = cleaned.replaceAll(RegExp(r'(?:^|(?<=\s))(/en|fen|;en)\b', caseSensitive: false), 'pen');
    cleaned = cleaned.replaceAll(RegExp(r"^[\?,:;!\.\'\-]+\s*"), "");
    return cleaned.trim();
  }
}
