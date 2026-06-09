import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Single-sprite 2.5D avatar engine for Violetta full-body artwork.
///
/// Renders one PNG layer with vector pupils/mouth overlays anchored to
/// anatomical landmarks on [imageReferenceSize].
class Violetta3DRenderEngine extends StatefulWidget {
  static const String bodyAsset = 'assets/violetta_bodyfull.png';
  static const Size canvasSize = Size(400, 400);
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

  /// Symmetric rig landmarks on the 375×666 sprite (X axis locked to 168.5).
  static const Offset leftEyeSocket = Offset(146.0, 176.0);
  static const Offset rightEyeSocket = Offset(191.0, 176.0);
  static const Offset gazeCenter = Offset(168.5, 176.0);
  static const Offset mouthCenter = Offset(168.5, 202.0);
  static const Offset bodyTiltPivotNorm = Offset(0.4493, 0.2643);

  /// Maps a pointer inside the strict 400×400 avatar box to normalized lookAt.
  static Offset lookAtFromAvatarPointer(Offset pointerInAvatarBox) {
    assert(
      canvasSize == const Size(400, 400),
      'Avatar look-at box must remain 400×400',
    );
    final Offset clampedPointer = Offset(
      pointerInAvatarBox.dx.clamp(0.0, canvasSize.width),
      pointerInAvatarBox.dy.clamp(0.0, canvasSize.height),
    );
    final Rect fitted = fittedImageRect(canvasSize);
    final double scale = fitted.height / imageReferenceSize.height;
    final Offset eyeCenterInBox = fitted.topLeft + gazeCenter * scale;
    final Offset delta = clampedPointer - eyeCenterInBox;
    const double maxReach = 72.0;
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
  static const double _maxPupilShiftPx = 4.0;

  static const Offset _leftEyeSocket = Violetta3DRenderEngine.leftEyeSocket;
  static const Offset _rightEyeSocket = Violetta3DRenderEngine.rightEyeSocket;
  static const Offset _mouthCenter = Violetta3DRenderEngine.mouthCenter;
  static const Offset _bodyTiltPivotNorm = Violetta3DRenderEngine.bodyTiltPivotNorm;

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
        width: 400,
        height: 400,
      );
    }

    final double lookAtX = _clampLook(widget.lookAtX);
    final double lookAtY = _clampLook(widget.lookAtY);
    final double mouthVolume = widget.mouthVolume.clamp(0.0, 1.0);
    final Offset pupilShift = _clampPupilShift(lookAtX, lookAtY);

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
                  width: Violetta3DRenderEngine.imageReferenceSize.width,
                  height: Violetta3DRenderEngine.imageReferenceSize.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.asset(
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
                      CustomPaint(
                        painter: _ViolettaFaceOverlayPainter(
                          leftEyeSocket: _leftEyeSocket,
                          rightEyeSocket: _rightEyeSocket,
                          mouthCenter: _mouthCenter,
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
    _paintPupils(canvas);
    if (blinkClosure > 0.001) {
      _paintBlinkLids(canvas);
    }
  }

  void _paintPupils(Canvas canvas) {
    const double pupilRadius = 3.6;
    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF1A0E08)
      ..style = PaintingStyle.fill;
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final Offset leftPupil = leftEyeSocket + pupilShift;
    final Offset rightPupil = rightEyeSocket + pupilShift;

    canvas.drawCircle(leftPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(rightPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(
      leftPupil + const Offset(-1.4, -1.2),
      1.4,
      highlightPaint,
    );
    canvas.drawCircle(
      rightPupil + const Offset(-1.4, -1.2),
      1.4,
      highlightPaint,
    );
  }

  void _paintBlinkLids(Canvas canvas) {
    const double eyeWidth = 20.0;
    const double eyeHeight = 12.0;
    const Color lidColor = Color(0xFFC89472);
    final Paint lidPaint = Paint()
      ..color = lidColor
      ..style = PaintingStyle.fill;

    for (final Offset socket in <Offset>[leftEyeSocket, rightEyeSocket]) {
      final Rect eyeBox = Rect.fromCenter(
        center: socket,
        width: eyeWidth,
        height: eyeHeight,
      );

      final double topDescent = eyeHeight * blinkClosure;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            eyeBox.left,
            eyeBox.top,
            eyeBox.right,
            eyeBox.top + topDescent,
          ),
          const Radius.circular(4),
        ),
        lidPaint,
      );

      if (blinkClosure > 0.35) {
        final double bottomAscent =
            eyeHeight * ((blinkClosure - 0.35) / 0.65).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              eyeBox.left,
              eyeBox.bottom - bottomAscent,
              eyeBox.right,
              eyeBox.bottom,
            ),
            const Radius.circular(4),
          ),
          lidPaint,
        );
      }

      if (blinkClosure > 0.92) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(eyeBox, const Radius.circular(4)),
          lidPaint,
        );
      }
    }
  }

  void _paintMouth(Canvas canvas) {
    final Path mouthPath = _buildMouthPath(mouthVolume);
    final Paint lipFill = Paint()
      ..color = const Color(0xFF6A3048)
      ..style = PaintingStyle.fill;
    final Paint lipLine = Paint()
      ..color = const Color(0xFF2A1018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

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
    final double openHeight = lerpDouble(2.0, 16.0, volume)!;
    final double width = lerpDouble(18.0, 24.0, volume)!;

    final Path path = Path();
    path.moveTo(center.dx - width * 0.5, center.dy - openHeight * 0.1);
    path.quadraticBezierTo(
      center.dx,
      center.dy - openHeight * 0.55,
      center.dx + width * 0.5,
      center.dy - openHeight * 0.1,
    );
    path.quadraticBezierTo(
      center.dx,
      center.dy + openHeight * 0.65,
      center.dx - width * 0.5,
      center.dy - openHeight * 0.1,
    );
    path.close();
    return path;
  }

  Path _buildInnerMouthPath(double volume) {
    final Offset center = mouthCenter + const Offset(0, 1.5);
    final double openHeight = lerpDouble(0.0, 9.0, volume)!;
    final double width = lerpDouble(0.0, 14.0, volume)!;
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: width,
            height: openHeight,
          ),
          Radius.circular(openHeight * 0.45),
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
