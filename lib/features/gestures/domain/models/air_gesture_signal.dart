/// Normalized skeletal + look-at targets derived from front-camera flux analysis.
class AirGestureSignal {
  final double lookAtX;
  final double lookAtY;
  final double leftArmAngle;
  final double rightArmAngle;
  final bool airSwipeUp;

  const AirGestureSignal({
    this.lookAtX = 0.0,
    this.lookAtY = 0.0,
    this.leftArmAngle = 0.0,
    this.rightArmAngle = 0.0,
    this.airSwipeUp = false,
  });
}
