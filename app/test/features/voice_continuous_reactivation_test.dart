import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/app.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';
import 'package:visionmate/features/emergency_sos/presentation/emergency_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 8));
  });

  group('SOS 8-Second Timer & Erroneous Voice Reactivation Suite', () {
    late MockVoiceService mockVoiceService;
    late MockStorageService mockStorageService;
    late CommandRouter commandRouter;

    setUp(() {
      mockVoiceService = MockVoiceService();
      mockStorageService = MockStorageService();
      commandRouter = CommandRouter();

      when(() => mockVoiceService.speak(any(), awaitCompletion: any(named: 'awaitCompletion')))
          .thenAnswer((_) async {});
      when(() => mockVoiceService.speak(any()))
          .thenAnswer((_) async {});
      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async => null);
      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
          )).thenAnswer((_) async => null);
      when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
      when(() => mockVoiceService.stopListening()).thenAnswer((_) async {});
      when(() => mockVoiceService.stopSpeaking()).thenAnswer((_) async {});
      when(() => mockVoiceService.listenForCancellation(duration: any(named: 'duration')))
          .thenAnswer((_) async => false);

      when(() => mockStorageService.getTrustedContact()).thenAnswer((_) async => {
            'name': 'Trusted Guardian',
            'phone': '+19998887777',
          });
    });

    Widget wrapWithProviders(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
          Provider<CommandRouter>.value(value: commandRouter),
          Provider<StorageService>.value(value: mockStorageService),
        ],
        child: MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: child,
        ),
      );
    }

    // =========================================================================
    // 1. EMERGENCY SOS 8-SECOND TIMER VERIFICATION
    // =========================================================================
    testWidgets('EmergencyScreen initializes with 8-second countdown and activates live microphone without TTS blocking timer', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(EmergencyScreen));
      expect((state as dynamic).countdownSeconds, equals(8));

      // Trigger SOS
      await tester.tap(find.widgetWithText(ElevatedButton, 'TRIGGER EMERGENCY SOS\n(SMS + Call with 8s Cancel)'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify listenForCancellation is invoked immediately for 8 seconds duration without TTS talking through timer
      verify(() => mockVoiceService.listenForCancellation(duration: const Duration(seconds: 8))).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    test('EmergencyService executeGlobalSos default cancellationWindow is 8 seconds', () async {
      final service = EmergencyService();
      when(() => mockVoiceService.listenForCancellation(duration: any(named: 'duration')))
          .thenAnswer((invocation) async {
        final duration = invocation.namedArguments[const Symbol('duration')] as Duration;
        expect(duration, equals(const Duration(seconds: 8)));
        return true;
      });

      await service.executeGlobalSos(
        storageService: mockStorageService,
        voiceService: mockVoiceService,
      );

      verify(() => mockVoiceService.speak(
            'Emergency SOS activated by shake gesture. Say CANCEL within 8 seconds to cancel.',
            awaitCompletion: true,
          )).called(1);
    });

    // =========================================================================
    // 2. NO REACTIVATION ON SILENCE / NULL SPEECH
    // =========================================================================
    testWidgets('HomeScreen does NOT reactivate voice recognition when speech returns null/silence', (tester) async {
      int listenCount = 0;
      when(() => mockVoiceService.listen()).thenAnswer((_) async {
        listenCount++;
        return null; // Silence/timeout
      });
      when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds')))
          .thenAnswer((_) async {
        listenCount++;
        return null; // Silence/timeout
      });

      await tester.pumpWidget(wrapWithProviders(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      // Initial voice activation
      expect(listenCount, equals(1));

      // Advance clock
      await tester.pump(const Duration(milliseconds: 600));

      // Must NOT have reactivated on silence
      expect(listenCount, equals(1));

      // Verify status text indicates no input detected without auto-relistening
      expect(find.textContaining('No voice input detected'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    // =========================================================================
    // 3. ELIMINATION OF CONTINUOUS RE-LISTENING ON UNRECOGNIZED COMMAND
    // =========================================================================
    testWidgets('HomeScreen does NOT continuously reactivate voice recognition when unrecognized voice command is gathered', (tester) async {
      int listenCount = 0;
      when(() => mockVoiceService.listen()).thenAnswer((_) async {
        listenCount++;
        if (listenCount == 1) {
          return 'banana potato invalid command';
        }
        return null;
      });
      when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds')))
          .thenAnswer((_) async {
        listenCount++;
        if (listenCount == 1) {
          return 'banana potato invalid command';
        }
        return null;
      });

      await tester.pumpWidget(wrapWithProviders(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      // Initial voice activation only; does NOT trigger continuous mic loop on unrecognized command
      expect(listenCount, equals(1));

      // Verify error announcement was spoken
      verify(() => mockVoiceService.speak(
            'Command not recognized. Tap the voice button, say VisionMate, or say Guide for help.',
          )).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    // =========================================================================
    // 4. REACTIVATION ON BARE WAKE WORD
    // =========================================================================
    testWidgets('HomeScreen DOES reactivate voice recognition when wake word is spoken alone', (tester) async {
      int listenCount = 0;
      when(() => mockVoiceService.listen()).thenAnswer((_) async {
        listenCount++;
        if (listenCount == 1) {
          return 'visionmate';
        }
        return null;
      });
      when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds')))
          .thenAnswer((_) async {
        listenCount++;
        if (listenCount == 1) {
          return 'visionmate';
        }
        return null;
      });

      await tester.pumpWidget(wrapWithProviders(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      // Initial voice activation + reactivation on bare wake word
      expect(listenCount, equals(2));

      // Verify guidance prompt was spoken
      verify(() => mockVoiceService.speak(
            'I am listening. State a feature name like Braille, OCR, Library, Scene, or SOS.',
          )).called(1);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
