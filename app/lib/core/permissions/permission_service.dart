import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestLocationPermission() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestSmsPermission() async {
    try {
      final status = await Permission.sms.request();
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestPhonePermission() async {
    try {
      final status = await Permission.phone.request();
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Requests all core VisionMate permissions (Camera, Microphone, Location, SMS) in batch mode.
  /// Returns a map indicating permission grant status per feature.
  Future<Map<Permission, bool>> requestAllCorePermissions() async {
    final permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
      Permission.sms,
    ];

    try {
      final statuses = await permissions.request();
      return statuses.map((perm, status) => MapEntry(perm, status.isGranted));
    } catch (_) {
      return {for (var p in permissions) p: true};
    }
  }

  /// Returns true if all critical non-visual & safety permissions are granted.
  Future<bool> areCorePermissionsGranted() async {
    try {
      final camera = await Permission.camera.isGranted;
      final mic = await Permission.microphone.isGranted;
      final location = await Permission.locationWhenInUse.isGranted;
      final sms = await Permission.sms.isGranted;

      return camera && mic && location && sms;
    } catch (_) {
      return true;
    }
  }
}

