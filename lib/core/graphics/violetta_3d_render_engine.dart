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
                      Positioned.fill(
                        child: CustomPaint(
                          size: Violetta3DRenderEngine.canvasSize,
                          painter: _ViolettaFaceOverlayPainter(
                            lookAtX: lookAtX,
                            lookAtY: lookAtY,
                            blinkClosure: blinkClosure,
                            mouthVolume: mouthVolume,
                          ),
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
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    // 1. Жесткий расчет Bounding Box картинки 375x666 внутри холста (BoxFit.contain)
    const double imageWidth = 375.0;
    const double imageHeight = 666.0;
    const double imageAspectRatio = imageWidth / imageHeight;
    final double canvasAspectRatio = size.width / size.height;

    final double drawWidth;
    final double drawHeight;
    final double offsetX;
    final double offsetY;

    if (canvasAspectRatio > imageAspectRatio) {
      drawHeight = size.height;
      drawWidth = drawHeight * imageAspectRatio;
      offsetX = (size.width - drawWidth) / 2.0;
      offsetY = 0.0;
    } else {
      drawWidth = size.width;
      drawHeight = drawWidth / imageAspectRatio;
      offsetX = 0.0;
      offsetY = (size.height - drawHeight) / 2.0;
    }

    // Глобальный коэффициент масштабирования элементов лица
    final double scale = drawHeight / imageHeight;

    // 2. Истинные нормализованные координаты landmarks из попиксельного анализа PNG
    const double leftEyeNormX = 148.96 / 375.0;
    const double leftEyeNormY = 175.45 / 666.0;

    const double rightEyeNormX = 177.58 / 375.0;
    const double rightEyeNormY = 178.87 / 666.0;

    const double mouthNormX = 181.46 / 375.0;
    const double mouthNormY = 206.38 / 666.0;

    // 3. Вычисление финальных точек на экране
    final double leftEyeX = offsetX + (leftEyeNormX * drawWidth);
    final double leftEyeY = offsetY + (leftEyeNormY * drawHeight);

    final double rightEyeX = offsetX + (rightEyeNormX * drawWidth);
    final double rightEyeY = offsetY + (rightEyeNormY * drawHeight);

    final double mouthX = offsetX + (mouthNormX * drawWidth);
    final double mouthY = offsetY + (mouthNormY * drawHeight);

    // 4. Отрисовка ГЛАЗ (многослойная, аккуратного аниме-масштаба)
    final Paint eyeBasePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF3D2A1C)
      ..style = PaintingStyle.fill;
    final Paint skinPaint = Paint()
      ..color = const Color(0xFFC89472)
      ..style = PaintingStyle.fill;

    final double eyeRadiusX = 11.0 * scale;
    final double eyeRadiusY = 7.0 * scale;
    final double pupilRadius = 4.0 * scale;

    final Offset leftEyeCenter = Offset(leftEyeX, leftEyeY);
    final Offset rightEyeCenter = Offset(rightEyeX, rightEyeY);

    canvas.drawOval(
      Rect.fromCenter(
        center: leftEyeCenter,
        width: eyeRadiusX * 2,
        height: eyeRadiusY * 2,
      ),
      eyeBasePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: rightEyeCenter,
        width: eyeRadiusX * 2,
        height: eyeRadiusY * 2,
      ),
      eyeBasePaint,
    );

    final Offset leftPupil = _clampPupilToEye(
      leftEyeCenter,
      Offset(leftEyeX + lookAtX * 3.0 * scale, leftEyeY + lookAtY * 2.0 * scale),
      eyeRadiusX * 0.45,
      eyeRadiusY * 0.35,
    );
    final Offset rightPupil = _clampPupilToEye(
      rightEyeCenter,
      Offset(
        rightEyeX + lookAtX * 3.0 * scale,
        rightEyeY + lookAtY * 2.0 * scale,
      ),
      eyeRadiusX * 0.45,
      eyeRadiusY * 0.35,
    );

    canvas.drawCircle(leftPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(rightPupil, pupilRadius, pupilPaint);

    // 5. Анимация МОРГАНИЯ (веко закрывает глаз сверху вниз)
    if (blinkClosure > 0.0) {
      final double lidHeight = eyeRadiusY * 2 * blinkClosure;
      canvas.drawRect(
        Rect.fromLTWH(
          leftEyeX - eyeRadiusX,
          leftEyeY - eyeRadiusY,
          eyeRadiusX * 2,
          lidHeight,
        ),
        skinPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          rightEyeX - eyeRadiusX,
          rightEyeY - eyeRadiusY,
          eyeRadiusX * 2,
          lidHeight,
        ),
        skinPaint,
      );
    }

    // 6. Отрисовка РТА (аккуратная линия строго на губах текстуры)
    final Paint mouthPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round;

    final double mouthWidth = 14.0 * scale;
    final double mouthOpenHeight = 8.0 * scale * mouthVolume;

    if (mouthVolume < 0.1) {
      canvas.drawLine(
        Offset(mouthX - mouthWidth / 2, mouthY),
        Offset(mouthX + mouthWidth / 2, mouthY),
        mouthPaint,
      );
    } else {
      final Path mouthPath = Path()
        ..moveTo(mouthX - mouthWidth / 2, mouthY)
        ..quadraticBezierTo(
          mouthX,
          mouthY + mouthOpenHeight,
          mouthX + mouthWidth / 2,
          mouthY,
        );
      canvas.drawPath(mouthPath, mouthPaint);
    }

    // 7. Debug-точки (HUD визуальный контроль)
    final Paint debugPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(leftEyeCenter, 2.0, debugPaint);
    canvas.drawCircle(rightEyeCenter, 2.0, debugPaint);
    canvas.drawCircle(Offset(mouthX, mouthY), 2.0, debugPaint);
  }

  Offset _clampPupilToEye(
    Offset eyeCenter,
    Offset target,
    double maxShiftX,
    double maxShiftY,
  ) {
    final double dx = (target.dx - eyeCenter.dx).clamp(-maxShiftX, maxShiftX);
    final double dy = (target.dy - eyeCenter.dy).clamp(-maxShiftY, maxShiftY);
    return Offset(eyeCenter.dx + dx, eyeCenter.dy + dy);
  }

  @override
  bool shouldRepaint(covariant _ViolettaFaceOverlayPainter oldDelegate) {
    return oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtY != lookAtY ||
        oldDelegate.blinkClosure != blinkClosure ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
