import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Single-sprite 2.5D avatar engine for Violetta full-body artwork.
///
/// Face landmarks are authored in a strict [faceRigSize] square and mapped onto
/// [imageReferenceSize] via [rigToImage] / [imageRectInRig].
class Violetta3DRenderEngine extends StatefulWidget {
  static const String bodyAsset = 'assets/violetta_bodyfull.png';
  static const Size canvasSize = Size(500, 500);
  static const Size faceRigSize = Size(500, 500);
  static const Size imageReferenceSize = Size(375, 666);

  /// Normalized look target in [-1.0, 1.0].
  final double lookAtX;
  final double lookAtY;

  /// Kept for HUD/debug API compatibility — not applied to the sprite rig.
  final double leftArmAngle;
  final double rightArmAngle;

  /// Mouth opening in [0.0, 1.0] for lipsync.
  final double mouthVolume;

  const Violetta3DRenderEngine({
    super.key,
    this.lookAtX = 0.0,
    this.lookAtY = 0.0,
    this.leftArmAngle = 0.0,
    this.rightArmAngle = 0.0,
    this.mouthVolume = 0.0,
  });

  /// Face landmarks in native sprite pixels, projected into rig space.
  static const Offset _leftEyeImage = Offset(149.0, 176.0);
  static const Offset _rightEyeImage = Offset(178.0, 179.0);
  static const Offset _mouthImage = Offset(181.0, 207.0);

  static Offset get leftEyeSocketRig => imageToRig(_leftEyeImage);
  static Offset get rightEyeSocketRig => imageToRig(_rightEyeImage);
  static Offset get gazeCenterRig => Offset(
        (leftEyeSocketRig.dx + rightEyeSocketRig.dx) * 0.5,
        (leftEyeSocketRig.dy + rightEyeSocketRig.dy) * 0.5,
      );
  static Offset get mouthCenterRig => imageToRig(_mouthImage);
  static Offset get bodyTiltPivotNorm => Offset(
        gazeCenterRig.dx / faceRigSize.width,
        gazeCenterRig.dy / faceRigSize.height,
      );

  static double get _rigContainScale => math.min(
        faceRigSize.width / imageReferenceSize.width,
        faceRigSize.height / imageReferenceSize.height,
      );

  static Offset get _rigImageOffset => Offset(
        (faceRigSize.width - imageReferenceSize.width * _rigContainScale) / 2.0,
        (faceRigSize.height - imageReferenceSize.height * _rigContainScale) / 2.0,
      );

  /// Letterboxed sprite destination inside the 500×500 rig.
  static Rect imageRectInRig() {
    final double scale = _rigContainScale;
    final double width = imageReferenceSize.width * scale;
    final double height = imageReferenceSize.height * scale;
    final Offset offset = _rigImageOffset;
    return Rect.fromLTWH(offset.dx, offset.dy, width, height);
  }

  /// Maps a rig-space landmark to native sprite pixels.
  static Offset rigToImage(Offset rigPoint) {
    final Offset offset = _rigImageOffset;
    final double scale = _rigContainScale;
    return Offset(
      (rigPoint.dx - offset.dx) / scale,
      (rigPoint.dy - offset.dy) / scale,
    );
  }

  /// Maps native sprite pixels back into the 500×500 rig box.
  static Offset imageToRig(Offset imagePoint) {
    final Offset offset = _rigImageOffset;
    final double scale = _rigContainScale;
    return Offset(
      imagePoint.dx * scale + offset.dx,
      imagePoint.dy * scale + offset.dy,
    );
  }

  /// Maps a pointer inside the strict 500×500 avatar box to normalized lookAt.
  static Offset lookAtFromAvatarPointer(Offset pointerInAvatarBox) {
    assert(
      canvasSize == faceRigSize,
      'Avatar look-at box must match the 500×500 face rig',
    );
    final Offset clampedPointer = Offset(
      pointerInAvatarBox.dx.clamp(0.0, canvasSize.width),
      pointerInAvatarBox.dy.clamp(0.0, canvasSize.height),
    );
    final Offset eyeCenterInBox = gazeCenterRig;
    final Offset delta = clampedPointer - eyeCenterInBox;
    const double maxReach = 90.0;
    return Offset(
      (delta.dx / maxReach).clamp(-1.0, 1.0),
      (delta.dy / maxReach).clamp(-1.0, 1.0),
    );
  }

