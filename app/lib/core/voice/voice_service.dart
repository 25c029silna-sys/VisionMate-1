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
  Completer<String?>? _activeListenCompleter;
  Timer? _activeListenTimer;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;
  bool get isWakeWordListening => false;

  VoiceService() {
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _tts.awaitSpeakCompletion(true);

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
  /// Automatically stops TTS, allows audio hardware buffers to settle, triggers haptic
  /// vibration confirmation at mic onset, and collects recognized speech.
  /// Extended single-session stream (default 25s) with a forgiving 3s pause cutoff.
  /// Holds microphone access quietly until input is recognized or manually cancelled,
  /// eliminating audio focus thrashing and rapid retry loops.
  Future<String?> listen({
    int listenDurationSeconds = 25,
    int pauseDurationSeconds = 3,
  }) async {
    // 1. Ensure TTS playback is stopped and audio hardware buffers have fully settled
    await _tts.stop();
    _isSpeaking = false;
    // Acoustic & hardware settling buffer: prevents microphone from capturing speaker tail-end
    await Future.delayed(const Duration(milliseconds: 450));

    // Cancel any previous listening timer/session
    _activeListenTimer?.cancel();
    if (_activeListenCompleter != null && !_activeListenCompleter!.isCompleted) {
      _activeListenCompleter!.complete(null);
    }

    final completer = Completer<String?>();
    _activeListenCompleter = completer;
    String recognizedText = '';

    final available = await _speech.initialize(
      onError: (val) {
        debugPrint('STT Error: $val');
        if (!completer.isCompleted) {
          _activeListenTimer?.cancel();
          _isListening = false;
          notifyListeners();
          completer.complete(recognizedText.trim().isNotEmpty ? recognizedText.trim() : null);
        }
      },
      onStatus: (status) {
        debugPrint('STT Status: $status');
        // When speech recognition engine stops listening on silence or completion
        if ((status == 'notListening' || status == 'done') && !completer.isCompleted) {
          _activeListenTimer?.cancel();
          _isListening = false;
          notifyListeners();
          completer.complete(recognizedText.trim().isNotEmpty ? recognizedText.trim() : null);
        }
      },
    );

    if (!available) {
      await speak('Speech recognition is not available on this device.');
      return null;
    }

    // Trigger haptic vibration confirmation at the exact moment recording begins
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    _isListening = true;
    notifyListeners();

    await _speech.listen(
      onResult: (event) {
        recognizedText = event.recognizedWords;
        notifyListeners();

        // Complete immediately if final result is reached with non-empty content
        if (event.finalResult && recognizedText.trim().isNotEmpty && !completer.isCompleted) {
          _activeListenTimer?.cancel();
          _isListening = false;
          notifyListeners();
          completer.complete(recognizedText.trim());
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: false,
        partialResults: true,
        listenFor: Duration(seconds: listenDurationSeconds),
        pauseFor: Duration(seconds: pauseDurationSeconds),
      ),
    );

    // Timeout fallback ensuring completer finishes if speech engine pauses or ends
    _activeListenTimer = Timer(Duration(seconds: listenDurationSeconds), () {
      if (!completer.isCompleted) {
        _speech.stop();
        _isListening = false;
        notifyListeners();
        completer.complete(recognizedText.trim().isNotEmpty ? recognizedText.trim() : null);
      }
    });

    final result = await completer.future;
    _activeListenTimer?.cancel();
    _isListening = false;
    notifyListeners();
    return result;
  }

  /// Dedicated fast listener for emergency SOS cancellation within a timeout (default 8s).
  /// Listens for words like 'cancel', 'stop', 'abort', 'wait', 'no'.
  /// Returns `true` if cancellation word is detected, `false` if timeout expires without cancellation.
  Future<bool> listenForCancellation({Duration duration = const Duration(seconds: 8)}) async {
    // 1. Ensure TTS playback is stopped and audio buffers have settled
    await _tts.stop();
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
    _isSpeaking = false;

    // Clean up any existing microphone session
    if (_isListening) {
      await _speech.stop();
      _activeListenTimer?.cancel();
      _isListening = false;
    }

    // Audio routing settling buffer: allows OS to release audio focus and switch to microphone
    await Future.delayed(const Duration(milliseconds: 250));

    final available = await _speech.initialize(
      onError: (val) => debugPrint('Cancellation STT Error: $val'),
      onStatus: (val) => debugPrint('Cancellation STT Status: $val'),
    );

    if (!available) {
      debugPrint('Cancellation STT: SpeechRecognizer not available');
      return false;
    }

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    final completer = Completer<bool>();
    Timer? cancellationTimer;
    _isListening = true;
    notifyListeners();

    await _speech.listen(
      onResult: (event) {
        debugPrint('Cancellation STT recognized: "${event.recognizedWords}" (final: ${event.finalResult})');
        if (CommandRouter.isCancellationCommand(event.recognizedWords)) {
          if (!completer.isCompleted) {
            cancellationTimer?.cancel();
            _speech.stop();
            _isListening = false;
            notifyListeners();
            completer.complete(true);
          }
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        listenFor: duration,
        pauseFor: const Duration(seconds: 2),
      ),
    );

    cancellationTimer = Timer(duration, () {
      if (!completer.isCompleted) {
        _speech.stop();
        _isListening = false;
        notifyListeners();
        completer.complete(false);
      }
    });

    final cancelled = await completer.future;
    cancellationTimer.cancel();
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
    _activeListenTimer?.cancel();
    if (_activeListenCompleter != null && !_activeListenCompleter!.isCompleted) {
      _activeListenCompleter!.complete(null);
    }
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _tts.stop();
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
      _isSpeaking = false;
      notifyListeners();
    }
  }
}
