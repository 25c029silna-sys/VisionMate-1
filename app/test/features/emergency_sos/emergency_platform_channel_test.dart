import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';
import 'package:visionmate/core/permissions/permission_service.dart';

class MockPermissionService extends PermissionService {
  final bool mockSms;
  final bool mockPhone;

  MockPermissionService({this.mockSms = true, this.mockPhone = true});

  @override
  Future<bool> requestSmsPermission() async => mockSms;

  @override
  Future<bool> requestPhonePermission() async => mockPhone;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmergencyService Platform Channel Tests', () {
    const channel = MethodChannel('com.visionmate.app/sms');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'sendSms') {
            return true;
          } else if (methodCall.method == 'makeCall') {
            return true;
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('sendSos invokes native sendSms method with correct parameters', () async {
      final emergencyService = EmergencyService(
        channel: channel,
        permissionService: MockPermissionService(mockSms: true),
      );

      await emergencyService.sendSos('+1234567890', 'Test SOS Message');

      expect(log, hasLength(1));
      expect(log.first.method, equals('sendSms'));
      expect(log.first.arguments, equals({
        'phoneNumber': '+1234567890',
        'message': 'Test SOS Message',
      }));
    });

    test('sendSos throws exception when SMS permission is denied', () async {
      final emergencyService = EmergencyService(
        channel: channel,
        permissionService: MockPermissionService(mockSms: false),
      );

      expect(
        () => emergencyService.sendSos('+1234567890', 'Test SOS Message'),
        throwsA(isA<Exception>()),
      );
      expect(log, isEmpty);
    });

    test('makePhoneCall invokes native makeCall method with correct parameters', () async {
      final emergencyService = EmergencyService(
        channel: channel,
        permissionService: MockPermissionService(mockPhone: true),
      );

      await emergencyService.makePhoneCall('+1234567890');

      expect(log, hasLength(1));
      expect(log.first.method, equals('makeCall'));
      expect(log.first.arguments, equals({
        'phoneNumber': '+1234567890',
      }));
    });
  });
}
