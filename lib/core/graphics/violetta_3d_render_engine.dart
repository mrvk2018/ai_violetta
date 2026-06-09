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
                            blinkProgress: blinkClosure,
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
  final double blinkProgress;
  final double mouthVolume;

  const _ViolettaFaceOverlayPainter({
    required this.lookAtX,
    required this.lookAtY,
    required this.blinkProgress,
    required this.mouthVolume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Абсолютные, выверенные вручную координаты центров лица (Origin: top-left холста 696x512)
    // Эти точки идеально попадают в зрачки и губы аватара по центру экрана
    final double leftEyeX = 264.5;
    final double leftEyeY = 281.5;

    final double rightEyeX = 282.5;
    final double rightEyeY = 282.5;

    final double mouthX = 274.0;
    final double mouthY = 296.0;

    // 2. Жёстко зафиксированный, аккуратный масштаб элементов (без гигантских овалов)
    final double eyeRadiusX = 7.5;  // Изящная ширина белка
    final double eyeRadiusY = 5.0;  // Изящная высота белка
    final double pupilRadius = 3.0; // Размер зрачка
    final double mouthWidth = 10.0; // Компактная ширина линии губ

    // Конфигурация кистей для отрисовки слоёв
    final Paint eyeBasePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final Paint pupilPaint = Paint()..color = const Color(0xFF3D2A1C)..style = PaintingStyle.fill; // Тёмно-коричневый
    final Paint skinPaint = Paint()..color = const Color(0xFFC89472)..style = PaintingStyle.fill; // Телесный для век

    // 3. Отрисовка слоёв ЛЕВОГО ГЛАЗА
    canvas.drawOval(Rect.fromCenter(center: Offset(leftEyeX, leftEyeY), width: eyeRadiusX * 2, height: eyeRadiusY * 2), eyeBasePaint);
    // Движение зрачка ( lookAtX / lookAtY ограничиваем в пределах ±2 пикселя)
    double dynamicLeftX = leftEyeX + (lookAtX * 2.0);
    double dynamicLeftY = leftEyeY + (lookAtY * 1.5);
    canvas.drawCircle(Offset(dynamicLeftX, dynamicLeftY), pupilRadius, pupilPaint);

    // 4. Отрисовка слоёв ПРАВОГО ГЛАЗА
    canvas.drawOval(Rect.fromCenter(center: Offset(rightEyeX, rightEyeY), width: eyeRadiusX * 2, height: eyeRadiusY * 2), eyeBasePaint);
    double dynamicRightX = rightEyeX + (lookAtX * 2.0);
    double dynamicRightY = rightEyeY + (lookAtY * 1.5);
    canvas.drawCircle(Offset(dynamicRightX, dynamicRightY), pupilRadius, pupilPaint);

    // 5. Анимация МОРГАНИЯ (Телесная заливка сверху вниз по границам глазницы)
    if (blinkProgress > 0.0) {
      double vHeight = eyeRadiusY * 2 * blinkProgress;
      canvas.drawRect(Rect.fromLTWH(leftEyeX - eyeRadiusX, leftEyeY - eyeRadiusY, eyeRadiusX * 2, vHeight), skinPaint);
      canvas.drawRect(Rect.fromLTWH(rightEyeX - eyeRadiusX, rightEyeY - eyeRadiusY, eyeRadiusX * 2, vHeight), skinPaint);
    }

    // 6. Отрисовка РТА (Аккуратная черная линия строго на губах аватара)
    final Paint mouthPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final double mouthOpenHeight = 5.0 * mouthVolume; // Управление открытием рта

    if (mouthVolume < 0.1) {
      // Сомкнутый рот — тонкая нить губ
      canvas.drawLine(Offset(mouthX - mouthWidth / 2, mouthY), Offset(mouthX + mouthWidth / 2, mouthY), mouthPaint);
    } else {
      // Открытый рот — аккуратная дуга вниз
      final Path mouthPath = Path();
      mouthPath.moveTo(mouthX - mouthWidth / 2, mouthY);
      mouthPath.quadraticBezierTo(mouthX, mouthY + mouthOpenHeight, mouthX + mouthWidth / 2, mouthY);
      canvas.drawPath(mouthPath, mouthPaint);
    }

    // 7. Белые debug-точки для HUD визуального контроля (встанут строго по центрам)
    final Paint debugPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(leftEyeX, leftEyeY), 1.5, debugPaint);
    canvas.drawCircle(Offset(rightEyeX, rightEyeY), 1.5, debugPaint);
    canvas.drawCircle(Offset(mouthX, mouthY), 1.5, debugPaint);
  }

  @override
  bool shouldRepaint(covariant _ViolettaFaceOverlayPainter oldDelegate) {
    return oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtY != lookAtY ||
        oldDelegate.blinkProgress != blinkProgress ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
