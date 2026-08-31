import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteHelper {
  Interpreter? _interpreter;
  bool _isModelAvailable = false;

  bool get isModelAvailable => _isModelAvailable;
  Interpreter? get interpreter => _interpreter;

  Future<Interpreter?> loadModel(String assetPath) async {
    if (_interpreter != null) return _interpreter;

    try {
      // Validate asset existence and byte signature before loading in C++ runtime
      final byteData = await rootBundle.load(assetPath);
      if (byteData.lengthInBytes < 1024) {
        debugPrint('TfliteHelper: Asset "$assetPath" is too small (${byteData.lengthInBytes} bytes) to be a valid TFLite model file.');
        _isModelAvailable = false;
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      // Check TFL3 magic bytes at offset 4: [0x54, 0x46, 0x4C, 0x33]
      if (bytes.length >= 8) {
        final isTfliteMagic = bytes[4] == 0x54 && bytes[5] == 0x46 && bytes[6] == 0x4C && bytes[7] == 0x33;
        if (!isTfliteMagic) {
          debugPrint('TfliteHelper: Asset "$assetPath" does not contain valid TFLite FlatBuffer header (TFL3). Skipping native C++ load.');
          _isModelAvailable = false;
          return null;
        }
      }

      try {
        _interpreter = Interpreter.fromBuffer(bytes);
      } catch (e) {
        debugPrint('TfliteHelper: Interpreter.fromBuffer failed, trying Interpreter.fromAsset: $e');
        _interpreter = await Interpreter.fromAsset(assetPath);
      }
      _isModelAvailable = _interpreter != null;
      return _interpreter;
    } catch (e, stackTrace) {
      _isModelAvailable = false;
      debugPrint('TfliteHelper error: Failed to load TFLite model from asset "$assetPath": $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelAvailable = false;
  }
}

