import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeDetectorService {
  final double shakeThresholdGravity;
  final int shakeResetTimeoutMs;
  final int minTimeBetweenShakesMs;
  final int requiredShakeCount;

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  int _shakeCount = 0;
  DateTime? _firstShakeTime;
  DateTime? _lastShakeTime;
  Function()? _onThreeShakes;

  ShakeDetectorService({
    this.shakeThresholdGravity = 13.0,
    this.shakeResetTimeoutMs = 2500,
    this.minTimeBetweenShakesMs = 250,
    this.requiredShakeCount = 3,
  });

  void startListening(Function() onThreeShakes) {
    _onThreeShakes = onThreeShakes;
    _subscription?.cancel();

    _subscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        final double gX = event.x;
        final double gY = event.y;
        final double gZ = event.z;

        final double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

        if (gForce > shakeThresholdGravity) {
          final now = DateTime.now();

          // Reset count if rolling window expired
          if (_firstShakeTime != null &&
              now.difference(_firstShakeTime!).inMilliseconds > shakeResetTimeoutMs) {
            _shakeCount = 0;
            _firstShakeTime = null;
          }

          // Debounce rapid continuous sample events from single physical shake
          if (_lastShakeTime != null &&
              now.difference(_lastShakeTime!).inMilliseconds < minTimeBetweenShakesMs) {
            return;
          }

          _firstShakeTime ??= now;
          _lastShakeTime = now;
          _shakeCount++;

          if (_shakeCount >= requiredShakeCount) {
            _shakeCount = 0;
            _firstShakeTime = null;
            _onThreeShakes?.call();
          }
        }
      },
      onError: (_) {
        // Fallback gracefully on devices without userAccelerometer
      },
      cancelOnError: false,
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _shakeCount = 0;
    _firstShakeTime = null;
    _lastShakeTime = null;
  }
}
