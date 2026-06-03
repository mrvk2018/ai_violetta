import 'package:camera/camera.dart';

class AirGestureService {
  DateTime _lastGestureTime = DateTime.now();
  double _previousLuminance = -1.0;

  bool detectAirSwipe(CameraImage image) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastGestureTime).inMilliseconds < 1000) {
      return false;
    }

    final List<int> bytes = image.planes.first.bytes;
    if (bytes.isEmpty) {
      return false;
    }

    int totalLuminance = 0;
    final int step = bytes.length ~/ 100;
    final int stride = step < 1 ? 1 : step;
    int sampleCount = 0;

    for (int i = 0; i < bytes.length; i += stride) {
      totalLuminance += bytes[i];
      sampleCount++;
    }

    if (sampleCount == 0) {
      return false;
    }

    final double currentLuminance = totalLuminance / sampleCount;

    if (_previousLuminance > 0) {
      final double delta = (currentLuminance - _previousLuminance).abs();
      if (delta > 35.0) {
        _lastGestureTime = now;
        _previousLuminance = currentLuminance;
        return true;
      }
    }

    _previousLuminance = currentLuminance;
    return false;
  }
}
