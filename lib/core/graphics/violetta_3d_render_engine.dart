import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Single-sprite 2.5D avatar engine for [bodyAsset] (`375×666` PNG).
///
/// Face overlay geometry is authored in PNG-normalized space and scaled by the
/// rendered sprite rect (`scale = imageRect.height / imageReferenceSize.height`).
class Violetta3DRenderEngine extends StatefulWidget {
  static const String bodyAsset = 'assets/violetta_bodyfull.png';
  static const Size canvasSize = Size(500, 500);
  static const Size imageReferenceSize = Size(375, 666);

  /// Normalized landmarks from PNG pixel analysis (origin top-left).
  static const Offset leftEyeNorm = Offset(0.3972, 0.2634);
  static const Offset rightEyeNorm = Offset(0.4736, 0.2686);
  static const Offset mouthNorm = Offset(0.4839, 0.3099);

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

  static Offset get gazeCenterNorm => Offset(
        (leftEyeNorm.dx + rightEyeNorm.dx) * 0.5,
        (leftEyeNorm.dy + rightEyeNorm.dy) * 0.5,
      );

  static Offset get bodyTiltPivotNorm => gazeCenterNorm;

  static double layoutScale(Size layoutSize) => imageRectInLayout(layoutSize).height /
      imageReferenceSize.height;

