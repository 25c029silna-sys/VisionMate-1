import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  bool _isSpeaking = false;
  bool _isListening = false;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  VoiceService() {
    _tts.setSpeechRate(0.4);
    _tts.setPitch(1.0);
    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
    });
  }

  Future<void> speak(String text) async {
    if (_speech.isListening) {
      await _speech.stop();
      _isListening = false;
    }
    _isSpeaking = true;
    await _tts.speak(text);
    // Wait until TTS completes speaking
    await Future.delayed(Duration(milliseconds: (text.length * 75).clamp(1000, 10000)));
    _isSpeaking = false;
  }

  Future<String?> listen({int listenDurationSeconds = 5}) async {
    final available = await _speech.initialize();
    if (!available) {
      await speak('Speech recognition is not available.');
      return null;
    }
    final completer = Completer<String?>();
    String recognizedText = '';

    _isListening = true;
    await _speech.listen(
      onResult: (event) {
        recognizedText = event.recognizedWords;
        if (event.finalResult && !completer.isCompleted) {
          _isListening = false;
          completer.complete(recognizedText);
        }
      },
      listenFor: Duration(seconds: listenDurationSeconds),
      pauseFor: const Duration(seconds: 2),
    );

    // Timeout safety
    Timer(Duration(seconds: listenDurationSeconds + 1), () {
      if (!completer.isCompleted) {
        _speech.stop();
        _isListening = false;
        completer.complete(recognizedText.isNotEmpty ? recognizedText : null);
      }
    });

    return completer.future;
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }
}


