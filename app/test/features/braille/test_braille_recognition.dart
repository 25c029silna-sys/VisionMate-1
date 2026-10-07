import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/domain/printed_braille_detector.dart';

class UpgradedPrintedBrailleDetector {
  static const Map<String, String> grade1Map = PrintedBrailleDetector.grade1Map;
  static const Map<String, String> numberMap = PrintedBrailleDetector.numberMap;

  static const Set<String> commonWords = {
    'i', 'a', 'am', 'is', 'the', 'to', 'in', 'it', 'you', 'that', 'he', 'was', 'for',
    'on', 'are', 'with', 'as', 'at', 'be', 'this', 'have', 'from', 'or', 'one', 'had',
    'by', 'word', 'but', 'not', 'what', 'all', 'were', 'we', 'when', 'your', 'can',
    'said', 'there', 'use', 'an', 'each', 'which', 'she', 'do', 'how', 'their', 'if',
    'book', 'music', 'reading', 'read', 'write', 'sun', 'sky', 'cat', 'dog', 'happy',
    'student', 'blue', 'hot', 'big', 'small', 'pen', 'us', 'me', 'my', 'see', 'look',
    'hi', 'go', 'so', 'no', 'of', 'up', 'out', 'day', 'get', 'has', 'good', 'like',
    'braille', 'test', 'hello', 'world', 'vision', 'visionmate', 'name', 'time',
  };

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
      } else if (commonWords.contains(clean) || RegExp(r'^[0-9]+$').hasMatch(clean)) {
        recognizedWords++;
      } else {
        final wordVowels = clean.split('').where((ch) => vowelSet.contains(ch)).length;
        if (wordVowels == 0 && !RegExp(r'^[0-9]+$').hasMatch(clean)) {
          invalidWords++;
        }
      }
    }

    // A valid Braille sentence or word must not be dominated by invalid consonant noise
    final score = (letters * 3.0) +
        (digits * 4.0) +
        (recognizedWords * 35.0) +
        (recognizedSingleLetters * 5.0) -
        (invalidWords * 18.0) -
        (questionMarks * 20.0) -
        (punctuation * 4.0);

    return score;
  }

  static bool isSpuriousText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    // Discard lines with 3 or more identical characters in a row (e.g. "cccc")
    if (RegExp(r'([a-zA-Z])\1{2,}').hasMatch(trimmed)) return true;

    // Discard repetitive punctuation/character noise (e.g. "c-:c-:c-:")
    if (RegExp(r'(?:[a-zA-Z][\-:;?,\.!]){3,}').hasMatch(trimmed)) return true;

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

  static String detectAndDecode(
    img.Image originalImage, {
    bool isAlreadyCropped = false,
    bool autoOrient = true,
  }) {
    if (autoOrient) {
      final text0 = _decodeSingleOrientation(originalImage, isAlreadyCropped: isAlreadyCropped);
      final score0 = scoreDecodedText(text0);

      // If upright orientation has confident text (score >= 120.0), return immediately
      if (score0 >= 120.0) {
        return text0;
      }

      String bestText = text0;
      double bestScore = score0;

      for (final angle in [90, 180, 270]) {
        final rotated = img.copyRotate(originalImage, angle: angle);
        final candidateText = _decodeSingleOrientation(rotated, isAlreadyCropped: isAlreadyCropped);
        final score = scoreDecodedText(candidateText);

        // Require meaningful positive score and substantial improvement over 0°
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

    final singleText = _decodeSingleOrientation(originalImage, isAlreadyCropped: isAlreadyCropped);
    if (scoreDecodedText(singleText) <= 0.0) {
      return '';
    }
    return singleText;
  }

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

  static List<PrintedDot> detectDots(img.Image inputImage, {bool isAlreadyCropped = false}) {
    img.Image workImage = inputImage;
    double scale = 1.0;
    if (inputImage.width > 1200) {
      scale = 1200.0 / inputImage.width;
      workImage = img.copyResize(inputImage, width: 1200);
    }

    final width = workImage.width;
    final height = workImage.height;
    if (width < 20 || height < 20) return [];

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

    int paperBoxMinX = 0;
    int paperBoxMaxX = width - 1;
    int paperBoxMinY = 0;
    int paperBoxMaxY = height - 1;

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
        paperBoxMinX = (minPaperX + 4).clamp(0, width - 1);
        paperBoxMaxX = (maxPaperX - 4).clamp(0, width - 1);
        paperBoxMinY = (minPaperY + 4).clamp(0, height - 1);
        paperBoxMaxY = (maxPaperY - 4).clamp(0, height - 1);
      }
    }

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

    int erodedCount = 0;
    for (int i = 0; i < eroded.length; i++) {
      if (eroded[i] == 1) erodedCount++;
    }
    final maskToUse = erodedCount >= 6 ? eroded : binMask;
    final double radiusComp = erodedCount >= 6 ? 1.0 : 0.0;

    final visited = List<bool>.filled(width * height, false);
    final List<PrintedDot> detectedDots = [];

    // Filter minimum dot area: at least 6.0 px (radius >= 1.4 px)
    const double minDotArea = 6.0;
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
        if (aspect < 0.45 || aspect > 2.2) continue;

        final double perimeter = perimeterCount.toDouble();
        final double circularity = perimeter > 0 ? (4.0 * pi * pixelCount) / (perimeter * perimeter) : 0;
        if (circularity < 0.38) continue;

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

    return PrintedBrailleDetector.suppressOverlappingDots(detectedDots);
  }

  static Map<String, double> estimatePitches(List<PrintedDot> dots) {
    return PrintedBrailleDetector.estimatePitches(dots);
  }

  static List<List<SegmentedBrailleCell>> segmentDocumentLines(List<PrintedDot> dots) {
    if (dots.length < 3) return [];

    final pitches = estimatePitches(dots);
    final double dx = pitches['dx']!;
    final double dy = pitches['dy']!;
    final double cx = pitches['cx']!;
    final double lineBandHeight = dy * 3.5;

    // Validate that dots exhibit orthogonal Braille lattice properties
    // If dots are randomly scattered with no horizontal or vertical pairs matching the pitch, they are noise!
    int gridPairs = 0;
    for (int i = 0; i < dots.length; i++) {
      for (int j = i + 1; j < dots.length; j++) {
        final dX = (dots[i].x - dots[j].x).abs();
        final dY = (dots[i].y - dots[j].y).abs();
        if (dY <= dy * 0.28 && (dX - dx).abs() <= dx * 0.25) {
          gridPairs++;
        } else if (dX <= dx * 0.28 && (dY - dy).abs() <= dy * 0.25) {
          gridPairs++;
        }
      }
    }

    // A real Braille document with >= 6 dots must have at least ~15% grid pairs per dot
    if (dots.length >= 6 && (gridPairs / dots.length) < 0.12) {
      return [];
    }

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

    rawLines.sort((l1, l2) {
      final y1 = l1.map((d) => d.y).reduce((a, b) => a + b) / l1.length;
      final y2 = l2.map((d) => d.y).reduce((a, b) => a + b) / l2.length;
      return y1.compareTo(y2);
    });

    final validBrailleLines = rawLines.where((l) => l.length >= 2).toList();
    if (validBrailleLines.isEmpty) return [];

    // 3. Clean margins
    final List<List<PrintedDot>> cleanedLines = [];

    for (int lineIdx = 0; lineIdx < validBrailleLines.length; lineIdx++) {
      var lineDots = validBrailleLines[lineIdx];

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

      hSegments.sort((a, b) => b.length.compareTo(a.length));
      lineDots = hSegments.first;
      if (lineDots.length < 2) continue;

      cleanedLines.add(lineDots);
    }

    if (cleanedLines.isEmpty) return [];

    final List<List<SegmentedBrailleCell>> documentLines = [];

    // 4. Segment Cells per Line using Phase-Locked Continuous Lattice
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
            if (diff < dy * 0.38) {
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
        return (d.y - (y0 + r * dy)).abs() < dy * 0.38;
      }).toList();

      if (rowDots.length < 2) continue;
      rowDots.sort((a, b) => a.x.compareTo(b.x));

      // 4A. Natural Cell Clustering
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

      for (int cIdx = 0; cIdx < cellClusters.length; cIdx++) {
        final cluster = cellClusters[cIdx];
        final clusterMinX = cluster.map((d) => d.x).reduce(min);
        final clusterMaxX = cluster.map((d) => d.x).reduce(max);
        final clusterSpanX = clusterMaxX - clusterMinX;

        // Determine if this cluster is a single column or two columns
        final bool isTwoColumns = clusterSpanX >= dx * 0.45;
        int singleCol = 0; // Default to Column 0

        if (!isTwoColumns) {
          // Check distance to next cell
          if (cIdx + 1 < cellClusters.length) {
            final nextX = cellClusters[cIdx + 1].map((d) => d.x).reduce(min);
            final distToNext = nextX - clusterMinX;
            // If distance to next is significantly smaller than cx (closer to cx - dx)
            if (distToNext < (cx - dx * 0.40)) {
              singleCol = 1;
            }
          } else if (cIdx > 0) {
            final prevX = cellClusters[cIdx - 1].map((d) => d.x).reduce(min);
            final distFromPrev = clusterMinX - prevX;
            // If distance from prev is closer to cx + dx than cx
            if (distFromPrev > (cx + dx * 0.40) && distFromPrev < (cx * 1.45)) {
              singleCol = 1;
            }
          }
        }

        final cellMinX = singleCol == 1 ? clusterMinX - dx : clusterMinX;

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
        // Dot 6 capital indicator
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

  static String cleanDecodedText(String text) {
    return PrintedBrailleDetector.cleanDecodedText(text);
  }
}

