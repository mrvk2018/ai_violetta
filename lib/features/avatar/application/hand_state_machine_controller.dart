import 'dart:async';

import 'package:flutter/foundation.dart';

enum HandPose {
  up,
  down,
}

class HandStateMachineController extends ChangeNotifier {
  static const Duration handDownDelay = Duration(seconds: 5);

  HandPose _pose = HandPose.up;
  Timer? _handDownTimer;

  HandPose get pose => _pose;
  bool get isHandDown => _pose == HandPose.down;
  double get handUpOpacity => _pose == HandPose.up ? 1.0 : 0.0;
  double get handDownOpacity => _pose == HandPose.down ? 1.0 : 0.0;

  void setHandUp() {
    _handDownTimer?.cancel();
    _setPose(HandPose.up);
  }

  void setHandDown({Duration delay = handDownDelay}) {
    _handDownTimer?.cancel();
    _handDownTimer = Timer(delay, () {
      _setPose(HandPose.down);
    });
  }

  void toggleHandPose() {
    if (_pose == HandPose.up) {
      setHandDown();
      return;
    }
    setHandUp();
  }

  void _setPose(HandPose nextPose) {
    if (_pose == nextPose) {
      return;
    }
    _pose = nextPose;
    notifyListeners();
  }

  @override
  void dispose() {
    _handDownTimer?.cancel();
    super.dispose();
  }
}
