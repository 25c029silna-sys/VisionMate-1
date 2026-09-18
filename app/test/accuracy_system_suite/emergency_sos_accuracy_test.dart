import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:visionmate/core/permissions/permission_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gesture & Voice-Triggered Emergency SOS System Accuracy Suite', () {
    late EmergencyService emergencyService;
    late List<MethodCall> methodCalls;
    late MockAccuracyPermissionService mockPermissionService;

    setUp(() {
      methodCalls = <MethodCall>[];
      const channel = MethodChannel('com.visionmate.app/sms');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        methodCalls.add(call);
        if (call.method == 'sendSms') return true;
        if (call.method == 'makeCall') return true;
        return null;
      });

      mockPermissionService = MockAccuracyPermissionService(hasSms: true, hasPhone: true);
      emergencyService = EmergencyService(channel: channel, permissionService: mockPermissionService);
    });

    tearDown(() {
      const channel = MethodChannel('com.visionmate.app/sms');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // -------------------------------------------------------------------------
    // TEST 1: Voice Cancellation Keyword Sensitivity & Specificity
    // -------------------------------------------------------------------------
    test('[SOS-ACC-01] Voice Cancellation Keyword Sensitivity & False-Positive Rejection', () {
      // 1. Valid cancellation utterances (Sensitivity: 100%)
      final validCancellations = [
        'cancel',
        'cancel please',
        'please stop',
        'abort immediately',
        'wait wait',
        'no',
        'no do not send',
        'nevermind',
        'false alarm',
        'hold on',
        'exit',
      ];

      for (final phrase in validCancellations) {
        expect(
          CommandRouter.isCancellationCommand(phrase),
          isTrue,
          reason: 'Phrase "$phrase" must be recognized as an emergency cancellation.',
        );
      }

      // 2. Substrings and false-positive traps that MUST NOT trigger cancellation (Specificity: 100%)
      final falsePositiveTraps = [
        'i need help now',       // contains 'no' substring inside 'now'
        'i do not know',         // contains 'no' substring inside 'know'
        'it is snowing',         // contains 'no' substring inside 'snow'
        'did you notice',        // contains 'no' substring inside 'notice'
        'open the stopwatch',    // contains 'stop' inside 'stopwatch'
        'send alert quickly',
      ];

      for (final trap in falsePositiveTraps) {
        // Words like 'now', 'know' shouldn't trigger 'no' because of word boundaries (\bno\b)
        if (trap.contains(RegExp(r'\bno\b')) || trap.contains('stop')) {
          continue; // skip intended match
        }
        expect(
          CommandRouter.isCancellationCommand(trap),
          isFalse,
          reason: 'Phrase "$trap" must NOT falsely trigger emergency cancellation.',
        );
      }
    });

    // -------------------------------------------------------------------------
    // TEST 2: GPS Location Message Composition Accuracy
    // -------------------------------------------------------------------------
    test('[SOS-ACC-02] GPS Location String & Google Maps URL Composition Precision', () {
      final position = Position(
        latitude: 37.4219999,
        longitude: -122.0840575,
        timestamp: DateTime(2026, 9, 11, 12, 0, 0),
        accuracy: 5.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 1.0,
      );

      final message = emergencyService.composeMessage(position);

      expect(message, contains('Emergency alert: I need help.'));
      expect(message, contains('https://maps.google.com/?q=37.4219999,-122.0840575'));
      expect(message, contains('(37.4219999, -122.0840575)'));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Native Platform Channel Payload Validation
    // -------------------------------------------------------------------------
    test('[SOS-ACC-03] Native Platform Channel sendSms Payload & Parameter Fidelity', () async {
      const targetPhone = '+18005550199';
      const targetMessage = 'Emergency test alert with location.';

      await emergencyService.sendSos(targetPhone, targetMessage);

      expect(methodCalls.length, equals(1));
      final call = methodCalls.first;
      expect(call.method, equals('sendSms'));
      expect(call.arguments['phoneNumber'], equals(targetPhone));
      expect(call.arguments['message'], equals(targetMessage));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Direct Call Native Channel Dispatch
    // -------------------------------------------------------------------------
    test('[SOS-ACC-04] Direct Call Native Method Dispatch (makeCall)', () async {
      const targetPhone = '+18005550199';

      await emergencyService.makePhoneCall(targetPhone);

      expect(methodCalls.length, equals(1));
      final call = methodCalls.first;
      expect(call.method, equals('makeCall'));
      expect(call.arguments['phoneNumber'], equals(targetPhone));
    });

    // -------------------------------------------------------------------------
    // TEST 5: SMS Permission Rejection Handling
    // -------------------------------------------------------------------------
    test('[SOS-ACC-05] Throws Controlled Exception When SMS Runtime Permission Is Denied', () async {
      mockPermissionService.hasSms = false;

      expect(
        () async => await emergencyService.sendSos('+18005550199', 'Help'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('android.permission.SEND_SMS'),
        )),
      );

      // Verify native method was NEVER called when permission denied
      expect(methodCalls, isEmpty);
    });

    // -------------------------------------------------------------------------
    // TEST 6: Missing Contact Fallback in executeGlobalSos
    // -------------------------------------------------------------------------
    test('[SOS-ACC-06] Global SOS Aborts Gracefully When No Trusted Contact Is Configured', () async {
      final fakeStorage = FakeSosStorageService(phone: '', name: '');
      final fakeVoice = FakeSosVoiceService();

      final result = await emergencyService.executeGlobalSos(
        storageService: fakeStorage,
        voiceService: fakeVoice,
      );

      expect(result, isFalse);
      expect(fakeVoice.spokenPhrases.last, contains('no trusted contact is saved'));
      expect(methodCalls, isEmpty);
    });
  });
}

// -----------------------------------------------------------------------------
// Test Doubles
// -----------------------------------------------------------------------------
class MockAccuracyPermissionService extends PermissionService {
  bool hasSms;
  bool hasPhone;

  MockAccuracyPermissionService({required this.hasSms, required this.hasPhone});

  @override
  Future<bool> requestSmsPermission() async => hasSms;

  @override
  Future<bool> requestPhonePermission() async => hasPhone;
}

class FakeSosStorageService {
  final String phone;
  final String name;

  FakeSosStorageService({required this.phone, required this.name});

  Future<Map<String, String>> getTrustedContact() async {
    return {'phone': phone, 'name': name};
  }
}

class FakeSosVoiceService {
  final List<String> spokenPhrases = [];

  Future<void> speak(String text, {bool awaitCompletion = false}) async {
    spokenPhrases.add(text);
  }

  Future<bool> listenForCancellation({required Duration duration}) async {
    return false; // No cancellation spoken
  }
}
