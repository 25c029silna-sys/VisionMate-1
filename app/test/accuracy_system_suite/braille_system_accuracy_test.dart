import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/braille/domain/braille_text_refiner.dart';
import 'package:visionmate/features/braille/domain/yolo_braille_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Braille Recognition & Digitization System Accuracy Suite', () {
    late BrailleService brailleService;

    setUp(() {
      brailleService = BrailleService();
    });

    tearDown(() {
      brailleService.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 1: Dictionary Mapping Accuracy (64 Braille Cells)
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-01] 64-Cell Braille Dictionary Character Mapping Accuracy', () {
      // Ground truth mappings for core alphabet and special symbols
      final Map<int, String> groundTruth = {
        0: ' ',   // Blank cell
        1: ',',   // Capital indicator
        8: '\'',
        9: '-',
        10: '*',
        14: '(',
        15: '#',  // Number indicator
        16: '"',
        18: ':',
        19: ')',
        20: 'i',
        22: 'j',
        23: 'w',
        24: ';',
        26: '!',
        28: 's',
        30: 't',
        32: 'a',
        34: 'e',
        36: 'c',
        38: 'd',
        40: 'k',
        41: 'u',
        42: 'o',
        43: 'z',
        44: 'm',
        45: 'x',
        46: 'n',
        47: 'y',
        48: 'b',
        50: 'h',
        52: 'f',
        54: 'g',
        56: 'l',
        57: 'v',
        58: 'r',
        60: 'p',
        62: 'q',
      };

      int correctCount = 0;
      for (final entry in groundTruth.entries) {
        final mapped = brailleService.mapIndexToCharacter(entry.key);
        if (mapped == entry.value) {
          correctCount++;
        }
      }

      final accuracy = (correctCount / groundTruth.length) * 100.0;
      expect(accuracy, equals(100.0), reason: 'All tested Braille cell mappings must match ground truth exactly.');

      // Out of bounds check
      expect(brailleService.mapIndexToCharacter(-1), equals('?'));
      expect(brailleService.mapIndexToCharacter(64), equals('?'));
      expect(brailleService.mapIndexToCharacter(999), equals('?'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Number Mode (#) Conversion Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-02] Number Prefix (# / Cell 15) Translation Accuracy', () {
      // a..j mapped to 1..0 after '#'
      // 32='a'->'1', 48='b'->'2', 36='c'->'3', 38='d'->'4', 34='e'->'5',
      // 52='f'->'6', 54='g'->'7', 50='h'->'8', 20='i'->'9', 22='j'->'0'
      final cellIndices = [15, 32, 48, 36, 38, 34, 52, 54, 50, 20, 22];
      final decoded = brailleService.assembleBrailleText(cellIndices);
      expect(decoded, equals('1234567890'));

      // Mixed digits and text: "#ab c" -> "12 c"
      final mixedIndices = [15, 32, 48, 0, 36];
      final mixedDecoded = brailleService.assembleBrailleText(mixedIndices);
      expect(mixedDecoded, equals('12 c'));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Capital Indicator (,) Translation Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-03] Capital Indicator (, / Cell 1) Translation Accuracy', () {
      // ',w', 'e', 'l', 'c', 'o', 'm', 'e' -> "Welcome"
      // 1=',', 23='w', 34='e', 56='l', 36='c', 42='o', 44='m', 34='e'
      final indices = [1, 23, 34, 56, 36, 42, 44, 34];
      final decoded = brailleService.assembleBrailleText(indices);
      expect(decoded, equals('Welcome'));

      // Multiple capitals: ",a,b" -> "AB"
      final allCaps = [1, 32, 1, 48];
      expect(brailleService.assembleBrailleText(allCaps), equals('AB'));
    });

    // -------------------------------------------------------------------------
    // TEST 4: YOLO Bounding Box Coordinate Transformation Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-04] YOLOv8 Coordinate Inverse Transformation & Seam Offset Accuracy', () {
      // Simulated YOLO output tensor [1, 68, 1]
      // Canvas center (320, 320, 40, 60), letterbox scale=0.5, padX=20, padY=50, slice offsetY=400
      final rawOut = List.generate(
        1,
        (_) => List.generate(
          68,
          (channel) {
            if (channel == 0) return [320.0]; // cx
            if (channel == 1) return [320.0]; // cy
            if (channel == 2) return [40.0];  // w
            if (channel == 3) return [60.0];  // h
            if (channel == 4 + 32) return [0.92]; // class 32 (letter 'a')
            return [0.0];
          },
        ),
      );

      final detections = YoloBrailleDecoder.extractDetections(
        rawOut,
        scale: 0.5,
        padX: 20.0,
        padY: 50.0,
        offsetX: 100.0,
        offsetY: 400.0,
        confidenceThreshold: 0.25,
      );

      expect(detections.length, equals(1));
      final d = detections.first;
      expect(d.classIndex, equals(32));
      expect(d.confidence, equals(0.92));

      // Expected math:
      // cx = (320 - 20) / 0.5 + 100 = 300 / 0.5 + 100 = 700
      // cy = (320 - 50) / 0.5 + 400 = 270 / 0.5 + 400 = 940
      // w  = 40 / 0.5 = 80
      // h  = 60 / 0.5 = 120
      // x1 = cx - w/2 = 700 - 40 = 660
      // y1 = cy - h/2 = 940 - 60 = 880
      expect(d.cx, closeTo(700.0, 0.01));
      expect(d.cy, closeTo(940.0, 0.01));
      expect(d.width, closeTo(80.0, 0.01));
      expect(d.height, closeTo(120.0, 0.01));
      expect(d.x1, closeTo(660.0, 0.01));
      expect(d.y1, closeTo(880.0, 0.01));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Overlapping Seam NMS Deduplication Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-05] Seam Overlap NMS Deduplication Precision', () {
      // 3 detections across tiled slices: 2 overlapping 'a' boxes (seam duplicate) + 1 distinct 'b' box
      final boxA1 = BrailleDetection(
        x1: 100, y1: 200, x2: 150, y2: 270,
        cx: 125, cy: 235, width: 50, height: 70,
        classIndex: 32, confidence: 0.88, binaryCode: '100000',
      );
      final boxA2 = BrailleDetection(
        x1: 104, y1: 202, x2: 152, y2: 272,
        cx: 128, cy: 237, width: 48, height: 70,
        classIndex: 32, confidence: 0.94, binaryCode: '100000', // higher confidence
      );
      final boxB = BrailleDetection(
        x1: 170, y1: 200, x2: 220, y2: 270,
        cx: 195, cy: 235, width: 50, height: 70,
        classIndex: 48, confidence: 0.91, binaryCode: '110000',
      );

      final reconstructed = YoloBrailleDecoder.reconstructFromDetections(
        [boxA1, boxA2, boxB],
        iouThreshold: 0.40,
      );

      expect(reconstructed, equals('ab'), reason: 'Duplicate box A1 must be suppressed by A2, resulting in exactly "ab".');
    });

    // -------------------------------------------------------------------------
    // TEST 6: Word Gap vs Inter-Character Spacing Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-06] Word Space Detection Accuracy (Threshold = 1.55 * medianW)', () {
      // medianW = 40. Word space requires gap >= 1.55 * 40 = 62px.
      // Character 1: 'c' at cx=100
      final d1 = BrailleDetection(
        x1: 80, y1: 100, x2: 120, y2: 160,
        cx: 100, cy: 130, width: 40, height: 60,
        classIndex: 36, confidence: 0.9, binaryCode: '100100',
      );
      // Character 2: 'a' at cx=142 (gap = 42 < 62 -> same word)
      final d2 = BrailleDetection(
        x1: 122, y1: 100, x2: 162, y2: 160,
        cx: 142, cy: 130, width: 40, height: 60,
        classIndex: 32, confidence: 0.9, binaryCode: '100000',
      );
      // Character 3: 't' at cx=184 (gap = 42 < 62 -> same word)
      final d3 = BrailleDetection(
        x1: 164, y1: 100, x2: 204, y2: 160,
        cx: 184, cy: 130, width: 40, height: 60,
        classIndex: 30, confidence: 0.9, binaryCode: '011110',
      );
      // Character 4: 'i' at cx=260 (gap = 76 >= 62 -> new word space!)
      final d4 = BrailleDetection(
        x1: 240, y1: 100, x2: 280, y2: 160,
        cx: 260, cy: 130, width: 40, height: 60,
        classIndex: 20, confidence: 0.9, binaryCode: '010100',
      );
      // Character 5: 's' at cx=302 (gap = 42 < 62 -> same word)
      final d5 = BrailleDetection(
        x1: 282, y1: 100, x2: 322, y2: 160,
        cx: 302, cy: 130, width: 40, height: 60,
        classIndex: 28, confidence: 0.9, binaryCode: '011100',
      );

      final result = YoloBrailleDecoder.reconstructFromDetections([d1, d2, d3, d4, d5]);
      expect(result, equals('cat is'), reason: 'Proper word break must be inserted between "cat" and "is".');
    });

    // -------------------------------------------------------------------------
    // TEST 7: Multi-Line Braille Reading Order Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-07] Multi-Line Page Reading Order Clustered by Line Band', () {
      // Line 1: "go" at y=100
      final l1c1 = BrailleDetection(x1: 100, y1: 95, x2: 140, y2: 155, cx: 120, cy: 125, width: 40, height: 60, classIndex: 54, confidence: 0.95, binaryCode: '110110'); // 'g'
      final l1c2 = BrailleDetection(x1: 145, y1: 102, x2: 185, y2: 162, cx: 165, cy: 132, width: 40, height: 60, classIndex: 42, confidence: 0.95, binaryCode: '101010'); // 'o'

      // Line 2: "to" at y=220
      final l2c1 = BrailleDetection(x1: 100, y1: 215, x2: 140, y2: 275, cx: 120, cy: 245, width: 40, height: 60, classIndex: 30, confidence: 0.95, binaryCode: '011110'); // 't'
      final l2c2 = BrailleDetection(x1: 145, y1: 222, x2: 185, y2: 282, cx: 165, cy: 252, width: 40, height: 60, classIndex: 42, confidence: 0.95, binaryCode: '101010'); // 'o'

      // Shuffled order input
      final shuffled = [l2c2, l1c1, l2c1, l1c2];
      final reconstructed = YoloBrailleDecoder.reconstructFromDetections(shuffled);

      expect(reconstructed, equals('go\nto'), reason: 'Lines must be ordered top-to-bottom, left-to-right.');
    });

    // -------------------------------------------------------------------------
    // TEST 8: Synthetic Page End-to-End Accuracy (CER & WER)
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-08] End-to-End Synthetic Page Benchmark (CER = 0.0%, WER = 0.0%)', () {
      // Ground truth target: "vision mate assistance"
      const groundTruthText = 'vision mate assistance';

      // Assemble cell indices for target
      // v=57, i=20, s=28, i=20, o=42, n=46, ' '=0
      // m=44, a=32, t=30, e=34, ' '=0
      // a=32, s=28, s=28, i=20, s=28, t=30, a=32, n=46, c=36, e=34
      final sentenceIndices = [
        57, 20, 28, 20, 42, 46, 0,
        44, 32, 30, 34, 0,
        32, 28, 28, 20, 28, 30, 32, 46, 36, 34
      ];

      final output = brailleService.assembleBrailleText(sentenceIndices);
      expect(output, equals(groundTruthText));

      // Calculate Character Error Rate (CER)
      int charErrors = 0;
      for (int i = 0; i < groundTruthText.length; i++) {
        if (i >= output.length || output[i] != groundTruthText[i]) {
          charErrors++;
        }
      }
      final cer = (charErrors / groundTruthText.length) * 100.0;
      expect(cer, equals(0.0), reason: 'Character Error Rate on clean sequence should be 0.0%.');

      // Calculate Word Error Rate (WER)
      final gtWords = groundTruthText.split(' ');
      final outWords = output.split(' ');
      int wordErrors = 0;
      for (int i = 0; i < gtWords.length; i++) {
        if (i >= outWords.length || outWords[i] != gtWords[i]) {
          wordErrors++;
        }
      }
      final wer = (wordErrors / gtWords.length) * 100.0;
      expect(wer, equals(0.0), reason: 'Word Error Rate on clean sequence should be 0.0%.');
    });

    // -------------------------------------------------------------------------
    // TEST 9: Offline Text Refiner & Spell-Correction Accuracy
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-09] BrailleTextRefiner Offline Dictionary & Short-form Accuracy', () {
      // 1. Number sign decoding (#cj -> 30, #aiai -> 1719)
      final rawNumbers = 'page #cj chapter #a';
      final cleanNumbers = BrailleTextRefiner.refineOffline(rawNumbers);
      expect(cleanNumbers, contains('page 30 chapter 1'));

      // 2. Grade 2 short-forms expansion (cd -> could, fr -> friends)
      final rawShortForms = 'swami cd see his fr in school';
      final cleanShortForms = BrailleTextRefiner.refineOffline(rawShortForms);
      expect(cleanShortForms, contains('could'));
      expect(cleanShortForms, contains('friends'));

      // 3. Conjunction separation (lifeand -> life and)
      final rawConjunction = 'knowledge lifeand light';
      final cleanConjunction = BrailleTextRefiner.refineOffline(rawConjunction);
      expect(cleanConjunction, equals('knowledge life and light'));
    });

    // -------------------------------------------------------------------------
    // TEST 10: Model Unavailable Graceful Degradation
    // -------------------------------------------------------------------------
    test('[BRAILLE-ACC-10] Non-Existent Image Handling Emits Controlled Fallback Message', () async {
      final result = await brailleService.classifyBraille('non_existent_braille_path.jpg');
      expect(result, anyOf(equals('MODEL_UNAVAILABLE'), equals('No image captured. Please try again.')));
    });
  });
}