void main() {
  print('=============================================');
  print('TESTING PRODUCTION PRINTED BRAILLE DETECTOR');
  print('=============================================');

  print('\n--- Test 1: Empty / uniform image ---');
  final blank = img.Image(width: 800, height: 600);
  img.fill(blank, color: img.ColorRgb8(240, 240, 240));
  final decodedBlank = PrintedBrailleDetector.detectAndDecode(blank);
  print('Blank decoded: "$decodedBlank" (Expected: "") -> ${decodedBlank.isEmpty ? "PASS" : "FAIL"}');

  print('\n--- Test 2: Noisy desk/background image without braille ---');
  final noisy = img.Image(width: 800, height: 600);
  for (int y = 0; y < 600; y++) {
    for (int x = 0; x < 800; x++) {
      final noise = ((x * 13 + y * 7 + (x * y) % 31) % 60);
      final c = (180 + noise).clamp(0, 255);
      noisy.setPixelRgb(x, y, c, c - 20, c - 40);
    }
  }
  for (int i = 0; i < 40; i++) {
    final sx = (i * 37) % 750 + 20;
    final sy = (i * 53) % 550 + 20;
    img.fillCircle(noisy, x: sx, y: sy, radius: 4, color: img.ColorRgb8(50, 40, 30));
  }
  final decodedNoisy = PrintedBrailleDetector.detectAndDecode(noisy);
  print('Noisy decoded: "$decodedNoisy" (Expected: "") -> ${decodedNoisy.isEmpty ? "PASS" : "FAIL"}');

  print('\n--- Test 3: Synthetic Grade 1 Braille "braille" ---');
  final brailleImg = renderBrailleWords([
    [1, 2],          // b
    [1, 2, 3, 5],    // r
    [1],             // a
    [2, 4],          // i
    [1, 2, 3],       // l
    [1, 2, 3],       // l
    [1, 5],          // e
  ]);
  final decodedBraille = PrintedBrailleDetector.detectAndDecode(brailleImg);
  print('Braille decoded: "$decodedBraille" (Expected: "braille") -> ${decodedBraille == "braille" ? "PASS" : "FAIL"}');

  print('\n--- Test 4: Grade 1 Braille alphabet "abcdefghijklmnopqrstuvwxyz" ---');
  final allLetters = [
    [1],             // a
    [1, 2],          // b
    [1, 4],          // c
    [1, 4, 5],       // d
    [1, 5],          // e
    [1, 2, 4],       // f
    [1, 2, 4, 5],    // g
    [1, 2, 5],       // h
    [2, 4],          // i
    [2, 4, 5],       // j
    [1, 3],          // k
    [1, 2, 3],       // l
    [1, 3, 4],       // m
    [1, 3, 4, 5],    // n
    [1, 3, 5],       // o
    [1, 2, 3, 4],    // p
    [1, 2, 3, 4, 5], // q
    [1, 2, 3, 5],    // r
    [2, 3, 4],       // s
    [2, 3, 4, 5],    // t
    [1, 3, 6],       // u
    [1, 2, 3, 6],    // v
    [2, 4, 5, 6],    // w
    [1, 3, 4, 6],    // x
    [1, 3, 4, 5, 6], // y
    [1, 3, 5, 6],    // z
  ];
  final alphabetImg = renderBrailleWords(allLetters);
  final decodedAlphabet = PrintedBrailleDetector.detectAndDecode(alphabetImg);
  print('Alphabet decoded: "$decodedAlphabet" (Expected: "abcdefghijklmnopqrstuvwxyz") -> ${decodedAlphabet == "abcdefghijklmnopqrstuvwxyz" ? "PASS" : "FAIL"}');

  print('\n--- Test 5: Numbers "#123" ---');
  final numbers = [
    [3, 4, 5, 6], // #
    [1],          // 1
    [1, 2],       // 2
    [1, 4],       // 3
  ];
  final numbersImg = renderBrailleWords(numbers);
  final decodedNumbers = PrintedBrailleDetector.detectAndDecode(numbersImg);
  print('Numbers decoded: "$decodedNumbers" (Expected: "123") -> ${decodedNumbers == "123" ? "PASS" : "FAIL"}');

  print('\n--- Test 6: Capital word ",braille" -> "Braille" ---');
  final capitalBraille = [
    [6],             // capital indicator (dot 6)
    [1, 2],          // b
    [1, 2, 3, 5],    // r
    [1],             // a
    [2, 4],          // i
    [1, 2, 3],       // l
    [1, 2, 3],       // l
    [1, 5],          // e
  ];
  final capImg = renderBrailleWords(capitalBraille);
  final decodedCap = PrintedBrailleDetector.detectAndDecode(capImg);
  print('Capital decoded: "$decodedCap" (Expected: "Braille") -> ${decodedCap == "Braille" ? "PASS" : "FAIL"}');

  print('\n--- Test 8: Printed Latin English Text (book page with normal letters/lines, NOT braille) ---');
  final latinPage = img.Image(width: 800, height: 600);
  img.fill(latinPage, color: img.ColorRgb8(245, 245, 245));
  for (int line = 0; line < 10; line++) {
    final y = 80 + line * 45;
    for (int word = 0; word < 8; word++) {
      final x = 60 + word * 80;
      for (int c = 0; c < 5; c++) {
        img.fillRect(latinPage, x1: x + c * 12, y1: y, x2: x + c * 12 + 6, y2: y + 14, color: img.ColorRgb8(10, 10, 10));
      }
    }
  }
  final decodedLatin = PrintedBrailleDetector.detectAndDecode(latinPage);
  print('Latin page decoded: "$decodedLatin" (Expected: "") -> ${decodedLatin.isEmpty ? "PASS" : "FAIL"}');

  print('\n--- Test 9: Random polka dots with no Braille grid (irregular spacing) ---');
  final polkaPage = img.Image(width: 800, height: 600);
  img.fill(polkaPage, color: img.ColorRgb8(240, 240, 240));
  for (int i = 0; i < 30; i++) {
    final px = (50 + (i * 79) % 700);
    final py = (50 + (i * 97) % 500);
    img.fillCircle(polkaPage, x: px, y: py, radius: 5, color: img.ColorRgb8(20, 20, 20));
  }
  final decodedPolka = PrintedBrailleDetector.detectAndDecode(polkaPage);
  print('Polka page decoded: "$decodedPolka" (Expected: "") -> ${decodedPolka.isEmpty ? "PASS" : "FAIL"}');

  print('\n--- Test 7: Actual user scanned sheet ---');
  final userFile = File('../embossed_braille_recognition/testing/experiments/test_user_scanned_sheet.jpg');
  if (userFile.existsSync()) {
    final rawUser = img.decodeImage(userFile.readAsBytesSync())!;
    final userImg = img.bakeOrientation(rawUser);
    final userDots = PrintedBrailleDetector.detectDots(userImg);
    print('User sheet dots detected: ${userDots.length}');
    final pitches = PrintedBrailleDetector.estimatePitches(userDots);
    print('User sheet pitches: $pitches');
    final lines = PrintedBrailleDetector.segmentDocumentLines(userDots);
    print('User sheet lines: ${lines.length}');
    for (int i = 0; i < min(5, lines.length); i++) {
      final raw = PrintedBrailleDetector.decodeCellsToRawText(lines[i]);
      print('Line $i raw: "$raw", isSpurious: ${PrintedBrailleDetector.isSpuriousText(raw)}');
    }
    final userText = PrintedBrailleDetector.detectAndDecode(userImg);
    print('User sheet decoded text:\n$userText');
    final hasHappy = userText.contains('happy');
    print('User sheet recognition test -> ${hasHappy ? "PASS" : "FAIL"}');
  } else {
    print('User sheet file not found.');
  }
}

img.Image renderBrailleWords(List<List<int>> wordsDots) {
  final width = 100 + wordsDots.length * 48;
  const int height = 250;
  final canvas = img.Image(width: width, height: height);
  img.fill(canvas, color: img.ColorRgb8(250, 250, 250));

  double startX = 40.0;
  final double startY = 80.0;
  const double dotPitch = 16.0;
  const double interCellPitch = 44.0;

  for (final cellDots in wordsDots) {
    if (cellDots.isEmpty) {
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
      img.fillCircle(canvas, x: cx, y: cy, radius: 4, color: img.ColorRgb8(20, 20, 20));
    }
    startX += interCellPitch;
  }
  return canvas;
}
