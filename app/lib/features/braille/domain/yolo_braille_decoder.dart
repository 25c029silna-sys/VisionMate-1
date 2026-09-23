import 'dart:math';

/// Represents a single detected Braille symbol bounding box.
class BrailleDetection {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final int classIndex;
  final double confidence;
  final String binaryCode;

  BrailleDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.classIndex,
    required this.confidence,
    required this.binaryCode,
  });
}

class YoloBrailleDecoder {
  /// Complete 64-character Braille dictionary including Grade 1 alphabet, numbers, punctuation, and Grade 2 contractions.
  static const Map<String, String> brailleCharMap = {
    '000000': ' ',
    '000001': ',',
    '000010': '',
    '000011': ';',
    '000100': '',
    '000101': '/',
    '000110': '',
    '000111': '?',
    '001000': '\'',
    '001001': '-',
    '001010': '*',
    '001011': '.',
    '001100': '"',
    '001101': '_',
    '001110': '',
    '001111': '#',
    '010000': ';',
    '010001': ',',
    '010010': ':',
    '010011': '.',
    '010100': 'i',
    '010101': '',
    '010110': 'j',
    '010111': 'w',
    '011000': ';',
    '011001': '?',
    '011010': '!',
    '011011': '(',
    '011100': 's',
    '011101': '',
    '011110': 't',
    '011111': '',
    '100000': 'a',
    '100001': '',
    '100010': 'e',
    '100011': '',
    '100100': 'c',
    '100101': '',
    '100110': 'd',
    '100111': '',
    '101000': 'k',
    '101001': 'u',
    '101010': 'o',
    '101011': 'z',
    '101100': 'm',
    '101101': 'x',
    '101110': 'n',
    '101111': 'y',
    '110000': 'b',
    '110001': '',
    '110010': 'h',
    '110011': '',
    '110100': 'f',
    '110101': '',
    '110110': 'g',
    '110111': '',
    '111000': 'l',
    '111001': 'v',
    '111010': 'r',
    '111011': '',
    '111100': 'p',
    '111101': '',
    '111110': 'q',
    '111111': '',
  };

  /// Converts a 6-dot binary code string to its standard Unicode Braille character (U+2800..U+283F).
  /// Formula: 0x2800 + (d1*1 + d2*2 + d3*4 + d4*8 + d5*16 + d6*32)
  /// Empty cell (sum == 0) maps strictly to a literal space ' '.
  static String binaryCodeToUnicode(String binaryCode) {
    if (binaryCode.isEmpty) return ' ';
    int d1 = binaryCode.length > 0 && binaryCode[0] == '1' ? 1 : 0;
    int d2 = binaryCode.length > 1 && binaryCode[1] == '1' ? 1 : 0;
    int d3 = binaryCode.length > 2 && binaryCode[2] == '1' ? 1 : 0;
    int d4 = binaryCode.length > 3 && binaryCode[3] == '1' ? 1 : 0;
    int d5 = binaryCode.length > 4 && binaryCode[4] == '1' ? 1 : 0;
    int d6 = binaryCode.length > 5 && binaryCode[5] == '1' ? 1 : 0;
    int mask = (d1 * 1) + (d2 * 2) + (d3 * 4) + (d4 * 8) + (d5 * 16) + (d6 * 32);
    if (mask == 0) return ' ';
    return String.fromCharCode(0x2800 + mask);
  }

  static const Map<String, String> numberMap = {
    'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
    'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0',
  };

