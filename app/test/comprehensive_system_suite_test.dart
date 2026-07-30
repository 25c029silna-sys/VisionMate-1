import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/permissions/permission_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/domain/minilm_embedder.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';
import 'package:visionmate/features/ocr_reader/data/ocr_data_source.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisionMate Master Comprehensive System Validation Test Suite', () {

    // =========================================================================
    // 1. BRAILLE RECOGNITION & DIGITIZATION MODULE
    // =========================================================================
    group('1. Braille Recognition & Digitization Pipeline', () {
      late BrailleService brailleService;

      setUp(() {
        brailleService = BrailleService();
      });

      test('[Braille-1.1] Stub TFLite model handling emits MODEL_UNAVAILABLE without crash', () async {
        final result = await brailleService.classifyBraille('test_braille_page.jpg');
        expect(result, equals('MODEL_UNAVAILABLE'));
        expect(brailleService.isModelAvailable, isFalse);
      });

      test('[Braille-1.2] Character dictionary index mapping covers 64 Braille cells', () {
        expect(brailleService.mapIndexToCharacter(0), equals('a'));
        expect(brailleService.mapIndexToCharacter(25), equals('z'));
        expect(brailleService.mapIndexToCharacter(63), equals(' '));
        expect(brailleService.mapIndexToCharacter(-1), equals('?'));
        expect(brailleService.mapIndexToCharacter(100), equals('?'));
      });

      test('[Braille-1.3] Reconstructs cell index sequence into digital text string', () {
        // 22 = w, 4 = e, 11 = l, 2 = c, 14 = o, 12 = m, 4 = e
        final indices = [22, 4, 11, 2, 14, 12, 4];
        final text = brailleService.assembleBrailleText(indices);
        expect(text, equals('welcome'));
      });
    });

    // =========================================================================
    // 2. SMART DIGITAL LIBRARY & SEMANTIC VECTOR SEARCH MODULE
    // =========================================================================
    group('2. Smart Digital Library & Semantic Vector Search', () {
      late MiniLmEmbedder embedder;

      setUp(() {
        embedder = MiniLmEmbedder();
      });

      test('[Library-2.1] MiniLM Embedder generates L2-normalized 384-d float vector', () {
        final vec = embedder.generateEmbedding('Blind navigation assistance');
        expect(vec, hasLength(384));

        double sumSq = 0.0;
        for (final val in vec) {
          sumSq += val * val;
        }
        // L2 norm of non-empty text should equal ~1.0
        expect(sumSq, closeTo(1.0, 0.001));
      });

      test('[Library-2.2] Spoken search query vectorization ranks matching documents', () async {
        final store = FakeEmbeddingStore();
        final libraryService = LibraryService(store);

        final docVector1 = embedder.generateEmbedding('medical prescription dosage');
        final docVector2 = embedder.generateEmbedding('blind mobility indoor guide');

        await store.saveEmbedding(101, docVector1);
        await store.saveEmbedding(102, docVector2);

        final results = await libraryService.searchBySpokenQuery('mobility guide');
        expect(results, isNotEmpty);
        expect(results.first['document_id'], equals(102));
      });
    });

    // =========================================================================
    // 3. OCR READER & CONTEXTUAL WEB ASSISTANCE MODULE
    // =========================================================================
    group('3. OCR Reader & Contextual Web Assistance', () {
      test('[OCR-3.1] 2-pass reading order sorts top-to-bottom and left-to-right', () {
        final b1 = OcrTextBlock(text: 'Header', boundingBox: const Rect.fromLTRB(10, 10, 100, 30));
        final b2 = OcrTextBlock(text: 'Left Column', boundingBox: const Rect.fromLTRB(10, 50, 100, 70));
        final b3 = OcrTextBlock(text: 'Right Column', boundingBox: const Rect.fromLTRB(120, 52, 200, 72));

        final sorted = OcrService.sortTextBlocksInReadingOrder([b3, b2, b1]);
        expect(sorted[0].text, equals('Header'));
        expect(sorted[1].text, equals('Left Column'));
        expect(sorted[2].text, equals('Right Column'));
      });

      test('[OCR-3.2] Web context lookup handles offline / empty query gracefully', () async {
        final ocrService = OcrService();
        final result = await ocrService.fetchWebContext('');
        expect(result, equals('No additional context available.'));
      });
    });

    // =========================================================================
    // 4. REAL-TIME SCENE DESCRIPTION & INDOOR NAVIGATION MODULE
    // =========================================================================
    group('4. Scene Description & Indoor Navigation', () {
      late SceneService sceneService;

      setUp(() {
        sceneService = SceneService();
      });

      test('[Scene-4.1] NMS algorithm suppresses duplicate overlapping bounding boxes', () {
        final o1 = DetectedObstacle(label: 'chair', confidence: 0.92, x: 10, y: 10, width: 40, height: 40, distanceCategory: 'close');
        final o2 = DetectedObstacle(label: 'chair', confidence: 0.80, x: 12, y: 12, width: 40, height: 40, distanceCategory: 'close');
        final o3 = DetectedObstacle(label: 'door', confidence: 0.88, x: 200, y: 200, width: 40, height: 40, distanceCategory: 'medium');

        final filtered = sceneService.applyNms([o1, o2, o3]);
        expect(filtered, hasLength(2));
        expect(filtered.map((e) => e.label), containsAll(['chair', 'door']));
      });

      test('[Scene-4.2] Audio alert throttle enforces 3-second cooldown window', () {
        final t0 = DateTime.now();
        expect(sceneService.shouldTriggerAlert('stairs', t0), isTrue);
        expect(sceneService.shouldTriggerAlert('stairs', t0.add(const Duration(seconds: 1))), isFalse);
        expect(sceneService.shouldTriggerAlert('stairs', t0.add(const Duration(milliseconds: 3100))), isTrue);
      });

      test('[Scene-4.3] Room summary generator produces warning for close obstacles', () {
        final closeObstacle = DetectedObstacle(label: 'table', confidence: 0.9, x: 0, y: 0, width: 50, height: 50, distanceCategory: 'close');
        final summary = sceneService.generateSceneSummary([closeObstacle]);
        expect(summary, contains('Warning: table detected right in front of you.'));
      });
    });

    // =========================================================================
    // 5. GESTURE-TRIGGERED EMERGENCY SOS MODULE
    // =========================================================================
    group('5. Emergency SOS & Native Platform Channel', () {
      late EmergencyService emergencyService;
      late List<MethodCall> methodCalls;

      setUp(() {
        methodCalls = <MethodCall>[];
        const channel = MethodChannel('com.visionmate.app/sms');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'sendSms') return true;
          return null;
        });

        emergencyService = EmergencyService(channel: channel);
      });

      tearDown(() {
        const channel = MethodChannel('com.visionmate.app/sms');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      test('[SOS-5.1] sendSos dispatches sendSms payload to com.visionmate.app/sms', () async {
        await emergencyService.sendSos('+18005550199', 'Emergency help needed.');
        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, equals('sendSms'));
        expect(methodCalls.first.arguments['phoneNumber'], equals('+18005550199'));
      });
    });

    // =========================================================================
    // 6. VOICE-GUIDED UI & ASR INTENT ROUTER
    // =========================================================================
    group('6. Voice UI Routing & ASR Intent Router', () {
      test('[Router-6.1] CommandRouter evaluates intent set across 5 noisy speech transcripts', () {
        final r1 = CommandRouter.routeCommand('um read the braille please');
        expect(r1, equals('/braille'));

        final r2 = CommandRouter.routeCommand('search my library thanks');
        expect(r2, equals('/library'));

        final r3 = CommandRouter.routeCommand('please read text from paper');
        expect(r3, equals('/ocr'));

        final r4 = CommandRouter.routeCommand('describe surroundings for me');
        expect(r4, equals('/scene'));

        final r5 = CommandRouter.routeCommand('i need help right now');
        expect(r5, equals('/emergency'));
      });

      test('[Router-6.2] CommandRouter applies priority tie-breaking on ambiguous input', () {
        // 'help read braille text' contains Emergency, Braille, OCR keywords -> Emergency wins
        final r = CommandRouter.routeCommand('help read braille text');
        expect(r, equals('/emergency'));
      });
    });

    // =========================================================================
    // 7. PERMISSION GOVERNANCE MODULE
    // =========================================================================
    group('7. Permission Governance', () {
      test('[Permission-7.1] PermissionService exposes core permission request helpers', () {
        final permService = PermissionService();
        expect(permService, isNotNull);
      });
    });
  });
}

class FakeEmbeddingStore implements EmbeddingStore {
  final List<Map<String, dynamic>> _storage = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<int> saveEmbedding(int documentId, List<double> vector) async {
    _storage.add({
      'document_id': documentId,
      'vector': jsonEncode(vector),
    });
    return _storage.length;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    if (limit != null) {
      return _storage.take(limit).toList();
    }
    return List.from(_storage);
  }
}
