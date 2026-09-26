import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/braille/presentation/widgets/voice_pdf_naming_dialog.dart';

class MockVoiceService extends Mock implements VoiceService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrailleService PDF Voice Naming Unit Tests', () {
    test('cleanPdfName formats input to Title Case and strips punctuation', () {
      expect(BrailleService.cleanPdfName('biology notes.'), equals('Biology Notes'));
      expect(BrailleService.cleanPdfName('physics exam 1!'), equals('Physics Exam 1'));
      expect(BrailleService.cleanPdfName('   chemistry   assignment   '), equals('Chemistry Assignment'));
    });

    test('cleanPdfName strips conversational carrier prefixes', () {
      expect(BrailleService.cleanPdfName('save as biology homework'), equals('Biology Homework'));
      expect(BrailleService.cleanPdfName('save pdf as final report'), equals('Final Report'));
      expect(BrailleService.cleanPdfName('name it chapter four'), equals('Chapter Four'));
      expect(BrailleService.cleanPdfName('call it my story'), equals('My Story'));
      expect(BrailleService.cleanPdfName('save with name test doc'), equals('Test Doc'));
      expect(BrailleService.cleanPdfName('export as history paper'), equals('History Paper'));
      expect(BrailleService.cleanPdfName('export pdf named lecture notes'), equals('Lecture Notes'));
      expect(BrailleService.cleanPdfName('please save as math quiz'), equals('Math Quiz'));
    });

    test('cleanPdfName strips invalid filesystem characters', () {
      expect(BrailleService.cleanPdfName('math/science:exam*2?'), equals('Mathscienceexam2'));
      expect(BrailleService.cleanPdfName('doc<with>illegal|chars"'), equals('Docwithillegalchars'));
    });

    test('cleanPdfName returns empty string on empty or whitespace-only input', () {
      expect(BrailleService.cleanPdfName(''), equals(''));
      expect(BrailleService.cleanPdfName('   '), equals(''));
      expect(BrailleService.cleanPdfName('save as'), equals(''));
    });

    test('extractPdfNameFromCommand parses explicit "as" and "named" phrases', () {
      expect(
        BrailleService.extractPdfNameFromCommand('save pdf as biology chapter one'),
        equals('Biology Chapter One'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('save as my braille sheet'),
        equals('My Braille Sheet'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('export pdf named english essay'),
        equals('English Essay'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('save with name chemistry lab'),
        equals('Chemistry Lab'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('export document as history quiz'),
        equals('History Quiz'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('save pdf called recipes'),
        equals('Recipes'),
      );
    });

    test('extractPdfNameFromCommand parses "save pdf <name>" direct pattern', () {
      expect(
        BrailleService.extractPdfNameFromCommand('save pdf geometry notes'),
        equals('Geometry Notes'),
      );
      expect(
        BrailleService.extractPdfNameFromCommand('export pdf algebra homework'),
        equals('Algebra Homework'),
      );
    });

    test('extractPdfNameFromCommand returns null when no custom name is given', () {
      expect(BrailleService.extractPdfNameFromCommand('save pdf'), isNull);
      expect(BrailleService.extractPdfNameFromCommand('export pdf'), isNull);
      expect(BrailleService.extractPdfNameFromCommand('pdf'), isNull);
      expect(BrailleService.extractPdfNameFromCommand('save'), isNull);
      expect(BrailleService.extractPdfNameFromCommand('save pdf now'), isNull);
      expect(BrailleService.extractPdfNameFromCommand('save pdf please'), isNull);
      expect(BrailleService.extractPdfNameFromCommand(''), isNull);
    });
  });

  group('VoicePdfNamingDialog Widget Tests', () {
    late MockVoiceService mockVoiceService;

    setUp(() {
      mockVoiceService = MockVoiceService();
      when(() => mockVoiceService.speak(any())).thenAnswer((_) async {});
      when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
    });

    Widget createTestDialog({String? initialName}) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  VoicePdfNamingDialog.show(
                    context,
                    voiceService: mockVoiceService,
                    initialName: initialName,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );
    }

    testWidgets('Renders dialog header, voice banner, text field, and action buttons', (tester) async {
      await tester.pumpWidget(createTestDialog(initialName: 'Initial Test Doc'));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Save Braille PDF'), findsOneWidget);
      expect(find.text('Speak or type the document name'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
      expect(find.text('Save PDF'), findsOneWidget);
      expect(find.text('Use Default'), findsOneWidget);
      expect(find.text('Initial Test Doc'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);

      verify(() => mockVoiceService.speak(any(that: contains('Please speak the name')))).called(1);
    });

    testWidgets('Automatically prompts for voice and sets spoken name', (tester) async {
      when(() => mockVoiceService.listen()).thenAnswer((_) async => 'biology assignment');

      String? resultName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    resultName = await VoicePdfNamingDialog.show(
                      context,
                      voiceService: mockVoiceService,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      verify(() => mockVoiceService.speak(any(that: contains('Document name set to Biology Assignment')))).called(1);
      expect(resultName, equals('Biology Assignment'));
    });

    testWidgets('Voice cancellation pops dialog with null', (tester) async {
      when(() => mockVoiceService.listen()).thenAnswer((_) async => 'cancel');

      String? resultName = 'not_cancelled';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    resultName = await VoicePdfNamingDialog.show(
                      context,
                      voiceService: mockVoiceService,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      verify(() => mockVoiceService.speak('PDF export cancelled.')).called(1);
      expect(resultName, isNull);
    });

    testWidgets('Tapping Use Default returns timestamped default name', (tester) async {
      String? resultName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    resultName = await VoicePdfNamingDialog.show(
                      context,
                      voiceService: mockVoiceService,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final useDefaultBtn = find.text('Use Default');
      expect(useDefaultBtn, findsOneWidget);

      await tester.tap(useDefaultBtn);
      await tester.pumpAndSettle();

      expect(resultName, isNotNull);
      expect(resultName, startsWith('Braille Document ('));
    });

    testWidgets('Tapping Save PDF confirms entered text', (tester) async {
      String? resultName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    resultName = await VoicePdfNamingDialog.show(
                      context,
                      voiceService: mockVoiceService,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter custom name manually in text field
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Custom Literature Notes');
      await tester.pumpAndSettle();

      final savePdfBtn = find.text('Save PDF');
      await tester.tap(savePdfBtn);
      await tester.pumpAndSettle();

      expect(resultName, equals('Custom Literature Notes'));
    });
  });
}