  /// Extracts candidate boxes from tensor shape [1, 68, 8400] and projects them into
  /// original image coordinates using [scale], [padX], [padY], [offsetX], [offsetY].
  static List<BrailleDetection> extractDetections(
    List<dynamic> rawOutput, {
    double scale = 1.0,
    double padX = 0.0,
    double padY = 0.0,
    double offsetX = 0.0,
    double offsetY = 0.0,
    double confidenceThreshold = 0.28,
  }) {
    final List<BrailleDetection> candidates = [];
    final outputTensor = rawOutput[0] as List; // 68 channels x 8400 boxes
    final int numBoxes = (outputTensor[0] as List).length;

    // Selective confidence threshold: single-dot symbols and sparse punctuation marks
    // easily false-trigger on faint paper shadows, wrinkles, or embossing texture.
    // We enforce a higher confidence floor (0.48) for these, while keeping default (0.28-0.30) for standard letters.
    // Note: Class 32 is letter 'a' (binary 100000) and must use standard confidence (0.28).
    const punctuationAndSparseClasses = {
      1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 24, 25, 26
    };

    for (int i = 0; i < numBoxes; i++) {
      final double cx = (outputTensor[0][i] as num).toDouble();
      final double cy = (outputTensor[1][i] as num).toDouble();
      final double w = (outputTensor[2][i] as num).toDouble();
      final double h = (outputTensor[3][i] as num).toDouble();

      int bestClass = 0;
      double maxProb = 0.0;

      // Channels 4 to 67 are the 64 class probabilities
      for (int c = 0; c < 64; c++) {
        final double prob = (outputTensor[4 + c][i] as num).toDouble();
        if (prob > maxProb) {
          maxProb = prob;
          bestClass = c;
        }
      }

      final minRequiredConf = punctuationAndSparseClasses.contains(bestClass)
          ? max(confidenceThreshold, 0.48)
          : confidenceThreshold;

      // Class 0 is '000000' (empty background)
      if (maxProb >= minRequiredConf && bestClass > 0) {
        // Project from 640x640 canvas back to unpadded/tile coordinate space,
        // then apply slice offset (offsetX, offsetY) to reach full image space.
        final double boxX1 = (cx - w / 2.0 - padX) / scale + offsetX;
        final double boxY1 = (cy - h / 2.0 - padY) / scale + offsetY;
        final double boxX2 = (cx + w / 2.0 - padX) / scale + offsetX;
        final double boxY2 = (cy + h / 2.0 - padY) / scale + offsetY;

        final double origW = boxX2 - boxX1;
        final double origH = boxY2 - boxY1;
        final double origCx = (boxX1 + boxX2) / 2.0;
        final double origCy = (boxY1 + boxY2) / 2.0;

        final String binary = bestClass.toRadixString(2).padLeft(6, '0');

        candidates.add(BrailleDetection(
          x1: boxX1,
          y1: boxY1,
          x2: boxX2,
          y2: boxY2,
          cx: origCx,
          cy: origCy,
          width: origW,
          height: origH,
          classIndex: bestClass,
          confidence: maxProb,
          binaryCode: binary,
        ));
      }
    }

    return candidates;
  }

  /// Runs NMS and line reconstruction on an aggregated list of candidate detections.
  static String reconstructFromDetections(
    List<BrailleDetection> candidates, {
    double iouThreshold = 0.40,
  }) {
    if (candidates.isEmpty) {
      return '';
    }

    // Non-Maximum Suppression (NMS) across all candidates
    final List<BrailleDetection> filtered = runNms(candidates, iouThreshold);
    if (filtered.isEmpty) {
      return '';
    }

    // Line Clustering and Reading Order Sorting
    return reconstructText(filtered);
  }

  /// Decodes raw YOLOv8 output tensor [1, 68, 8400] into formatted text.
  static String decodeYoloOutput(
    List<dynamic> rawOutput, {
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
  }) {
    final candidates = extractDetections(
      rawOutput,
      scale: 1.0,
      padX: 0.0,
      padY: 0.0,
      offsetX: 0.0,
      offsetY: 0.0,
      confidenceThreshold: confidenceThreshold,
    );
    return reconstructFromDetections(candidates, iouThreshold: iouThreshold);
  }

  /// Non-Maximum Suppression to remove duplicate bounding boxes for the same character.
  static List<BrailleDetection> runNms(List<BrailleDetection> boxes, double iouThreshold) {
    // Sort descending by confidence
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<BrailleDetection> keep = [];
    final List<bool> suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      keep.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;

        final double iou = calculateIoU(boxes[i], boxes[j]);
        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return keep;
  }

  /// Calculates Intersection over Union (IoU) between two bounding boxes.
  static double calculateIoU(BrailleDetection a, BrailleDetection b) {
    final double xx1 = max(a.x1, b.x1);
    final double yy1 = max(a.y1, b.y1);
    final double xx2 = min(a.x2, b.x2);
    final double yy2 = min(a.y2, b.y2);

    final double interW = max(0.0, xx2 - xx1);
    final double interH = max(0.0, yy2 - yy1);
    final double interArea = interW * interH;

    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;
    final double unionArea = areaA + areaB - interArea;

    if (unionArea <= 0.0) return 0.0;
    return interArea / unionArea;
  }

