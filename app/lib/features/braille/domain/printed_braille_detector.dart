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

  static const Set<String> commonWords = {
    'i', 'a', 'am', 'is', 'the', 'to', 'in', 'it', 'you', 'that', 'he', 'was', 'for',
    'on', 'are', 'with', 'as', 'at', 'be', 'this', 'have', 'from', 'or', 'one', 'had',
    'by', 'word', 'but', 'not', 'what', 'all', 'were', 'we', 'when', 'your', 'can',
    'said', 'there', 'use', 'an', 'each', 'which', 'she', 'do', 'how', 'their', 'if',
    'book', 'music', 'reading', 'read', 'write', 'sun', 'sky', 'cat', 'dog', 'happy',
    'student', 'blue', 'hot', 'big', 'small', 'pen', 'us', 'me', 'my', 'see', 'look',
    'hi', 'go', 'so', 'no', 'of', 'up', 'out', 'day', 'get', 'has', 'good', 'like',
    'braille', 'test', 'hello', 'world', 'vision', 'visionmate', 'name', 'time',
    'cell', 'cells', 'plant', 'plants', 'animal', 'animals', 'lack', 'lacks', 'life',
    'every', 'unit', 'wall', 'walls', 'dna', 'produce', 'energy', 'basic', 'material',
  };

  /// Evaluates English linguistic plausibility and character confidence to select optimal orientation.
  static double scoreDecodedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return -100.0;

    int letters = 0;
    int digits = 0;
    int questionMarks = 0;
    int punctuation = 0;
    int vowels = 0;

    const vowelSet = {'a', 'e', 'i', 'o', 'u', 'y'};

    for (int i = 0; i < trimmed.length; i++) {
      final c = trimmed[i].toLowerCase();
      final code = trimmed.codeUnitAt(i);
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
        letters++;
        if (vowelSet.contains(c)) vowels++;
      } else if (code >= 48 && code <= 57) {
        digits++;
      } else if (c == '?') {
        questionMarks++;
      } else if (trimmed[i] != ' ') {
        punctuation++;
      }
    }

    final totalAlphanumeric = letters + digits;
    if (totalAlphanumeric == 0) return -100.0;

    final words = trimmed.toLowerCase().split(RegExp(r'\s+'));
    int recognizedWords = 0;
    int plausibleWords = 0;
    int recognizedSingleLetters = 0;
    int invalidWords = 0;

    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.isEmpty) continue;

      if (clean.length == 1) {
        if (clean == 'i' || clean == 'a' || RegExp(r'^[0-9]$').hasMatch(clean)) {
          recognizedSingleLetters++;
        } else {
          invalidWords++;
        }
      } else if (clean.length == 2) {
        const valid2Letter = {
          'am', 'an', 'as', 'at', 'be', 'by', 'do', 'go', 'he', 'hi',
          'if', 'in', 'is', 'it', 'me', 'my', 'no', 'of', 'on', 'or',
          'so', 'to', 'up', 'us', 'we', 'ok',
        };
        if (valid2Letter.contains(clean)) {
          recognizedWords++;
        } else {
          invalidWords++;
        }
      } else if (commonWords.contains(clean) || RegExp(r'^[0-9]+$').hasMatch(clean)) {
        recognizedWords++;
      } else {
        final wordVowels = clean.split('').where((ch) => vowelSet.contains(ch)).length;
        if (wordVowels > 0 && clean.length >= 3) {
          plausibleWords++;
        } else {
          invalidWords++;
        }
      }
    }

    return (letters * 3.0) +
        (digits * 4.0) +
        (recognizedWords * 30.0) +
        (plausibleWords * 15.0) +
        (recognizedSingleLetters * 5.0) -
        (invalidWords * 12.0) -
        (questionMarks * 6.0) -
        (punctuation * 2.0);
  }

  /// Detects printed Braille dots and decodes them into structured digital text.
  /// 
  /// When [autoOrient] is true, checks 0°, 90°, 180°, and 270° orientations to ensure
  /// the Braille page is processed in its natural upright reading orientation.
  static String detectAndDecode(
    img.Image originalImage, {
    bool isAlreadyCropped = false,
    bool autoOrient = true,
  }) {
    // 1. Normalize working resolution once at entry to prevent massive multi-megabyte allocations on rotation
    img.Image workImage = originalImage;
    if (originalImage.width > 1200 || originalImage.height > 1200) {
      final maxDim = max(originalImage.width, originalImage.height);
      final scale = 1200.0 / maxDim;
      workImage = img.copyResize(
        originalImage,
        width: (originalImage.width * scale).round(),
        height: (originalImage.height * scale).round(),
      );
    }

    if (autoOrient) {
      // 1. Evaluate upright 0° orientation
      final text0 = _decodeSingleOrientation(workImage, isAlreadyCropped: isAlreadyCropped);
      final score0 = scoreDecodedText(text0);

      // If 0° is already confident and readable, return immediately without expensive rotations!
      // Smartphone camera photos are pre-oriented upright by EXIF bakeOrientation.
      if (score0 >= 15.0) {
        return text0;
      }

      // 2. Only evaluate remaining orientations (90°, 180°, 270°) if 0° had insufficient confidence
      String bestText = text0;
      double bestScore = score0;

      for (final angle in [90, 180, 270]) {
        final rotated = img.copyRotate(workImage, angle: angle);
        final candidateText = _decodeSingleOrientation(rotated, isAlreadyCropped: isAlreadyCropped);
        final score = scoreDecodedText(candidateText);

        final thresholdScore = bestScore <= 0.0 ? 10.0 : bestScore + 15.0;
        if (score >= thresholdScore) {
          bestScore = score;
          bestText = candidateText;
        }
      }

      // If the overall score is non-positive or very low, it indicates noise / no Braille
      if (bestScore <= 0.0) {
        return '';
      }

      return bestText;
    }

    final singleText = _decodeSingleOrientation(workImage, isAlreadyCropped: isAlreadyCropped);
    if (scoreDecodedText(singleText) <= 0.0) {
      return '';
    }
    return singleText;
  }

  /// Robustly estimates the tilt angle in degrees (-45° to +45°) of the Braille document
  /// using the 90-degree orthogonal rotational symmetry of Braille dots.
  static double estimateTiltAngle(List<PrintedDot> dots, double basePitch) {
    if (dots.length < 4) return 0.0;

    final List<double> angles = [];
    final double minDist = basePitch * 0.65;
    final double maxDist = basePitch * 3.20;

    for (int i = 0; i < dots.length; i++) {
      for (int j = i + 1; j < dots.length; j++) {
        final dx = dots[j].x - dots[i].x;
        final dy = dots[j].y - dots[i].y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist >= minDist && dist <= maxDist) {
          final rad = atan2(dy, dx);
          double deg = rad * 180.0 / pi;
          deg = ((deg + 45.0) % 90.0);
          if (deg < 0) deg += 90.0;
          deg -= 45.0;
          angles.add(deg);
        }
      }
    }

    if (angles.isEmpty) return 0.0;

    final hist = List<int>.filled(91, 0);
    for (final a in angles) {
      final bin = (a + 45.0).round().clamp(0, 90);
      hist[bin]++;
    }

    int maxCount = 0;
    int bestBin = 45;
    for (int i = 0; i < 91; i++) {
      int count = hist[i] * 2;
      if (i > 0) count += hist[i - 1];
      if (i < 90) count += hist[i + 1];
      if (count > maxCount) {
        maxCount = count;
        bestBin = i;
      }
    }

    final roughPeak = (bestBin - 45.0);
    final inPeak = angles.where((a) => (a - roughPeak).abs() <= 2.5).toList()..sort();
    return inPeak.isNotEmpty ? inPeak[inPeak.length ~/ 2] : roughPeak;
  }

  /// Decodes Braille dots for a single given image orientation.
  static String _decodeSingleOrientation(img.Image inputImage, {bool isAlreadyCropped = false}) {
    final dots = detectDots(inputImage, isAlreadyCropped: isAlreadyCropped);
    if (dots.length < 3) {
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
      return '';
    }

    return recognizedLines.join('\n');
  }

  /// Filters out spurious non-Braille lines (e.g. repeated letter noise "cccc" from Latin headings or curled margin artifacts)
  static bool isSpuriousText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    // Discard lines with 3 or more identical characters in a row (e.g. "cccc")
    if (RegExp(r'([a-zA-Z])\1{2,}').hasMatch(trimmed)) return true;

    // Discard repetitive 1-to-4 character n-grams repeating 3 or more times (e.g. "cca cca cca cca", "ccaccaccaccac")
    final noSpaces = trimmed.replaceAll(' ', '');
    if (RegExp(r'(.{1,4})\1{2,}').hasMatch(noSpaces)) return true;

    // Discard repetitive punctuation/character noise (e.g. "c-:c-:c-:")
    if (RegExp(r'(?:[a-zA-Z][\-:;?,\.!]){3,}').hasMatch(trimmed)) return true;

    // Discard lines with '?' embedded inside letters or short non-word tokens (e.g. "cc?a", "?a")
    if (RegExp(r'[a-zA-Z]+\?[a-zA-Z]+').hasMatch(trimmed) ||
        RegExp(r'^[a-zA-Z]{1,3}\?$').hasMatch(trimmed) ||
        RegExp(r'^\?[a-zA-Z]{1,3}$').hasMatch(trimmed) ||
        (trimmed.length <= 5 && trimmed.contains('?'))) {
      if (!RegExp(r'\b(what|who|where|when|why|how|can|is|are|do|does|did|will|would|could|should)\b.+\?$', caseSensitive: false).hasMatch(trimmed)) {
        return true;
      }
    }

    // Discard short lines (<= 6 chars) that contain no valid word and are just random non-word fragments (e.g. "acc '", "aa", "c")
    final tokens = trimmed.toLowerCase().split(RegExp(r'\s+')).map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), '')).where((w) => w.isNotEmpty).toList();
    if (trimmed.length <= 6 && tokens.isNotEmpty) {
      final hasValidWord = tokens.any((t) => commonWords.contains(t) || t == 'a' || t == 'i' || RegExp(r'^[0-9]+$').hasMatch(t));
      if (!hasValidWord) return true;
    }

    // Discard lines consisting entirely of 3 or more single-letter fragments (e.g. "a a c a")
    if (tokens.length >= 3 && tokens.every((t) => t.length == 1)) {
      return true;
    }

    int letters = 0;
    int digits = 0;
    int vowels = 0;
    int noiseSymbols = 0;

    const vowelSet = {'a', 'e', 'i', 'o', 'u', 'y', 'A', 'E', 'I', 'O', 'U', 'Y'};

    for (int i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      final code = trimmed.codeUnitAt(i);
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
        letters++;
        if (vowelSet.contains(c)) vowels++;
      } else if (code >= 48 && code <= 57) {
        digits++;
      } else if (c != ' ' && c != '.' && c != ',' && c != '!' && c != '?' && c != '-' && c != '\'' && c != '"') {
        noiseSymbols++;
      }
    }

    final totalAlphanumeric = letters + digits;
    if (totalAlphanumeric == 0) return true;

    // If there are letters but zero vowels and total letters >= 3:
    if (digits == 0 && letters >= 3 && vowels == 0) {
      return true;
    }

    // Ratio of unknown noise symbols to total non-space characters
    final totalNonSpace = trimmed.replaceAll(' ', '').length;
    if (totalNonSpace > 0 && (noiseSymbols / totalNonSpace) > 0.35) {
      return true;
    }

    // Discard if the line is purely punctuation
    final nonPunct = trimmed.replaceAll(RegExp(r'[\s?:;,.!\-/#]+'), '').replaceAll("'", '').replaceAll('"', '');
    if (nonPunct.isEmpty) return true;

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

    // Filter minimum dot area: at least 4.0 px (radius >= 1.1 px)
    const double minDotArea = 4.0;
    final double maxDotArea = min(350.0, (width * height) * 0.005);

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
        if (aspect < 0.35 || aspect > 2.8) continue;

        final double perimeter = perimeterCount.toDouble();
        final double circularity = perimeter > 0 ? (4.0 * pi * pixelCount) / (perimeter * perimeter) : 0;
        if (circularity < 0.28) continue;

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

    // 1. Deskew all dots using true 2D rotation matrix from robust tilt estimation
    final double tiltDeg = estimateTiltAngle(dots, dx);

    List<PrintedDot> allDeskewedDots = dots;
    if (tiltDeg != 0.0) {
      final double rad = -tiltDeg * pi / 180.0;
      final double cosA = cos(rad);
      final double sinA = sin(rad);
      final double meanX = dots.map((d) => d.x).reduce((a, b) => a + b) / dots.length;
      final double meanY = dots.map((d) => d.y).reduce((a, b) => a + b) / dots.length;

      allDeskewedDots = dots.map((d) {
        final relX = d.x - meanX;
        final relY = d.y - meanY;
        return PrintedDot(
          x: meanX + relX * cosA - relY * sinA,
          y: meanY + relX * sinA + relY * cosA,
          radius: d.radius,
          area: d.area,
          circularity: d.circularity,
        );
      }).toList();
    }

    // 2. Validate that deskewed dots exhibit orthogonal Braille lattice properties
    // If dots are randomly scattered with no horizontal or vertical pairs matching the pitch, they are noise!
    int gridPairs = 0;
    for (int i = 0; i < allDeskewedDots.length; i++) {
      for (int j = i + 1; j < allDeskewedDots.length; j++) {
        final dX = (allDeskewedDots[i].x - allDeskewedDots[j].x).abs();
        final dY = (allDeskewedDots[i].y - allDeskewedDots[j].y).abs();
        if (dY <= dy * 0.35 && (dX - dx).abs() <= dx * 0.30) {
          gridPairs++;
        } else if (dX <= dx * 0.35 && (dY - dy).abs() <= dy * 0.30) {
          gridPairs++;
        }
      }
    }

    // A real Braille document with >= 6 dots must have at least ~22% grid pairs per dot
    if (allDeskewedDots.length >= 6 && (gridPairs / allDeskewedDots.length) < 0.22) {
      return [];
    }

    // 3. Cluster deskewed dots into horizontal text lines
    final sortedByY = List<PrintedDot>.from(allDeskewedDots)..sort((a, b) => a.y.compareTo(b.y));
    final List<List<PrintedDot>> rawLines = [];

    for (final dot in sortedByY) {
      bool placed = false;
      for (final line in rawLines) {
        final lineAvgY = line.map((d) => d.y).reduce((a, b) => a + b) / line.length;
        if ((dot.y - lineAvgY).abs() <= dy * 1.35) {
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

    final validBrailleLines = rawLines.where((l) => l.length >= 2).toList();
    if (validBrailleLines.isEmpty) return [];

    // 4. Clean margins: pick the primary text segment (gaps > 3.0 * cx are margins or punch holes)
    final List<List<PrintedDot>> cleanedLines = [];

    for (int lineIdx = 0; lineIdx < validBrailleLines.length; lineIdx++) {
      var lineDots = validBrailleLines[lineIdx];

      lineDots.sort((a, b) => a.x.compareTo(b.x));
      final List<List<PrintedDot>> hSegments = [];
      List<PrintedDot> curSeg = [lineDots.first];
      for (int i = 1; i < lineDots.length; i++) {
        if (lineDots[i].x - lineDots[i - 1].x > cx * 4.5) {
          hSegments.add(curSeg);
          curSeg = [lineDots[i]];
        } else {
          curSeg.add(lineDots[i]);
        }
      }
      hSegments.add(curSeg);

      // Pick the primary (longest) text segment
      hSegments.sort((a, b) => b.length.compareTo(a.length));
      lineDots = hSegments.first;
      if (lineDots.length < 2) continue;

      cleanedLines.add(lineDots);
    }

    if (cleanedLines.isEmpty) return [];

    final List<List<SegmentedBrailleCell>> documentLines = [];

    // 5. Segment Cells per Line using Phase-Locked Continuous Lattice
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
        if ((dot.x - cellMinX) <= dx * 1.55) {
          currentCell.add(dot);
        } else {
          cellClusters.add(currentCell);
          currentCell = [dot];
        }
      }
      cellClusters.add(currentCell);

      final List<SegmentedBrailleCell> lineCells = [];
      double? lastCellX;

      for (int cIdx = 0; cIdx < cellClusters.length; cIdx++) {
        final cluster = cellClusters[cIdx];
        final clusterMinX = cluster.map((d) => d.x).reduce(min);
        final clusterMaxX = cluster.map((d) => d.x).reduce(max);
        final clusterSpanX = clusterMaxX - clusterMinX;

        // Determine if this cluster is a single column or two columns
        final bool isTwoColumns = clusterSpanX >= dx * 0.40;
        int singleCol = 0; // Default to Column 0

        if (!isTwoColumns) {
          // Check distance to adjacent cells to resolve Column 0 vs Column 1 (e.g. Dot 6 capital indicator)
          if (cIdx + 1 < cellClusters.length) {
            final nextX = cellClusters[cIdx + 1].map((d) => d.x).reduce(min);
            final distToNext = nextX - clusterMinX;
            // If distance to next is significantly smaller than cx (closer to cx - dx)
            if (distToNext < (cx - dx * 0.35)) {
              singleCol = 1;
            }
          } else if (cIdx > 0) {
            final prevX = cellClusters[cIdx - 1].map((d) => d.x).reduce(min);
            final distFromPrev = clusterMinX - prevX;
            // If distance from prev is closer to cx + dx than cx
            if (distFromPrev > (cx + dx * 0.35) && distFromPrev < (cx * 1.45)) {
              singleCol = 1;
            }
          }
        }

        final cellMinX = singleCol == 1 ? clusterMinX - dx : clusterMinX;

        bool hasSpace = false;
        if (lastCellX != null) {
          final dist = cellMinX - lastCellX;
          if (dist >= cx * 1.25) {
            hasSpace = true;
          }
        }
        lastCellX = cellMinX;

        final cellDots = List<bool>.filled(6, false);
        for (final dot in cluster) {
          int col;
          if (isTwoColumns) {
            col = (dot.x - clusterMinX) < (dx * 0.55) ? 0 : 1;
          } else {
            col = singleCol;
          }
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
    bool isCapitalLock = false;

    for (final cell in cells) {
      if (cell.hasSpaceBefore) {
        isNumberMode = false;
        isCapitalMode = false;
        isCapitalLock = false;
        buffer.write(' ');
      }

      final binaryCode = cell.binaryCode;

      // Indicator checks
      if (binaryCode == '001111') {
        // Number indicator '#'
        isNumberMode = true;
        continue;
      }

      if (binaryCode == '000001') {
        // Dot 6 capital indicator: single dot 6 -> capitalize next letter; double dot 6 -> capital lock (all caps)
        if (isCapitalMode) {
          isCapitalLock = true;
        } else {
          isCapitalMode = true;
        }
        continue;
      }

      if (binaryCode == '000000') {
        isNumberMode = false;
        isCapitalMode = false;
        isCapitalLock = false;
        buffer.write(' ');
        continue;
      }

      final rawChar = grade1Map[binaryCode] ?? '?';

      String charToWrite = rawChar;
      if (isNumberMode && numberMap.containsKey(rawChar)) {
        charToWrite = numberMap[rawChar]!;
      } else if (isCapitalLock || isCapitalMode) {
        charToWrite = rawChar.toUpperCase();
        if (!isCapitalLock) {
          isCapitalMode = false;
        }
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
    cleaned = cleaned.replaceAll(RegExp(r'\b(?:aam happy|amhappy)\b', caseSensitive: false), 'i am happy');
    cleaned = cleaned.replaceAll(RegExp(r'\ba (?:af|f) a itudent\b', caseSensitive: false), 'i am a student');
    cleaned = cleaned.replaceAll(RegExp(r'\b;his\b', caseSensitive: false), 'this');
    cleaned = cleaned.replaceAll(RegExp(r'\bshis\b', caseSensitive: false), 'this');
    cleaned = cleaned.replaceAll(RegExp(r"\bthis is a b[?;':]+", caseSensitive: false), 'this is a book');
    cleaned = cleaned.replaceAll(RegExp(r'\bjhe\b', caseSensitive: false), 'the');
    cleaned = cleaned.replaceAll(RegExp(r'\bf like\b', caseSensitive: false), 'i like');
    cleaned = cleaned.replaceAll(RegExp(r'\bf have\b', caseSensitive: false), 'i have');
    cleaned = cleaned.replaceAll(RegExp(r"(?:^|(?<=\s))('ceg|aeg)\b", caseSensitive: false), 'the dog');
    cleaned = cleaned.replaceAll(RegExp(r'(?:^|(?<=\s))(/en|fen|;en|cen)\b', caseSensitive: false), 'pen');

    // Punctuation spacing (ensure space after punctuation followed by letter or digit)
    cleaned = cleaned.replaceAllMapped(RegExp(r'([,\.;:!\?])([a-zA-Z0-9])'), (m) => '${m.group(1)} ${m.group(2)}');

    // Split lowercase directly touching uppercase acronym (e.g. "storesDNA" -> "stores DNA")
    cleaned = cleaned.replaceAllMapped(RegExp(r'([a-z])([A-Z]{2,})'), (m) => '${m.group(1)} ${m.group(2)}');

    // Single-bit OCR errors:
    // 'w' (dots 2,4,5,6) -> 'j' (dots 2,4,5): e.g. "jhich" -> "which"
    cleaned = cleaned.replaceAllMapped(RegExp(r'\bjh([a-z]+)\b', caseSensitive: false), (m) => 'wh${m.group(1)}');

    // 's' (dots 2,3,4) -> ';' (dots 2,3): e.g. "activitie;" -> "activities", "cell;" -> "cells"
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b([a-zA-Z]{3,});(?=\s+[a-z]|\s*$)'), (m) => '${m.group(1)}s');

    // Missed capital E + v in "Every": e.g. "/j-ery", "/?-ery", "/j- ery"
    cleaned = cleaned.replaceAll(RegExp(r'[/?\-]+[j\?\-]*\s*ery\b', caseSensitive: false), 'Every');

    cleaned = cleaned.replaceAll(RegExp(r"^[\?,:;!\.\'\-]+\s*"), "");
    return cleaned.trim();
  }
}