  /// Image destination rect when [containerSize] uses [BoxFit.contain].
  static Rect fittedImageRect(Size containerSize) {
    final double scale = math.min(
      containerSize.width / imageReferenceSize.width,
      containerSize.height / imageReferenceSize.height,
    );
    final double width = imageReferenceSize.width * scale;
    final double height = imageReferenceSize.height * scale;
    final double left = (containerSize.width - width) / 2.0;
    final double top = (containerSize.height - height) / 2.0;
    return Rect.fromLTWH(left, top, width, height);
  }

  @override
  State<Violetta3DRenderEngine> createState() => _Violetta3DRenderEngineState();
}

class _Violetta3DRenderEngineState extends State<Violetta3DRenderEngine>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _breathCycle = Duration(milliseconds: 4200);
  static const Duration _blinkDuration = Duration(milliseconds: 120);
  static const Duration _minBlinkInterval = Duration(milliseconds: 3500);
  static const Duration _maxBlinkInterval = Duration(milliseconds: 5200);

  static const double _perspectiveEntry = 0.0016;
  static const double _maxBodyYaw = 0.14;
  static const double _maxBodyPitch = 0.08;
  static const double _breathScaleAmplitude = 0.012;
  static const double _maxPupilShiftPx = _ViolettaFaceOverlayPainter.maxPupilShiftPx;

  Offset get _leftEyeSocketRig => Violetta3DRenderEngine.leftEyeSocketRig;
  Offset get _rightEyeSocketRig => Violetta3DRenderEngine.rightEyeSocketRig;
  Offset get _mouthCenterRig => Violetta3DRenderEngine.mouthCenterRig;
  Offset get _bodyTiltPivotNorm => Violetta3DRenderEngine.bodyTiltPivotNorm;

  late final AnimationController _breathController;
  late final AnimationController _blinkController;
  late final math.Random _random;

  Timer? _blinkScheduleTimer;
  bool _isRenderActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _random = math.Random();

    _breathController = AnimationController(
      vsync: this,
      duration: _breathCycle,
    )..repeat();

    _blinkController = AnimationController(
      vsync: this,
      duration: _blinkDuration,
    );

    _blinkController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        _blinkController.reverse();
      } else if (status == AnimationStatus.dismissed && mounted) {
        _scheduleNextBlink();
      }
    });

    _scheduleNextBlink();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool shouldRender = state == AppLifecycleState.resumed;
    if (_isRenderActive == shouldRender || !mounted) {
      return;
    }
    setState(() {
      _isRenderActive = shouldRender;
    });
    if (shouldRender) {
      if (!_breathController.isAnimating) {
        _breathController.repeat();
      }
      _scheduleNextBlink();
    } else {
      _breathController.stop();
      _blinkScheduleTimer?.cancel();
    }
  }

  void _scheduleNextBlink() {
    if (!_isRenderActive || !mounted) {
      return;
    }
    _blinkScheduleTimer?.cancel();
    final int spanMs =
        _maxBlinkInterval.inMilliseconds - _minBlinkInterval.inMilliseconds;
    final int delayMs =
        _minBlinkInterval.inMilliseconds + _random.nextInt(spanMs + 1);
    _blinkScheduleTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || !_isRenderActive) {
        return;
      }
      _blinkController.forward(from: 0.0);
    });
  }

  double _clampLook(double value) => value.clamp(-1.0, 1.0);

  Offset _clampPupilShift(double lookAtX, double lookAtY) {
    final Offset raw = Offset(
      lookAtX * _maxPupilShiftPx,
      lookAtY * _maxPupilShiftPx,
    );
    final double distance = raw.distance;
    if (distance <= _maxPupilShiftPx) {
      return raw;
    }
    return Offset.fromDirection(raw.direction, _maxPupilShiftPx);
  }

  Alignment _pivotAlignment(Offset normalized) {
    return Alignment(
      normalized.dx * 2.0 - 1.0,
      normalized.dy * 2.0 - 1.0,
    );
  }

  Matrix4 _buildBodyTiltMatrix({
    required double lookAtX,
    required double lookAtY,
  }) {
    return Matrix4.identity()
      ..setEntry(3, 2, _perspectiveEntry)
      ..rotateY(lookAtX * _maxBodyYaw)
      ..rotateX(-lookAtY * _maxBodyPitch);
  }

  double _resolveBlinkClosure(double controllerValue) {
    if (controllerValue <= 0.5) {
      return Curves.easeIn.transform(controllerValue / 0.5) * 0.62;
    }
    return lerpDouble(
      0.62,
      1.0,
      Curves.easeOut.transform((controllerValue - 0.5) / 0.5),
    )!;
  }

  double _breathScale(double phase) {
    final double angle = phase * math.pi * 2.0;
    final double wave = math.sin(angle) * 0.72 + math.sin(angle * 0.47) * 0.2;
    return 1.0 + wave * _breathScaleAmplitude;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blinkScheduleTimer?.cancel();
    _breathController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRenderActive) {
      return const SizedBox(
        width: 500,
        height: 500,
      );
    }

    final double lookAtX = _clampLook(widget.lookAtX);
    final double lookAtY = _clampLook(widget.lookAtY);
    final double mouthVolume = widget.mouthVolume.clamp(0.0, 1.0);
    final Offset pupilShift = _clampPupilShift(lookAtX, lookAtY);
    final Rect imageRect = Violetta3DRenderEngine.imageRectInRig();

    return RepaintBoundary(
      child: SizedBox(
        width: Violetta3DRenderEngine.canvasSize.width,
        height: Violetta3DRenderEngine.canvasSize.height,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _breathController,
            _blinkController,
          ]),
          builder: (BuildContext context, Widget? child) {
            final double blinkClosure =
                _resolveBlinkClosure(_blinkController.value);
            final double breathScale = _breathScale(_breathController.value);

            return FittedBox(
              fit: BoxFit.contain,
              child: Transform.scale(
                scaleY: breathScale,
                alignment: _pivotAlignment(_bodyTiltPivotNorm),
                child: Transform(
                  alignment: _pivotAlignment(_bodyTiltPivotNorm),
                  transform: _buildBodyTiltMatrix(
                    lookAtX: lookAtX,
                    lookAtY: lookAtY,
                  ),
                  child: SizedBox(
                    width: Violetta3DRenderEngine.faceRigSize.width,
                    height: Violetta3DRenderEngine.faceRigSize.height,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: imageRect,
                          child: Image.asset(
                            Violetta3DRenderEngine.bodyAsset,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            errorBuilder: (
                              BuildContext context,
                              Object error,
                              StackTrace? stackTrace,
                            ) {
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text(
                                    'violetta_bodyfull.png',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        CustomPaint(
                          size: Violetta3DRenderEngine.faceRigSize,
                          painter: _ViolettaFaceOverlayPainter(
                            leftEyeSocket: _leftEyeSocketRig,
                            rightEyeSocket: _rightEyeSocketRig,
                            mouthCenter: _mouthCenterRig,
                            pupilShift: pupilShift,
                            blinkClosure: blinkClosure,
                            mouthVolume: mouthVolume,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ViolettaFaceOverlayPainter extends CustomPainter {
  static const double pupilRadius = 1.8;
  static const double pupilHighlightRadius = 0.75;
  static const double maxPupilShiftPx = 2.0;
  static const double blinkEyeWidth = 8.5;
  static const double blinkEyeHeight = 5.0;
  static const double mouthClosedWidth = 13.0;
  static const double mouthOpenWidth = 18.0;
  static const double mouthOpenDepth = 7.0;
  static const double innerMouthMaxWidth = 10.0;
  static const double innerMouthMaxDepth = 5.0;

  final Offset leftEyeSocket;
  final Offset rightEyeSocket;
  final Offset mouthCenter;
  final Offset pupilShift;
  final double blinkClosure;
  final double mouthVolume;

  const _ViolettaFaceOverlayPainter({
    required this.leftEyeSocket,
    required this.rightEyeSocket,
    required this.mouthCenter,
    required this.pupilShift,
    required this.blinkClosure,
    required this.mouthVolume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintMouth(canvas);
    if (blinkClosure < 0.42) {
      _paintPupils(canvas);
    }
    if (blinkClosure > 0.04) {
      _paintBlinkLids(canvas);
    }
  }

  void _paintPupils(Canvas canvas) {
    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF1A0E08)
      ..style = PaintingStyle.fill;
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    final Offset leftPupil = leftEyeSocket + pupilShift;
    final Offset rightPupil = rightEyeSocket + pupilShift;

    canvas.drawCircle(leftPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(rightPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(leftPupil, pupilHighlightRadius, highlightPaint);
    canvas.drawCircle(rightPupil, pupilHighlightRadius, highlightPaint);
  }

  void _paintBlinkLids(Canvas canvas) {
    const Color lidColor = Color(0xFFC89472);
    final Paint lidPaint = Paint()
      ..color = lidColor
      ..style = PaintingStyle.fill;

    for (final Offset socket in <Offset>[leftEyeSocket, rightEyeSocket]) {
      final Rect eyeBox = Rect.fromCenter(
        center: socket,
        width: blinkEyeWidth,
        height: blinkEyeHeight,
      );

      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          eyeBox.inflate(0.4),
          Radius.circular(eyeBox.height * 0.85),
        ),
      );

      final double upperDrop = eyeBox.height * 0.9 * blinkClosure;
      if (upperDrop > 0.2) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              eyeBox.left - 0.8,
              eyeBox.top - 0.4,
              eyeBox.right + 0.8,
              eyeBox.top + upperDrop,
            ),
            Radius.elliptical(eyeBox.width * 0.32, eyeBox.height * 0.28),
          ),
          lidPaint,
        );
      }

      if (blinkClosure > 0.58) {
        final double lowerRise =
            eyeBox.height * 0.65 * ((blinkClosure - 0.58) / 0.42).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              eyeBox.left - 0.8,
              eyeBox.bottom - lowerRise,
              eyeBox.right + 0.8,
              eyeBox.bottom + 0.4,
            ),
            Radius.elliptical(eyeBox.width * 0.32, eyeBox.height * 0.28),
          ),
          lidPaint,
        );
      }

      canvas.restore();
    }
  }

  void _paintMouth(Canvas canvas) {
    final Path mouthPath = _buildMouthPath(mouthVolume);
    final Paint lipLine = Paint()
      ..color = const Color(0xFF2A1018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    if (mouthVolume <= 0.06) {
      canvas.drawPath(mouthPath, lipLine);
      return;
    }

    final Paint lipFill = Paint()
      ..color = const Color(0xFF6A3048)
      ..style = PaintingStyle.fill;

    canvas.drawPath(mouthPath, lipFill);
    canvas.drawPath(mouthPath, lipLine);

    if (mouthVolume > 0.08) {
      final Paint innerMouth = Paint()
        ..color = const Color(0xFF120812).withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_buildInnerMouthPath(mouthVolume), innerMouth);
    }
  }

  Path _buildMouthPath(double volume) {
    final Offset center = mouthCenter;
    final double width = lerpDouble(mouthClosedWidth, mouthOpenWidth, volume)!;
    final double openDepth = lerpDouble(0.5, mouthOpenDepth, volume)!;
    final double lipY = center.dy;

    if (volume <= 0.06) {
      return Path()
        ..moveTo(center.dx - width * 0.5, lipY)
        ..quadraticBezierTo(
          center.dx,
          lipY + 0.9,
          center.dx + width * 0.5,
          lipY,
        );
    }

    final Path path = Path();
    path.moveTo(center.dx - width * 0.5, lipY);
    path.quadraticBezierTo(
      center.dx - width * 0.12,
      lipY - 0.35,
      center.dx,
      lipY - 0.2,
    );
    path.quadraticBezierTo(
      center.dx + width * 0.12,
      lipY - 0.35,
      center.dx + width * 0.5,
      lipY,
    );
    path.quadraticBezierTo(
      center.dx + width * 0.18,
      lipY + openDepth * 0.55,
      center.dx,
      lipY + openDepth,
    );
    path.quadraticBezierTo(
      center.dx - width * 0.18,
      lipY + openDepth * 0.55,
      center.dx - width * 0.5,
      lipY,
    );
    path.close();
    return path;
  }

  Path _buildInnerMouthPath(double volume) {
    final Offset center = mouthCenter + Offset(0.0, 0.8 * volume);
    final double depth = innerMouthMaxDepth * volume;
    final double width = innerMouthMaxWidth * volume;
    return Path()
      ..addOval(
        Rect.fromCenter(
          center: center,
          width: width,
          height: depth,
        ),
      );
  }

  @override
  bool shouldRepaint(covariant _ViolettaFaceOverlayPainter oldDelegate) {
    return oldDelegate.pupilShift != pupilShift ||
        oldDelegate.blinkClosure != blinkClosure ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
