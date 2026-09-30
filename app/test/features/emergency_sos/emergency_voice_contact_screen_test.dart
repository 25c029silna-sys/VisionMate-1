import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/emergency_sos/presentation/emergency_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 8));
  });

  group('EmergencyScreen Voice-Activated Contact Tests', () {
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
            'name': 'Alex Emergency',
            'phone': '+15551234567',
          });
      when(() => mockStorageService.saveTrustedContact(
            name: any(named: 'name'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async {});
    });

    Widget wrapWithProviders(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
          Provider<CommandRouter>.value(value: commandRouter),
          Provider<StorageService>.value(value: mockStorageService),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('renders contact card with Voice Configure mic button and VOICE EDIT CONTACT button', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('TRUSTED EMERGENCY CONTACT'), findsOneWidget);
      expect(find.text('Alex Emergency (+15551234567)'), findsOneWidget);
      expect(find.byTooltip('Voice Configure Contact'), findsWidgets);
      expect(find.text('VOICE EDIT CONTACT'), findsOneWidget);
    });

    testWidgets('VOICE ADD CONTACT button renders when no contact is configured', (tester) async {
      when(() => mockStorageService.getTrustedContact()).thenAnswer((_) async => {
            'name': '',
            'phone': '',
          });

      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('VOICE ADD CONTACT'), findsOneWidget);
      expect(find.text('No Contact Configured'), findsOneWidget);
    });

    testWidgets('startVoiceContactSetup executes guided voice configuration and saves contact on confirmation', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // After initial postFrameCallback completes, stub sequential voice inputs for the wizard:
      int step = 0;
      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async {
        step++;
        if (step == 1) return 'Dr Sarah Connor'; // Step 1: Name
        if (step == 2) return 'nine eight seven six five four three two one zero'; // Step 2: Phone
        if (step == 3) return 'confirm'; // Step 3: Confirmation
        return null;
      });

      final state = tester.state(find.byType(EmergencyScreen)) as dynamic;
      await state.startVoiceContactSetup();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify contact was saved with parsed digits
      verify(() => mockStorageService.saveTrustedContact(
            name: 'Dr Sarah Connor',
            phone: '9876543210',
          )).called(1);

      // Verify success announcement
      verify(() => mockVoiceService.speak('Emergency contact Dr Sarah Connor saved successfully.')).called(1);
    });

    testWidgets('saying "cancel" during name step aborts without saving', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async => 'cancel');

      final state = tester.state(find.byType(EmergencyScreen)) as dynamic;
      await state.startVoiceContactSetup();
      await tester.pump(const Duration(milliseconds: 100));

      verifyNever(() => mockStorageService.saveTrustedContact(
            name: any(named: 'name'),
            phone: any(named: 'phone'),
          ));
      verify(() => mockVoiceService.speak('Contact configuration cancelled.')).called(1);
    });

    testWidgets('saying "keep" during edit retains existing name', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      int step = 0;
      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async {
        step++;
        if (step == 1) return 'keep'; // Retain Alex Emergency
        if (step == 2) return '5550199'; // New phone
        if (step == 3) return 'yes'; // Confirm
        return null;
      });

      final state = tester.state(find.byType(EmergencyScreen)) as dynamic;
      await state.startVoiceContactSetup();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockStorageService.saveTrustedContact(
            name: 'Alex Emergency',
            phone: '5550199',
          )).called(1);
    });

    testWidgets('one-shot direct voice command extracts contact and saves on confirmation', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async => 'confirm');

      final state = tester.state(find.byType(EmergencyScreen)) as dynamic;
      await state.startVoiceContactSetup(initialUtterance: 'add contact Mom 1234567890');
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockStorageService.saveTrustedContact(
            name: 'Mom',
            phone: '1234567890',
          )).called(1);
      verify(() => mockVoiceService.speak('Emergency contact Mom saved successfully.')).called(1);
    });

    testWidgets('voice command "contact" triggers voice contact setup from main listener', (tester) async {
      // In this test, the initial voice command listened at startup is "contact"
      int step = 0;
      when(() => mockVoiceService.listen(
            listenDurationSeconds: any(named: 'listenDurationSeconds'),
            pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
          )).thenAnswer((_) async {
        step++;
        if (step == 1) return 'contact'; // Heard by _handleVoiceCommand
        if (step == 2) return 'cancel'; // Cancels name step
        return null;
      });

      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify that contact configuration wizard was launched and then cancelled
      verify(() => mockVoiceService.speak('Contact configuration cancelled.')).called(1);
    });

    testWidgets('dialog includes START VOICE SETUP WIZARD and mic suffix buttons', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Open visual dialog
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('START VOICE SETUP WIZARD'), findsOneWidget);
      expect(find.byTooltip('Speak Contact Name'), findsOneWidget);
      expect(find.byTooltip('Speak Phone Number'), findsOneWidget);
    });
  });
}
