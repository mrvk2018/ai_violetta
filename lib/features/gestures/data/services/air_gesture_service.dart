import 'dart:async';

import 'package:camera/camera.dart';
import 'package:violetta_app/features/gestures/domain/models/air_gesture_signal.dart';

class AirGestureService {
  AirGestureService() : _signalController = StreamController<AirGestureSignal>.broadcast();

  final StreamController<AirGestureSignal> _signalController;

  DateTime _lastGestureTime = DateTime.now();
  double _previousLuminance = -1.0;
  double _previousUpperLuminance = -1.0;
  double _previousLowerLuminance = -1.0;

  /// Reactive broadcast of normalized avatar gesture targets.
  Stream<AirGestureSignal> get signalStream => _signalController.stream;

  /// Backward-compatible swipe detector.
  bool detectAirSwipe(CameraImage image) => processFrame(image).airSwipeUp;

  /// Analyzes a camera frame, emits [AirGestureSignal], and returns the signal.
  AirGestureSignal processFrame(CameraImage image) {
    final AirGestureSignal signal = _analyzeFrame(image);
    if (!_signalController.isClosed) {
      _signalController.add(signal);
    }
    return signal;
  }

  AirGestureSignal _analyzeFrame(CameraImage image) {
    final List<int> bytes = image.planes.first.bytes;
    if (bytes.isEmpty) {
      return const AirGestureSignal();
    }

    final int width = image.width;
    final int height = image.height;
    if (width <= 0 || height <= 0) {
      return const AirGestureSignal();
    }

    double leftSum = 0;
    double rightSum = 0;
    double upperSum = 0;
    double lowerSum = 0;
    int leftCount = 0;
    int rightCount = 0;
    int upperCount = 0;
    int lowerCount = 0;

    final int stepX = (width ~/ 24).clamp(1, width);
    final int stepY = (height ~/ 24).clamp(1, height);

    for (int y = 0; y < height; y += stepY) {
      for (int x = 0; x < width; x += stepX) {
        final int index = (y * width) + x;
        if (index >= bytes.length) {
          continue;
        }

        final double sample = bytes[index].toDouble();
        if (x < width ~/ 2) {
          leftSum += sample;
          leftCount++;
        } else {
          rightSum += sample;
          rightCount++;
        }

        if (y < height ~/ 2) {
          upperSum += sample;
          upperCount++;
        } else {
          lowerSum += sample;
          lowerCount++;
        }
      }
    }

    if (leftCount == 0 || rightCount == 0 || upperCount == 0 || lowerCount == 0) {
      return const AirGestureSignal();
    }

    final double leftAvg = leftSum / leftCount;
    final double rightAvg = rightSum / rightCount;
    final double upperAvg = upperSum / upperCount;
    final double lowerAvg = lowerSum / lowerCount;
    final double globalAvg = (leftSum + rightSum) / (leftCount + rightCount);

    final double lookAtX = ((rightAvg - leftAvg) / 64.0).clamp(-1.0, 1.0);
    final double lookAtY = ((lowerAvg - upperAvg) / 72.0).clamp(-1.0, 1.0);

    double leftArmAngle = 0.0;
    double rightArmAngle = 0.0;
    bool airSwipeUp = false;

    if (_previousUpperLuminance > 0 && _previousLowerLuminance > 0) {
      final double upperDelta = upperAvg - _previousUpperLuminance;
      final double lowerDelta = lowerAvg - _previousLowerLuminance;
      final double proximityLift = ((upperDelta - lowerDelta) / 90.0).clamp(0.0, 0.5);
      leftArmAngle = proximityLift;
      rightArmAngle = proximityLift;
    }

    if (_previousLuminance > 0) {
      final DateTime now = DateTime.now();
      final double globalDelta = (globalAvg - _previousLuminance).abs();
      final double upperDelta = upperAvg - _previousUpperLuminance;
      final bool cooldownElapsed =
          now.difference(_lastGestureTime).inMilliseconds >= 1000;

      if (cooldownElapsed &&
          globalDelta > 35.0 &&
          upperDelta > 15.0 &&
          upperDelta > (lowerAvg - _previousLowerLuminance)) {
        airSwipeUp = true;
        leftArmAngle = 0.5;
        rightArmAngle = 0.5;
        _lastGestureTime = now;
      }
    }

    _previousLuminance = globalAvg;
    _previousUpperLuminance = upperAvg;
    _previousLowerLuminance = lowerAvg;

    return AirGestureSignal(
      lookAtX: lookAtX,
      lookAtY: lookAtY,
      leftArmAngle: leftArmAngle,
      rightArmAngle: rightArmAngle,
      airSwipeUp: airSwipeUp,
    );
  }

  void dispose() {
    _signalController.close();
  }
}
