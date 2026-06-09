import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Single-sprite 2.5D avatar engine for [bodyAsset] (`375×666` PNG).
class Violetta3DRenderEngine extends StatefulWidget {
  static const String bodyAsset = 'assets/violetta_bodyfull.png';
  static const Size canvasSize = Size(500, 500);
  static const Size imageReferenceSize = Size(375, 666);
  static const double imageAspectRatio = 375 / 666;

  /// Normalized landmarks from PNG pixel analysis (origin top-left).
  static const Offset leftEyeNorm = Offset(0.3972, 0.2634);
  static const Offset rightEyeNorm = Offset(0.4736, 0.2686);
  static const Offset mouthNorm = Offset(0.4839, 0.3099);

  final double lookAtX;
  final double lookAtY;
  final double leftArmAngle;
  final double rightArmAngle;
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

  static Rect imageRectInRig() =>
      _SpriteDrawBox.fromCanvasSize(canvasSize).rect;

  static Offset lookAtFromAvatarPointer(Offset pointerInAvatarBox) {
    final _SpriteDrawBox drawBox = _SpriteDrawBox.fromCanvasSize(canvasSize);
    final Offset clampedPointer = Offset(
      pointerInAvatarBox.dx.clamp(0.0, canvasSize.width),
      pointerInAvatarBox.dy.clamp(0.0, canvasSize.height),
    );
    final Offset eyeCenter = drawBox.landmark(gazeCenterNorm);
    final double maxReach = 90.0 * drawBox.currentScale;
    final Offset delta = clampedPointer - eyeCenter;
    return Offset(
      (delta.dx / maxReach).clamp(-1.0, 1.0),
      (delta.dy / maxReach).clamp(-1.0, 1.0),
    );
  }

  static Rect fittedImageRect(Size containerSize) =>
      _SpriteDrawBox.fromCanvasSize(containerSize).rect;

  @override
  State<Violetta3DRenderEngine> createState() => _Violetta3DRenderEngineState();
}

/// BoxFit.contain layout for the sprite inside a canvas [Size].
class _SpriteDrawBox {
  final double drawWidth;
  final double drawHeight;
  final double offsetX;
  final double offsetY;

  const _SpriteDrawBox({
    required this.drawWidth,
    required this.drawHeight,
    required this.offsetX,
    required this.offsetY,
  });

  double get currentScale =>
      drawHeight / Violetta3DRenderEngine.imageReferenceSize.height;