  /// Reconstructs lines and words in natural reading order (top-to-bottom, left-to-right).
  static String reconstructText(List<BrailleDetection> detections) {
    if (detections.isEmpty) return '';

    // Calculate median character dimensions to detect line breaks and word spaces
    final List<double> heights = detections.map((d) => d.height).toList()..sort();
    final List<double> widths = detections.map((d) => d.width).toList()..sort();
    final double medianH = heights[heights.length ~/ 2];
    final double medianW = widths[widths.length ~/ 2];

    // Sort primarily by vertical Y position
    final sortedByY = List<BrailleDetection>.from(detections)
      ..sort((a, b) => a.cy.compareTo(b.cy));

    final List<List<BrailleDetection>> lines = [];
    List<BrailleDetection> currentLine = [];
    double currentLineAvgY = -1.0;

    for (final d in sortedByY) {
      if (currentLineAvgY < 0) {
        currentLine.add(d);
        currentLineAvgY = d.cy;
      } else if ((d.cy - currentLineAvgY).abs() < (medianH * 0.85)) {
        currentLine.add(d);
        final sumY = currentLine.fold<double>(0.0, (acc, item) => acc + item.cy);
        currentLineAvgY = sumY / currentLine.length;
      } else {
        currentLine.sort((a, b) => a.cx.compareTo(b.cx));
        lines.add(currentLine);
        currentLine = [d];
        currentLineAvgY = d.cy;
      }
    }

    if (currentLine.isNotEmpty) {
      currentLine.sort((a, b) => a.cx.compareTo(b.cx));
      lines.add(currentLine);
    }

    // Assemble text line-by-line
    final buffer = StringBuffer();
    bool isNumberMode = false;
    bool isCapitalMode = false;

    for (int l = 0; l < lines.length; l++) {
      final line = lines[l];
      double lastX2 = -1.0;
      double lastCx = -1.0;

      for (final d in line) {
        // Dynamic Spacing Calibration:
        // Do NOT emit an empty space ' ' unless the horizontal gap between two consecutive 2x3 cells
        // is strictly greater than 1.5 times the inter-cell pitch (cx).
        // Any gap smaller than this MUST be treated as contiguous characters within the same word.
        final double cx = medianW * 1.20;
        final bool isSpace = lastCx > 0 && (d.cx - lastCx) > (1.5 * cx);
        if (isSpace) {
          buffer.write(' ');
          isNumberMode = false;
        }
        lastX2 = d.x2;
        lastCx = d.cx;

        final rawChar = brailleCharMap[d.binaryCode] ?? '?';

        if (rawChar == '#') {
          isNumberMode = true;
          continue;
        }
        if (rawChar == ',') {
          isCapitalMode = true;
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

      if (l < lines.length - 1) {
        buffer.write('\n');
      }
      isNumberMode = false;
      isCapitalMode = false;
    }

    final rawText = buffer.toString();

    // Clean up unnecessary punctuation & spacing artifacts:
    // 1. Remove orphan punctuation marks sitting alone between spaces or at line boundaries
    String cleaned = rawText
        .replaceAll(RegExp(r"(?<=\s)[;',\-\*\.\:\?\!/]+(?=\s|$)"), '')
        .replaceAll(RegExp(r"^[;',\-\*\.\:\?\!/]+\s*"), '')
        .replaceAll(RegExp(r"\s*[;',\-\*\.\:\?\!/]+$"), '');

    // 2. Remove stray semicolons/punctuation embedded inside words (e.g. "u;k" -> "uk", "l;k" -> "lk")
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([a-zA-Z0-9])[;:]+([a-zA-Z0-9])'),
      (m) => '${m[1]}${m[2]}',
    );

    // 3. Collapse multiple consecutive punctuation marks
    cleaned = cleaned.replaceAll(RegExp(r'[;]{2,}'), ';');

    // 4. Merge sequences of 3+ single letters separated by a single space (e.g. "p a a" -> "paa", "c k a m a" -> "ckama")
    // Standalone 2-letter Grade-2 sequences (e.g. "c y" for "can you", "b y" for "but you", "d y" for "do you")
    // must NOT be merged so that Grade-2 contraction expansions work properly.
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\b[a-zA-Z](?: [a-zA-Z]){2,}\b'),
      (match) {
        final segment = match.group(0)!;
        final letters = segment.split(' ');
        return letters.join('');
      },
    );

    // 5. Collapse multiple spaces and format lines
    final linesList = cleaned
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s{2,}'), ' ').trim())
        .where((line) => line.isNotEmpty);

    return linesList.join('\n').trim();
  }
}
