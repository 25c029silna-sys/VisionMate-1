import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/features/braille/presentation/braille_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrailleScreen Widget Tests', () {
    late MockVoiceService mockVoiceService;

    setUp(() {
      mockVoiceService = MockVoiceService();
      when(() => mockVoiceService.speak(any())).thenAnswer((_) async {});
      when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
      when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds'))).thenAnswer((_) async => null);
    });

    Widget createTestableWidget() {
      return ChangeNotifierProvider<VoiceService>.value(
        value: mockVoiceService,
        child: const MaterialApp(
          home: BrailleScreen(),
        ),
      );
    }

    testWidgets('Renders BrailleScreen title, camera view area, and scan button', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Braille Page Recognition'), findsOneWidget);
      expect(find.text('Scan Braille'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('Tapping Scan Braille triggers scan sequence and voice feedback', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final scanButton = find.text('Scan Braille');
      expect(scanButton, findsOneWidget);

      await tester.tap(scanButton);
      await tester.pump(const Duration(milliseconds: 500));

      verify(() => mockVoiceService.speak(any())).called(greaterThanOrEqualTo(1));
    });
  });
}
