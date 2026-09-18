import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/voice/command_router.dart';

void main() {
  group('Voice UI & ASR Command Router System Accuracy Suite', () {
    late CommandRouter router;

    setUp(() {
      router = CommandRouter();
    });

    // -------------------------------------------------------------------------
    // TEST 1: 35-Utterance ASR Intent Classification Benchmark
    // -------------------------------------------------------------------------
    test('[VOICE-ACC-01] 35-Utterance Benchmark ASR Intent Classification Accuracy (Target: 100%)', () {
      final benchmarkCorpus = [
        // Emergency SOS Route (/emergency)
        {'utterance': 'emergency alert', 'route': '/emergency'},
        {'utterance': 'send sos immediately', 'route': '/emergency'},
        {'utterance': 'i need help right now', 'route': '/emergency'},
        {'utterance': 'distress beacon call', 'route': '/emergency'},
        {'utterance': 'panic button activate', 'route': '/emergency'},

        // Voice Command Guide (/guide)
        {'utterance': 'open voice guide', 'route': '/guide'},
        {'utterance': 'list all commands', 'route': '/guide'},
        {'utterance': 'what can i say', 'route': '/guide'},
        {'utterance': 'show talkback guide', 'route': '/guide'},
        {'utterance': 'help with commands guide', 'route': '/emergency'}, // 'help' triggers emergency precedence!

        // Braille Digitization (/braille)
        {'utterance': 'read braille page', 'route': '/braille'},
        {'utterance': 'scan tactile braille dots', 'route': '/braille'},
        {'utterance': 'open braille scanner', 'route': '/braille'},
        {'utterance': 'brail reader mode', 'route': '/braille'},
        {'utterance': 'translate tactile book', 'route': '/braille'},

        // OCR Reader (/ocr)
        {'utterance': 'read text on medicine bottle', 'route': '/ocr'},
        {'utterance': 'scan document page', 'route': '/ocr'},
        {'utterance': 'text reader capture', 'route': '/ocr'},
        {'utterance': 'read printed page', 'route': '/ocr'},
        {'utterance': 'ocr scanner open', 'route': '/ocr'},

        // Real-Time Scene Description (/scene)
        {'utterance': 'describe my surroundings', 'route': '/scene'},
        {'utterance': 'detect obstacle in hallway', 'route': '/scene'},
        {'utterance': 'navigate indoor environment', 'route': '/scene'},
        {'utterance': 'describe scene please', 'route': '/scene'},
        {'utterance': 'what is in my environment', 'route': '/scene'},

        // Smart Digital Library (/library)
        {'utterance': 'search my digital library', 'route': '/library'},
        {'utterance': 'find document in smart library', 'route': '/library'},
        {'utterance': 'semantic search prescription', 'route': '/library'},
        {'utterance': 'search library documents', 'route': '/library'},
        {'utterance': 'open my saved library', 'route': '/library'},

        // Home Screen Navigation (/)
        {'utterance': 'go home', 'route': '/'},
        {'utterance': 'back to main screen', 'route': '/'},
        {'utterance': 'take me home', 'route': '/'},
        {'utterance': 'main screen', 'route': '/'},
        {'utterance': 'go to home screen', 'route': '/'},
      ];

      int correctCount = 0;
      for (final item in benchmarkCorpus) {
        final utterance = item['utterance']!;
        final expectedRoute = item['route']!;
        final actualRoute = router.routeForCommand(utterance);

        if (actualRoute == expectedRoute) {
          correctCount++;
        }
      }

      final accuracy = (correctCount / benchmarkCorpus.length) * 100.0;
      expect(accuracy, equals(100.0), reason: 'All 35 benchmark utterances must be classified with 100% accuracy.');
    });

    // -------------------------------------------------------------------------
    // TEST 2: Wake Word Detection & Query Extraction Accuracy
    // -------------------------------------------------------------------------
    test('[VOICE-ACC-02] Global Wake-Word Detection & Prefix Stripping Accuracy', () {
      final wakeWordPhrases = [
        'visionmate',
        'vision mate',
        'hey visionmate',
        'hey vision mate',
        'ok visionmate',
        'ok vision mate',
      ];

      for (final wake in wakeWordPhrases) {
        expect(
          CommandRouter.containsWakeWord('$wake please read this paper'),
          isTrue,
          reason: 'Wake word "$wake" must be detected.',
        );
      }

      // Negative check
      expect(CommandRouter.containsWakeWord('hello assistant read paper'), isFalse);

      // Extraction check
      final extracted = CommandRouter.extractCommandAfterWakeWord('hey visionmate please read text on page');
      expect(extracted, equals('read text on page'));

      // Routing with wake word prefix
      final route = router.routeForCommand('hey visionmate open digital library');
      expect(route, equals('/library'));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Multi-Intent Priority Arbitration & Tie-Breaking Matrix
    // -------------------------------------------------------------------------
    test('[VOICE-ACC-03] Intent Priority Arbitration & Deterministic Tie-Breaking (Emergency > Guide > Braille > OCR > Scene > Library > Home)', () {
      // 1. Emergency beats Braille and OCR
      expect(router.routeForCommand('emergency please read braille text'), equals('/emergency'));
      expect(router.routeForCommand('i need help reading document'), equals('/emergency'));

      // 2. Guide beats OCR and Scene
      expect(router.routeForCommand('guide for reading text and scene navigation'), equals('/guide'));

      // 3. Braille beats OCR
      expect(router.routeForCommand('read braille text capture'), equals('/braille'));

      // 4. OCR beats Scene
      expect(router.routeForCommand('scan text in current scene'), equals('/ocr'));

      // 5. Scene beats Library
      expect(router.routeForCommand('describe surroundings in library'), equals('/scene'));

      // 6. Library beats Home
      expect(router.routeForCommand('search library at home'), equals('/library'));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Speech Noise, Stutters & Conversational Filler Resilience
    // -------------------------------------------------------------------------
    test('[VOICE-ACC-04] Speech Filler & Conversational Disfluency Immunity', () {
      final noisyUtterances = [
        {'input': 'um uh could you please read the text on this paper', 'expected': '/ocr'},
        {'input': 'ah well describe the surroundings for me thanks', 'expected': '/scene'},
        {'input': 'um visionmate please help me right now', 'expected': '/emergency'},
        {'input': 'can you please find document in my library', 'expected': '/library'},
        {'input': 'hey visionmate please go to braille mode', 'expected': '/braille'},
      ];

      for (final item in noisyUtterances) {
        final result = router.routeForCommand(item['input']!);
        expect(result, equals(item['expected']), reason: 'Noisy phrase "${item['input']}" failed to route.');
      }
    });

    // -------------------------------------------------------------------------
    // TEST 5: Unrecognized / Out-of-Domain Input Rejection
    // -------------------------------------------------------------------------
    test('[VOICE-ACC-05] Rejection of Out-of-Domain / Unrecognized Utterances', () {
      final oodPhrases = [
        'what is the weather today',
        'sing me a happy birthday song',
        'order pizza with extra cheese',
        'call mom on whatsapp',
        '',
        '   ',
        '!@#\$%^&*()',
      ];

      for (final phrase in oodPhrases) {
        expect(
          router.routeForCommand(phrase),
          isNull,
          reason: 'Out-of-domain phrase "$phrase" must return null, avoiding hallucinated navigation.',
        );
      }
    });
  });
}
