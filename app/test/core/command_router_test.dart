import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/voice/command_router.dart';

void main() {
  final router = CommandRouter();

  group('CommandRouter ASR Robustness Tests', () {
    final testCases = <Map<String, String?>>[
      // Braille intent test cases
      {'input': 'scan braille', 'expected': '/braille'},
      {'input': 'read braille', 'expected': '/braille'},
      {'input': 'um read the braille please', 'expected': '/braille'},
      {'input': 'can you read braille', 'expected': '/braille'},
      {'input': 'read brail', 'expected': '/braille'},
      {'input': 'braille reading mode', 'expected': '/braille'},
      {'input': 'open the braille scanner', 'expected': '/braille'},

      // Digital Library intent test cases
      {'input': 'search library', 'expected': '/library'},
      {'input': 'semantic search', 'expected': '/library'},
      {'input': 'search my library thanks', 'expected': '/library'},
      {'input': 'find document in my library', 'expected': '/library'},
      {'input': 'could you please search for documents', 'expected': '/library'},

      // OCR Reader intent test cases
      {'input': 'read text', 'expected': '/ocr'},
      {'input': 'read document', 'expected': '/ocr'},
      {'input': 'please read text from paper', 'expected': '/ocr'},
      {'input': 'ocr document reading', 'expected': '/ocr'},
      {'input': 'scan text on page', 'expected': '/ocr'},

      // Scene & Navigation intent test cases
      {'input': 'describe surroundings', 'expected': '/scene'},
      {'input': 'navigate', 'expected': '/scene'},
      {'input': 'can you describe surroundings for me', 'expected': '/scene'},
      {'input': 'is there any obstacle in front of me', 'expected': '/scene'},
      {'input': 'indoor navigation mode', 'expected': '/scene'},

      // Emergency SOS intent test cases
      {'input': 'emergency', 'expected': '/emergency'},
      {'input': 'sos', 'expected': '/emergency'},
      {'input': 'help me please emergency', 'expected': '/emergency'},
      {'input': 'panic button', 'expected': '/emergency'},
      {'input': 'i need help right now', 'expected': '/emergency'},

      // Ambiguity & Tie-Break test cases
      {'input': 'read braille text', 'expected': '/braille'}, // Braille > OCR
      {'input': 'emergency text help', 'expected': '/emergency'}, // Emergency > OCR

      // Unmatched / Out of domain test cases
      {'input': 'what is the weather today', 'expected': null},
      {'input': 'hello computer', 'expected': null},
      {'input': '', 'expected': null},
    ];

    test('All test phrases match expected routes', () {
      int passed = 0;
      int failed = 0;
      final failureDetails = <String>[];

      for (final tc in testCases) {
        final input = tc['input']!;
        final expected = tc['expected'];
        final actual = router.routeForCommand(input);

        if (actual == expected) {
          passed++;
        } else {
          failed++;
          failureDetails.add('Input: "$input" -> Expected: $expected, Actual: $actual');
        }
      }

      print('ASR Robustness Test Summary: $passed/${testCases.length} Passed (${(passed / testCases.length * 100).toStringAsFixed(1)}%)');
      if (failureDetails.isNotEmpty) {
        print('Failures:\n${failureDetails.join('\n')}');
      }

      expect(failed, equals(0), reason: 'All test phrases should route correctly.');
    });
  });
}
