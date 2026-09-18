import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';
import 'package:visionmate/features/emergency_sos/presentation/emergency_screen.dart';
import 'package:visionmate/features/scene_navigation/presentation/scene_screen.dart';

class _FakeStorageService extends StorageService {
  final Map<String, String> _contact = {
    'name': 'Alex Emergency',
    'phone': '+15559876543',
  };

  @override
  Future<Map<String, String>> getTrustedContact() async => _contact;
}

class _MockVoiceService extends VoiceService {
  final List<String> spokenMessages = [];
  bool shouldCancel = false;

  @override
  Future<void> speak(String text, {bool awaitCompletion = true}) async {
    spokenMessages.add(text);
  }

  @override
  Future<bool> listenForCancellation({Duration duration = const Duration(seconds: 8)}) async {
    return shouldCancel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Voice and UI Enhancements Suite', () {
    // =========================================================================
    // 1. EMERGENCY SOS 3-SECOND VOICE CANCELLATION TESTS
    // =========================================================================
    group('1. Emergency SOS 3-Second Voice Cancellation', () {
      late List<MethodCall> methodCalls;
      late EmergencyService emergencyService;

      setUp(() {
        methodCalls = <MethodCall>[];
        const channel = MethodChannel('com.visionmate.app/sms');
        const ttsChannel = MethodChannel('flutter_tts');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'sendSms') return true;
          if (call.method == 'makeCall') return true;
          return null;
        });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ttsChannel, (MethodCall call) async => 1);

        emergencyService = EmergencyService(channel: channel);
      });

      tearDown(() {
        const channel = MethodChannel('com.visionmate.app/sms');
        const ttsChannel = MethodChannel('flutter_tts');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ttsChannel, null);
      });

      test('executeGlobalSos aborts SMS dispatch when voice cancellation is detected within 3s', () async {
        final mockVoice = _MockVoiceService()..shouldCancel = true;
        final fakeStorage = _FakeStorageService();

        final dispatched = await emergencyService.executeGlobalSos(
          storageService: fakeStorage,
          voiceService: mockVoice,
          cancellationWindow: const Duration(milliseconds: 100),
        );

        expect(dispatched, isFalse);
        expect(methodCalls, isEmpty); // No SMS or call dispatched
        expect(mockVoice.spokenMessages.any((m) => m.contains('cancelled')), isTrue);
      });

      test('executeGlobalSos dispatches alert when no cancellation occurs within 3s', () async {
        final mockVoice = _MockVoiceService()..shouldCancel = false;
        final fakeStorage = _FakeStorageService();

        // Mock geolocator location
        const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(locationChannel, (MethodCall call) async {
          if (call.method == 'checkPermission') return 3; // LocationPermission.always
          if (call.method == 'requestPermission') return 3;
          if (call.method == 'getCurrentPosition') {
            return {
              'latitude': 37.7749,
              'longitude': -122.4194,
              'timestamp': 1000,
              'altitude': 0.0,
              'accuracy': 5.0,
              'heading': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
            };
          }
          return null;
        });

        final dispatched = await emergencyService.executeGlobalSos(
          storageService: fakeStorage,
          voiceService: mockVoice,
          cancellationWindow: const Duration(milliseconds: 50),
        );

        expect(dispatched, isTrue);
        expect(methodCalls.any((c) => c.method == 'sendSms'), isTrue);
      });

      test('CommandRouter detects all cancellation keywords correctly', () {
        expect(CommandRouter.isCancellationCommand('cancel'), isTrue);
        expect(CommandRouter.isCancellationCommand('stop please'), isTrue);
        expect(CommandRouter.isCancellationCommand('abort sos'), isTrue);
        expect(CommandRouter.isCancellationCommand('wait wait'), isTrue);
        expect(CommandRouter.isCancellationCommand('no false alarm'), isTrue);
        expect(CommandRouter.isCancellationCommand('help me now'), isFalse);
      });
    });

    // =========================================================================
    // 2. GLOBAL WAKE WORD "VISIONMATE" DETECTION & COMMAND ROUTING
    // =========================================================================
    group('2. Global "VisionMate" Wake Word & Routing', () {
      test('CommandRouter detects wake word phrases', () {
        expect(CommandRouter.containsWakeWord('visionmate open braille'), isTrue);
        expect(CommandRouter.containsWakeWord('hey vision mate describe scene'), isTrue);
        expect(CommandRouter.containsWakeWord('ok visionmate sos'), isTrue);
        expect(CommandRouter.containsWakeWord('just read text'), isFalse);
      });

      test('CommandRouter extracts command after wake word', () {
        expect(
          CommandRouter.extractCommandAfterWakeWord('visionmate open braille'),
          equals('braille'),
        );
        expect(
          CommandRouter.extractCommandAfterWakeWord('hey vision mate scan text'),
          equals('scan text'),
        );
        expect(
          CommandRouter.extractCommandAfterWakeWord('visionmate'),
          isEmpty,
        );
      });

      test('CommandRouter routes commands prefixed with wake words directly to modules', () {
        expect(CommandRouter.routeCommand('visionmate braille'), equals('/braille'));
        expect(CommandRouter.routeCommand('hey vision mate describe scene'), equals('/scene'));
        expect(CommandRouter.routeCommand('ok visionmate emergency help'), equals('/emergency'));
        expect(CommandRouter.routeCommand('visionmate read document'), equals('/ocr'));
        expect(CommandRouter.routeCommand('visionmate search library'), equals('/library'));
      });
    });

    // =========================================================================
    // 3. SCENE DESCRIPTION BOX RENDERING VERIFICATION
    // =========================================================================
    group('3. Scene Description Box Layout & Text Rendering', () {
      Widget wrap(Widget child) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<VoiceService>(create: (_) => VoiceService()),
            Provider<CommandRouter>(create: (_) => CommandRouter()),
            Provider<StorageService>(create: (_) => _FakeStorageService()),
          ],
          child: MaterialApp(home: child),
        );
      }

      testWidgets('SceneScreen renders SCENE DESCRIPTION card and description text visibly', (tester) async {
        await tester.pumpWidget(wrap(const SceneScreen()));
        await tester.pump(const Duration(milliseconds: 200));

        // Verify Header and Label
        expect(find.text('SCENE DESCRIPTION'), findsOneWidget);
        expect(find.text('READY'), findsOneWidget);
        expect(find.text('Describe Surroundings'), findsOneWidget);
        expect(find.text('VOICE COMMAND'), findsOneWidget);

        // Verify initial instruction text is present and visible
        expect(
          find.text('Point camera at your surroundings and tap Describe Surroundings or say Describe.'),
          findsOneWidget,
        );
      });

      testWidgets('EmergencyScreen renders cancellation countdown UI on trigger', (tester) async {
        await tester.pumpWidget(wrap(const EmergencyScreen()));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.textContaining('TRIGGER EMERGENCY SOS'), findsOneWidget);
        expect(find.textContaining('8s Cancel'), findsOneWidget);
      });

      testWidgets('EmergencyScreen renders cleanly without RenderFlex overflow on constrained screen sizes', (tester) async {
        tester.view.physicalSize = const Size(360, 560);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(wrap(const EmergencyScreen()));
        await tester.pump(const Duration(milliseconds: 200));

        // Expect no Flutter error / RenderFlex overflow in idle state
        expect(tester.takeException(), isNull);
        final triggerFinder = find.textContaining('TRIGGER EMERGENCY SOS');
        expect(triggerFinder, findsOneWidget);

        // Scroll to and tap trigger to enter countdown state
        await tester.ensureVisible(triggerFinder);
        await tester.tap(triggerFinder);
        await tester.pump(const Duration(milliseconds: 200));

        // Expect countdown banner without any RenderFlex overflow
        expect(tester.takeException(), isNull);
        expect(find.textContaining('CANCELLATION WINDOW'), findsOneWidget);
      });
    });
  });
}
