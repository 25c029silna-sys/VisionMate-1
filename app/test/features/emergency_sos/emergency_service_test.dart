import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmergencyService MethodChannel & SOS Alert Tests', () {
    late EmergencyService emergencyService;
    late List<MethodCall> log;

    setUp(() {
      log = <MethodCall>[];
      const channel = MethodChannel('com.visionmate.app/sms');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'sendSms') {
          return true;
        }
        return null;
      });

      emergencyService = EmergencyService(channel: channel);
    });

    tearDown(() {
      const channel = MethodChannel('com.visionmate.app/sms');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('sendSos invokes com.visionmate.app/sms method channel with sendSms', () async {
      const phone = '+15551234567';
      const message = 'Emergency alert: I need help. My location is 37.7749, -122.4194.';

      await emergencyService.sendSos(phone, message);

      expect(log, hasLength(1));
      expect(log.first.method, equals('sendSms'));
      expect(log.first.arguments, equals({
        'phoneNumber': phone,
        'message': message,
      }));
    });
  });
}
