import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'command_router.dart';

class VoiceService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  
  bool _isSpeaking = false;
  bool _isListening = false;
  Completer<void>? _ttsCompleter;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;
  bool get isWakeWordListening => false;

  VoiceService() {
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
      notifyListeners();
    });

    _tts.setErrorHandler((dynamic msg) {
      _isSpeaking = false;
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
      notifyListeners();
    });
  }

  /// Speaks [text] using Flutter TTS.
  /// If [awaitCompletion] is true, waits until TTS completes speaking before returning.
  Future<void> speak(String text, {bool awaitCompletion = true}) async {
    if (_isListening) {
      await stopListening();
    }

    await _tts.stop();
    _isSpeaking = true;
    notifyListeners();

    if (awaitCompletion) {
      _ttsCompleter = Completer<void>();
      await _tts.speak(text);
      
      // Fallback timeout in case TTS completion handler is delayed
      final timeoutMs = (text.length * 80).clamp(1200, 12000);
      Timer(Duration(milliseconds: timeoutMs), () {
        if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
          _ttsCompleter!.complete();
        }
      });

      await _ttsCompleter!.future;
      _isSpeaking = false;
      notifyListeners();
    } else {
      await _tts.speak(text);
    }
  }

  /// Listens for spoken input from microphone.
  /// Automatically stops TTS, triggers haptic vibration feedback, and collects recognized speech.
  /// Single-session: releases the microphone immediately upon completion or timeout.
  Future<String?> listen({int listenDurationSeconds = 6}) async {
    if (_isSpeaking) {
      await _tts.stop();
      _isSpeaking = false;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final available = await _speech.initialize(
      onError: (val) => debugPrint('STT Error: $val'),
      onStatus: (val) => debugPrint('STT Status: $val'),
    );

    if (!available) {
      await speak('Speech recognition is not available on this device.');
      return null;
    }

    // Trigger haptic vibration confirmation so visually impaired user knows microphone is active
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    final completer = Completer<String?>();
    String recognizedText = '';

    _isListening = true;
    notifyListeners();

    await _speech.listen(
      onResult: (event) {
        recognizedText = event.recognizedWords;
        notifyListeners();

        if (event.finalResult && !completer.isCompleted) {
          _isListening = false;
          notifyListeners();
          completer.complete(recognizedText);
        }
      },
      listenFor: Duration(seconds: listenDurationSeconds),
      pauseFor: const Duration(seconds: 2),
    );

    // Timeout fallback
    Timer(Duration(seconds: listenDurationSeconds + 1), () {
      if (!completer.isCompleted) {
        _speech.stop();
        _isListening = false;
        notifyListeners();
        completer.complete(recognizedText.trim().isNotEmpty ? recognizedText : null);
      }
    });

    final result = await completer.future;
    _isListening = false;
    notifyListeners();
    return result;
  }

  /// Dedicated fast listener for emergency SOS cancellation within a timeout (default 3s).
  /// Listens for words like 'cancel', 'stop', 'abort', 'wait', 'no'.
  /// Returns `true` if cancellation word is detected, `false` if timeout expires without cancellation.
  Future<bool> listenForCancellation({Duration duration = const Duration(seconds: 3)}) async {
    final available = await _speech.initialize(
      onError: (val) => debugPrint('Cancellation STT Error: $val'),
      onStatus: (val) => debugPrint('Cancellation STT Status: $val'),
    );

    if (!available) {
      return false;
    }

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    final completer = Completer<bool>();
    _isListening = true;
    notifyListeners();

    await _speech.listen(
      onResult: (event) {
        if (CommandRouter.isCancellationCommand(event.recognizedWords)) {
          if (!completer.isCompleted) {
            _speech.stop();
            _isListening = false;
            notifyListeners();
            completer.complete(true);
          }
        }
      },
      listenFor: duration,
      pauseFor: const Duration(seconds: 1),
    );

    Timer(duration, () {
      if (!completer.isCompleted) {
        _speech.stop();
        _isListening = false;
        notifyListeners();
        completer.complete(false);
      }
    });

    final cancelled = await completer.future;
    _isListening = false;
    notifyListeners();
    return cancelled;
  }

  /// Continuous wake-word standby is disabled to eliminate audio focus locking,
  /// recurring beeps, camera pipeline conflicts, and rapid battery drain.
  Future<void> startWakeWordListener({
    required Function(String wakeWord, String? chainedCommand) onWakeWord,
  }) async {
    // Disabled: System SpeechRecognizer cannot be safely run in an infinite loop on mobile.
  }

  /// Stops wake word listener (no-op while continuous listening is disabled).
  Future<void> stopWakeWordListener() async {
    // No-op
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _tts.stop();
      _isSpeaking = false;
      notifyListeners();
    }
  }
}
