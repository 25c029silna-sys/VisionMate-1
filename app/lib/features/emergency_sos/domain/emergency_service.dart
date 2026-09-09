import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/permissions/permission_service.dart';

class EmergencyService {
  final MethodChannel _channel;
  final PermissionService _permissionService;

  EmergencyService({MethodChannel? channel, PermissionService? permissionService})
      : _channel = channel ?? const MethodChannel('com.visionmate.app/sms'),
        _permissionService = permissionService ?? PermissionService();

  Future<Position> fetchLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    return Geolocator.getCurrentPosition();
  }

  /// Sends an emergency SMS alert to [phoneNumber] with retry capability.
  /// Requests runtime SEND_SMS permission prior to native dispatch.
  Future<void> sendSos(String phoneNumber, String message) async {
    final hasPermission = await _permissionService.requestSmsPermission();
    if (!hasPermission) {
      throw Exception('SMS permission (android.permission.SEND_SMS) was denied. Please grant SMS permission in device Settings.');
    }

    int attempts = 0;
    const maxAttempts = 2;
    Object? lastError;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        await _channel.invokeMethod('sendSms', {
          'phoneNumber': phoneNumber,
          'message': message,
        });
        return; // Success via native platform channel
      } catch (e) {
        lastError = e;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    throw Exception('SMS transmission failed after $maxAttempts attempts: $lastError');
  }

  /// Initiates a direct phone call to [phoneNumber] via native platform channel.
  Future<void> makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    await _permissionService.requestPhonePermission();
    try {
      await _channel.invokeMethod('makeCall', {
        'phoneNumber': phoneNumber,
      });
    } catch (e) {
      throw Exception('Could not place phone call: $e');
    }
  }

  String composeMessage(Position position) {
    return 'Emergency alert: I need help. My location is https://maps.google.com/?q=${position.latitude},${position.longitude} (${position.latitude}, ${position.longitude}).';
  }

  /// Triggers full emergency workflow globally with a 3-second cancellation window via voice input.
  Future<bool> executeGlobalSos({
    required dynamic storageService,
    required dynamic voiceService,
    Duration cancellationWindow = const Duration(seconds: 3),
  }) async {
    final contact = await storageService.getTrustedContact();
    final String phone = contact['phone'] ?? '';
    final String name = contact['name'] ?? 'Trusted Contact';

    if (phone.isEmpty) {
      await voiceService.speak(
        'Emergency SOS triggered by shake gesture, but no trusted contact is saved. Please configure a contact in Emergency SOS.',
      );
      return false;
    }

    // 1. Announce SOS activation with 3-second voice cancellation prompt
    await voiceService.speak(
      'Emergency SOS activated by shake gesture. Say CANCEL within 3 seconds to cancel.',
      awaitCompletion: true,
    );

    // 2. Listen for voice cancellation ('cancel', 'stop', 'abort', 'wait', 'no')
    final wasCancelled = await voiceService.listenForCancellation(duration: cancellationWindow);
    if (wasCancelled) {
      await voiceService.speak('Emergency SOS cancelled. No alert was sent.');
      return false;
    }

    // 3. If not cancelled within 3 seconds, proceed with dispatch
    await voiceService.speak('Sending emergency alert to $name.');

    try {
      final position = await fetchLocation();
      final message = composeMessage(position);
      await sendSos(phone, message);
      await voiceService.speak('Emergency SMS sent. Calling $name.');
      await makePhoneCall(phone);
      return true;
    } catch (e) {
      await voiceService.speak('Emergency alert encountered an issue. Placing phone call directly.');
      await makePhoneCall(phone);
      return true;
    }
  }
}