  static Rect imageRectInLayout(Size layoutSize) {
    final double scale = math.min(
      layoutSize.width / imageReferenceSize.width,
      layoutSize.height / imageReferenceSize.height,
    );
    final double width = imageReferenceSize.width * scale;
    final double height = imageReferenceSize.height * scale;
    final double left = (layoutSize.width - width) / 2.0;
    final double top = (layoutSize.height - height) / 2.0;
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Sprite destination rect inside [canvasSize].
  static Rect imageRectInRig() => imageRectInLayout(canvasSize);

  /// Maps normalized PNG coordinates to canvas coordinates.
  static Offset landmarkOnCanvas(Offset normalized, Rect imageRect) {
    return Offset(
      imageRect.left + normalized.dx * imageRect.width,
      imageRect.top + normalized.dy * imageRect.height,
    );
  }

  static Offset get leftEyeCanvas => landmarkOnCanvas(leftEyeNorm, imageRectInRig());
  static Offset get rightEyeCanvas => landmarkOnCanvas(rightEyeNorm, imageRectInRig());
  static Offset get gazeCenterCanvas => landmarkOnCanvas(gazeCenterNorm, imageRectInRig());
  static Offset get mouthCenterCanvas => landmarkOnCanvas(mouthNorm, imageRectInRig());

  /// Maps a pointer inside the avatar box to normalized lookAt.
  static Offset lookAtFromAvatarPointer(Offset pointerInAvatarBox) {
    final Rect imageRect = imageRectInRig();
    final Offset clampedPointer = Offset(
      pointerInAvatarBox.dx.clamp(0.0, canvasSize.width),
      pointerInAvatarBox.dy.clamp(0.0, canvasSize.height),
    );
    final Offset eyeCenter = gazeCenterCanvas;
    final double scale = imageRect.height / imageReferenceSize.height;
    final double maxReach = 90.0 * scale;
    final Offset delta = clampedPointer - eyeCenter;
    return Offset(
      (delta.dx / maxReach).clamp(-1.0, 1.0),
      (delta.dy / maxReach).clamp(-1.0, 1.0),
    );
  }

  /// Image destination rect when [containerSize] uses [BoxFit.contain].
  static Rect fittedImageRect(Size containerSize) =>
      imageRectInLayout(containerSize);

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

  Offset _clampPupilShift(double lookAtX, double lookAtY, double maxShiftPx) {
    final Offset raw = Offset(
      lookAtX * maxShiftPx,
      lookAtY * maxShiftPx,
    );
    final double distance = raw.distance;
    if (distance <= maxShiftPx) {
      return raw;
    }
    return Offset.fromDirection(raw.direction, maxShiftPx);
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
      return SizedBox(
        width: Violetta3DRenderEngine.canvasSize.width,
        height: Violetta3DRenderEngine.canvasSize.height,
      );
    }

    final double lookAtX = _clampLook(widget.lookAtX);
    final double lookAtY = _clampLook(widget.lookAtY);
    final double mouthVolume = widget.mouthVolume.clamp(0.0, 1.0);
    final Rect imageRect = Violetta3DRenderEngine.imageRectInRig();
    final double scale =
        imageRect.height / Violetta3DRenderEngine.imageReferenceSize.height;
    final Offset pupilShift = _clampPupilShift(
      lookAtX,
      lookAtY,
      _ViolettaFaceOverlayPainter.basePupilShiftPx * scale,
    );

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
                alignment: _pivotAlignment(
                  Violetta3DRenderEngine.bodyTiltPivotNorm,
                ),
                child: Transform(
                  alignment: _pivotAlignment(
                    Violetta3DRenderEngine.bodyTiltPivotNorm,
                  ),
                  transform: _buildBodyTiltMatrix(
                    lookAtX: lookAtX,
                    lookAtY: lookAtY,
                  ),
                  child: SizedBox(
                    width: Violetta3DRenderEngine.canvasSize.width,
                    height: Violetta3DRenderEngine.canvasSize.height,
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
                          size: Violetta3DRenderEngine.canvasSize,
                          painter: _ViolettaFaceOverlayPainter(
                            scale: scale,
                            leftEyeCenter: Violetta3DRenderEngine.leftEyeCanvas,
                            rightEyeCenter:
                                Violetta3DRenderEngine.rightEyeCanvas,
                            mouthCenter:
                                Violetta3DRenderEngine.mouthCenterCanvas,
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

/// Face overlay scaled from PNG reference space (`375×666`).
class _ViolettaFaceOverlayPainter extends CustomPainter {
  /// Base sizes in PNG pixel space before [scale] is applied.
  static const double baseScleraWidth = 22.0;
  static const double baseScleraHeight = 14.0;
  static const double baseIrisRadius = 5.5;
  static const double basePupilRadius = 2.8;
  static const double baseHighlightRadius = 1.1;
  static const double basePupilShiftPx = 4.0;
  static const double baseMouthWidth = 26.0;
  static const double baseMouthOpenWidth = 32.0;
  static const double baseMouthOpenDepth = 10.0;
  static const double baseInnerMouthWidth = 16.0;
  static const double baseInnerMouthDepth = 7.0;
  static const double baseLipStrokeWidth = 1.2;

  final double scale;
  final Offset leftEyeCenter;
  final Offset rightEyeCenter;
  final Offset mouthCenter;
  final Offset pupilShift;
  final double blinkClosure;
  final double mouthVolume;

  const _ViolettaFaceOverlayPainter({
    required this.scale,
    required this.leftEyeCenter,
    required this.rightEyeCenter,
    required this.mouthCenter,
    required this.pupilShift,
    required this.blinkClosure,
    required this.mouthVolume,
  });

  double get _scleraWidth => baseScleraWidth * scale;
  double get _scleraHeight => baseScleraHeight * scale;
  double get _irisRadius => baseIrisRadius * scale;
  double get _pupilRadius => basePupilRadius * scale;
  double get _highlightRadius => baseHighlightRadius * scale;
  double get _mouthWidth =>
      lerpDouble(baseMouthWidth, baseMouthOpenWidth, mouthVolume)! * scale;
  double get _mouthDepth => baseMouthOpenDepth * mouthVolume * scale;
  double get _lipStrokeWidth => baseLipStrokeWidth * scale;

  @override
  void paint(Canvas canvas, Size size) {
    _paintMouth(canvas);
    _paintEyeStack(canvas, leftEyeCenter);
    _paintEyeStack(canvas, rightEyeCenter);
  }

  void _paintEyeStack(Canvas canvas, Offset center) {
    final Rect scleraRect = Rect.fromCenter(
      center: center,
      width: _scleraWidth,
      height: _scleraHeight,
    );

    final Paint scleraPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawOval(scleraRect, scleraPaint);

    final Paint irisPaint = Paint()
      ..color = const Color(0xFF5A3828)
      ..style = PaintingStyle.fill;
    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF120818)
      ..style = PaintingStyle.fill;
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    final Offset irisCenter = center + pupilShift;
    canvas.drawCircle(irisCenter, _irisRadius, irisPaint);
    canvas.drawCircle(irisCenter, _pupilRadius, pupilPaint);
    canvas.drawCircle(
      irisCenter + Offset(-0.9 * scale, -0.75 * scale),
      _highlightRadius,
      highlightPaint,
    );

    if (blinkClosure > 0.02) {
      _paintFilledEyelid(canvas, scleraRect);
    }
  }

  void _paintFilledEyelid(Canvas canvas, Rect eyeRect) {
    const Color lidColor = Color(0xFFC89472);
    final Paint lidPaint = Paint()
      ..color = lidColor
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(eyeRect.inflate(0.6 * scale)),
    );

    final double upperDrop = eyeRect.height * 0.95 * blinkClosure;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          eyeRect.left - scale,
          eyeRect.top - scale,
          eyeRect.right + scale,
          eyeRect.top + upperDrop,
        ),
        Radius.elliptical(eyeRect.width * 0.28, eyeRect.height * 0.22),
      ),
      lidPaint,
    );

    if (blinkClosure > 0.55) {
      final double lowerRise =
          eyeRect.height * 0.75 * ((blinkClosure - 0.55) / 0.45).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            eyeRect.left - scale,
            eyeRect.bottom - lowerRise,
            eyeRect.right + scale,
            eyeRect.bottom + scale,
          ),
          Radius.elliptical(eyeRect.width * 0.28, eyeRect.height * 0.22),
        ),
        lidPaint,
      );
    }

    canvas.restore();
  }

  void _paintMouth(Canvas canvas) {
    final Path mouthPath = _buildMouthPath();
    final Paint lipLine = Paint()
      ..color = const Color(0xFF2A1018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lipStrokeWidth
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
      canvas.drawPath(_buildInnerMouthPath(), innerMouth);
    }
  }

  Path _buildMouthPath() {
    final Offset center = mouthCenter;
    final double width = _mouthWidth;
    final double openDepth = _mouthDepth;
    final double lipY = center.dy;

    if (mouthVolume <= 0.06) {
      return Path()
        ..moveTo(center.dx - width * 0.5, lipY)
        ..quadraticBezierTo(
          center.dx,
          lipY + 0.35 * scale,
          center.dx + width * 0.5,
          lipY,
        );
    }

    final Path path = Path();
    path.moveTo(center.dx - width * 0.5, lipY);
    path.quadraticBezierTo(
      center.dx - width * 0.1,
      lipY - 0.25 * scale,
      center.dx,
      lipY - 0.12 * scale,
    );
    path.quadraticBezierTo(
      center.dx + width * 0.1,
      lipY - 0.25 * scale,
      center.dx + width * 0.5,
      lipY,
    );
    path.quadraticBezierTo(
      center.dx + width * 0.16,
      lipY + openDepth * 0.55,
      center.dx,
      lipY + openDepth,
    );
    path.quadraticBezierTo(
      center.dx - width * 0.16,
      lipY + openDepth * 0.55,
      center.dx - width * 0.5,
      lipY,
    );
    path.close();
    return path;
  }

  Path _buildInnerMouthPath() {
    final Offset center = mouthCenter + Offset(0.0, 0.6 * scale * mouthVolume);
    final double depth = baseInnerMouthDepth * mouthVolume * scale;
    final double width = baseInnerMouthWidth * mouthVolume * scale;
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
    return oldDelegate.scale != scale ||
        oldDelegate.leftEyeCenter != leftEyeCenter ||
        oldDelegate.rightEyeCenter != rightEyeCenter ||
        oldDelegate.mouthCenter != mouthCenter ||
        oldDelegate.pupilShift != pupilShift ||
        oldDelegate.blinkClosure != blinkClosure ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