  Rect get rect => Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);

  Offset landmark(Offset normalized) {
    return Offset(
      offsetX + normalized.dx * drawWidth,
      offsetY + normalized.dy * drawHeight,
    );
  }

  static _SpriteDrawBox fromCanvasSize(Size size) {
    final double canvasAspectRatio = size.width / size.height;

    final double drawWidth;
    final double drawHeight;
    final double offsetX;
    final double offsetY;

    if (canvasAspectRatio > Violetta3DRenderEngine.imageAspectRatio) {
      drawHeight = size.height;
      drawWidth = drawHeight * Violetta3DRenderEngine.imageAspectRatio;
      offsetX = (size.width - drawWidth) / 2.0;
      offsetY = 0.0;
    } else {
      drawWidth = size.width;
      drawHeight = drawWidth / Violetta3DRenderEngine.imageAspectRatio;
      offsetX = 0.0;
      offsetY = (size.height - drawHeight) / 2.0;
    }

    return _SpriteDrawBox(
      drawWidth: drawWidth,
      drawHeight: drawHeight,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }
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

            return Transform.scale(
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
                        painter: _ViolettaFaceOverlayPainter(
                          lookAtX: lookAtX,
                          lookAtY: lookAtY,
                          blinkClosure: blinkClosure,
                          mouthVolume: mouthVolume,
                        ),
                      ),
                    ],
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
  static const double baseScleraWidth = 22.0;
  static const double baseScleraHeight = 14.0;
  static const double basePupilRadius = 5.0;
  static const double basePupilShiftPx = 4.0;
  static const double baseMouthWidth = 24.0;
  static const double baseMouthOpenWidth = 30.0;
  static const double baseMouthOpenDepth = 9.0;
  static const double baseInnerMouthWidth = 14.0;
  static const double baseInnerMouthDepth = 6.0;
  static const double baseLipStrokeWidth = 1.2;

  final double lookAtX;
  final double lookAtY;
  final double blinkClosure;
  final double mouthVolume;

  const _ViolettaFaceOverlayPainter({
    required this.lookAtX,
    required this.lookAtY,
    required this.blinkClosure,
    required this.mouthVolume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final _SpriteDrawBox drawBox = _SpriteDrawBox.fromCanvasSize(size);
    final double currentScale = drawBox.currentScale;

    final Offset leftEyeCenter =
        drawBox.landmark(Violetta3DRenderEngine.leftEyeNorm);
    final Offset rightEyeCenter =
        drawBox.landmark(Violetta3DRenderEngine.rightEyeNorm);
    final Offset mouthCenter =
        drawBox.landmark(Violetta3DRenderEngine.mouthNorm);

    final double maxShift = basePupilShiftPx * currentScale;
    final Offset pupilShift = _clampPupilShift(lookAtX, lookAtY, maxShift);

    _paintMouth(canvas, mouthCenter, currentScale);
    _paintEyeStack(canvas, leftEyeCenter, pupilShift, currentScale);
    _paintEyeStack(canvas, rightEyeCenter, pupilShift, currentScale);
  }

  Offset _clampPupilShift(double lookAtX, double lookAtY, double maxShiftPx) {
    final Offset raw = Offset(lookAtX * maxShiftPx, lookAtY * maxShiftPx);
    if (raw.distance <= maxShiftPx) {
      return raw;
    }
    return Offset.fromDirection(raw.direction, maxShiftPx);
  }

  void _paintEyeStack(
    Canvas canvas,
    Offset center,
    Offset pupilShift,
    double currentScale,
  ) {
    final double scleraWidth = baseScleraWidth * currentScale;
    final double scleraHeight = baseScleraHeight * currentScale;
    final double pupilRadius = basePupilRadius * currentScale;

    final Rect scleraRect = Rect.fromCenter(
      center: center,
      width: scleraWidth,
      height: scleraHeight,
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
    canvas.drawCircle(irisCenter, pupilRadius, irisPaint);
    canvas.drawCircle(irisCenter, pupilRadius * 0.55, pupilPaint);
    canvas.drawCircle(
      irisCenter + Offset(-0.8 * currentScale, -0.65 * currentScale),
      pupilRadius * 0.22,
      highlightPaint,
    );

    if (blinkClosure > 0.02) {
      _paintFilledEyelid(canvas, scleraRect, currentScale);
    }
  }

  void _paintFilledEyelid(
    Canvas canvas,
    Rect eyeRect,
    double currentScale,
  ) {
    const Color lidColor = Color(0xFFC89472);
    final Paint lidPaint = Paint()
      ..color = lidColor
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(eyeRect.inflate(0.5 * currentScale)),
    );

    final double upperDrop = eyeRect.height * 0.95 * blinkClosure;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          eyeRect.left - currentScale,
          eyeRect.top - currentScale,
          eyeRect.right + currentScale,
          eyeRect.top + upperDrop,
        ),
        Radius.elliptical(eyeRect.width * 0.28, eyeRect.height * 0.22),
      ),
      lidPaint,
    );

    if (blinkClosure > 0.55) {
      final double lowerRise = eyeRect.height *
          0.75 *
          ((blinkClosure - 0.55) / 0.45).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            eyeRect.left - currentScale,
            eyeRect.bottom - lowerRise,
            eyeRect.right + currentScale,
            eyeRect.bottom + currentScale,
          ),
          Radius.elliptical(eyeRect.width * 0.28, eyeRect.height * 0.22),
        ),
        lidPaint,
      );
    }

    canvas.restore();
  }

  void _paintMouth(Canvas canvas, Offset mouthCenter, double currentScale) {
    final Path mouthPath = _buildMouthPath(mouthCenter, currentScale);
    final Paint lipLine = Paint()
      ..color = const Color(0xFF2A1018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseLipStrokeWidth * currentScale
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
      canvas.drawPath(
        _buildInnerMouthPath(mouthCenter, currentScale),
        innerMouth,
      );
    }
  }

  Path _buildMouthPath(Offset mouthCenter, double currentScale) {
    final double width = lerpDouble(
          baseMouthWidth,
          baseMouthOpenWidth,
          mouthVolume,
        )! *
        currentScale;
    final double openDepth = baseMouthOpenDepth * mouthVolume * currentScale;
    final double lipY = mouthCenter.dy;

    if (mouthVolume <= 0.06) {
      return Path()
        ..moveTo(mouthCenter.dx - width * 0.5, lipY)
        ..quadraticBezierTo(
          mouthCenter.dx,
          lipY + 0.35 * currentScale,
          mouthCenter.dx + width * 0.5,
          lipY,
        );
    }

    final Path path = Path();
    path.moveTo(mouthCenter.dx - width * 0.5, lipY);
    path.quadraticBezierTo(
      mouthCenter.dx - width * 0.1,
      lipY - 0.25 * currentScale,
      mouthCenter.dx,
      lipY - 0.12 * currentScale,
    );
    path.quadraticBezierTo(
      mouthCenter.dx + width * 0.1,
      lipY - 0.25 * currentScale,
      mouthCenter.dx + width * 0.5,
      lipY,
    );
    path.quadraticBezierTo(
      mouthCenter.dx + width * 0.16,
      lipY + openDepth * 0.55,
      mouthCenter.dx,
      lipY + openDepth,
    );
    path.quadraticBezierTo(
      mouthCenter.dx - width * 0.16,
      lipY + openDepth * 0.55,
      mouthCenter.dx - width * 0.5,
      lipY,
    );
    path.close();
    return path;
  }

  Path _buildInnerMouthPath(Offset mouthCenter, double currentScale) {
    final Offset center =
        mouthCenter + Offset(0.0, 0.6 * currentScale * mouthVolume);
    final double depth = baseInnerMouthDepth * mouthVolume * currentScale;
    final double width = baseInnerMouthWidth * mouthVolume * currentScale;
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
    return oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtY != lookAtY ||
        oldDelegate.blinkClosure != blinkClosure ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
