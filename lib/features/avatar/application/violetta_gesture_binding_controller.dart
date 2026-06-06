import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:violetta_app/features/gestures/data/services/air_gesture_service.dart';
import 'package:violetta_app/features/gestures/domain/models/air_gesture_signal.dart';

/// Damped bridge between [AirGestureService] and [Violetta3DRenderEngine] inputs.
class ViolettaGestureBindingController extends ChangeNotifier {
  static const Duration dampingWindow = Duration(milliseconds: 200);
  static const Duration armResetDelay = Duration(milliseconds: 850);
  static const double swipeArmAngle = 0.5;

  ViolettaGestureBindingController({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  late final Ticker _ticker;
  StreamSubscription<AirGestureSignal>? _signalSubscription;
  Timer? _armResetTimer;

  double _targetLookAtX = 0.0;
  double _targetLookAtY = 0.0;
  double _targetLeftArmAngle = 0.0;
  double _targetRightArmAngle = 0.0;

  double _lookAtX = 0.0;
  double _lookAtY = 0.0;
  double _leftArmAngle = 0.0;
  double _rightArmAngle = 0.0;

  double get lookAtX => _lookAtX;
  double get lookAtY => _lookAtY;
  double get leftArmAngle => _leftArmAngle;
  double get rightArmAngle => _rightArmAngle;

  void attach(AirGestureService service) {
    _signalSubscription?.cancel();
    _signalSubscription = service.signalStream.listen(_handleSignal);
  }

  void detach() {
    _signalSubscription?.cancel();
    _signalSubscription = null;
  }

  void _handleSignal(AirGestureSignal signal) {
    _targetLookAtX = signal.lookAtX.clamp(-1.0, 1.0);
    _targetLookAtY = signal.lookAtY.clamp(-1.0, 1.0);

    if (signal.airSwipeUp) {
      _targetLeftArmAngle = swipeArmAngle;
      _targetRightArmAngle = swipeArmAngle;
      _scheduleArmReset();
      return;
    }

    _targetLeftArmAngle = signal.leftArmAngle.clamp(-1.85, 1.85);
    _targetRightArmAngle = signal.rightArmAngle.clamp(-1.85, 1.85);
  }

  void _scheduleArmReset() {
    _armResetTimer?.cancel();
    _armResetTimer = Timer(armResetDelay, () {
      _targetLeftArmAngle = 0.0;
      _targetRightArmAngle = 0.0;
    });
  }

  void _onTick(Duration elapsed) {
    final double step = (elapsed.inMicroseconds / dampingWindow.inMicroseconds)
        .clamp(0.0, 1.0);

    final double? nextLookAtX = lerpDouble(_lookAtX, _targetLookAtX, step);
    final double? nextLookAtY = lerpDouble(_lookAtY, _targetLookAtY, step);
    final double? nextLeftArm =
        lerpDouble(_leftArmAngle, _targetLeftArmAngle, step);
    final double? nextRightArm =
        lerpDouble(_rightArmAngle, _targetRightArmAngle, step);

    if (nextLookAtX == null ||
        nextLookAtY == null ||
        nextLeftArm == null ||
        nextRightArm == null) {
      return;
    }

    final bool changed =
        (nextLookAtX - _lookAtX).abs() >= 0.0008 ||
        (nextLookAtY - _lookAtY).abs() >= 0.0008 ||
        (nextLeftArm - _leftArmAngle).abs() >= 0.0008 ||
        (nextRightArm - _rightArmAngle).abs() >= 0.0008;

    if (!changed) {
      return;
    }

    _lookAtX = nextLookAtX;
    _lookAtY = nextLookAtY;
    _leftArmAngle = nextLeftArm;
    _rightArmAngle = nextRightArm;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _armResetTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}
