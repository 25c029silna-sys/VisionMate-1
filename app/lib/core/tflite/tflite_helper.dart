import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteHelper {
  Interpreter? _interpreter;
  bool _isModelAvailable = false;

  bool get isModelAvailable => _isModelAvailable;

  Future<Interpreter?> loadModel(String assetPath) async {
    try {
      _interpreter ??= await Interpreter.fromAsset(assetPath);
      _isModelAvailable = true;
      return _interpreter;
    } catch (e, stackTrace) {
      _isModelAvailable = false;
      debugPrint('TfliteHelper error: Failed to load TFLite model from asset "$assetPath": $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelAvailable = false;
  }
}

