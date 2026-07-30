import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Initializes camera service with preferred back camera.
  Future<bool> initCamera({ResolutionPreset resolution = ResolutionPreset.high}) async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('CameraService: No cameras available on device.');
        return false;
      }

      final backCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        backCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      return true;
    } catch (e, stack) {
      debugPrint('CameraService init error: $e');
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }

  /// Captures a high-resolution photo file.
  Future<XFile?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint('CameraService: Camera is not initialized.');
      return null;
    }

    try {
      if (_controller!.value.isTakingPicture) {
        return null;
      }
      final XFile photo = await _controller!.takePicture();
      return photo;
    } catch (e) {
      debugPrint('CameraService takePicture error: $e');
      return null;
    }
  }

  /// Toggles flash mode (Torch / Off).
  Future<void> toggleFlash(bool enable) async {
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller!.setFlashMode(enable ? FlashMode.torch : FlashMode.off);
    }
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

