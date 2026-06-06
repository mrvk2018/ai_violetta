import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Pseudo-3D (2.5D) Live2D-style render engine for the Violetta AR avatar.
///
/// Composes three raster layers (body + arms) with GPU-accelerated [Matrix4]
/// perspective, organic breathing, procedural blink/mouth overlays, and
/// external gesture / lipsync inputs.
class Violetta3DRenderEngine extends StatefulWidget {
  /// Normalized horizontal look target in [-1.0, 1.0].
  final double lookAtX;

  /// Normalized vertical look target in [-1.0, 1.0].
  final double lookAtY;

  /// Shoulder rotation for the left arm (radians), e.g. from [AirGestureService].
  final double leftArmAngle;

  /// Shoulder rotation for the right arm (radians), e.g. from [AirGestureService].
  final double rightArmAngle;

  /// Mouth opening driven by local TTS decibel stream in [0.0, 1.0].
  final double mouthVolume;

  const Violetta3DRenderEngine({
    super.key,
    this.lookAtX = 0.0,
    this.lookAtY = 0.0,
    this.leftArmAngle = 0.0,
    this.rightArmAngle = 0.0,
    this.mouthVolume = 0.0,
  });

  @override
  State<Violetta3DRenderEngine> createState() => _Violetta3DRenderEngineState();
}

class _Violetta3DRenderEngineState extends State<Violetta3DRenderEngine>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _bodyAsset = 'assets/avatar/violetta_body.png';
  static const String _leftArmAsset = 'assets/avatar/left_arm.png';
  static const String _rightArmAsset = 'assets/avatar/right_arm.png';

  static const Duration _breathCycle = Duration(milliseconds: 4200);
  static const Duration _headBreathDelay = Duration(milliseconds: 150);
  static const Duration _blinkDuration = Duration(milliseconds: 120);
  static const Duration _minBlinkInterval = Duration(milliseconds: 3500);
  static const Duration _maxBlinkInterval = Duration(milliseconds: 5000);

  static const double _perspectiveEntry = 0.0018;
  static const double _maxHeadYaw = 0.22;
  static const double _maxHeadPitch = 0.12;
  static const double _maxParallaxShift = 14.0;
  static const double _torsoBreathAmplitude = 0.018;
  static const double _upperBodyBreathLift = 0.016;
  static const double _armBreathSway = 0.045;

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
  void didUpdateWidget(covariant Violetta3DRenderEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool shouldRender = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
      AppLifecycleState.hidden => false,
    };

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

  double _organicBreathWave(double phase) {
    final double angle = phase * math.pi * 2.0;
    return math.sin(angle) * 0.72 +
        math.sin(angle * 0.47) * 0.2 +
        math.sin(angle * 2.17) * 0.08;
  }

  double _delayedBreathPhase(double primaryPhase) {
    final double delayFraction =
        _headBreathDelay.inMilliseconds / _breathCycle.inMilliseconds;
    return (primaryPhase - delayFraction + 1.0) % 1.0;
  }

  Matrix4 _buildPerspectiveMatrix() {
    return Matrix4.identity()..setEntry(3, 2, _perspectiveEntry);
  }

  Matrix4 _buildHeadLookMatrix({
    required double lookAtX,
    required double lookAtY,
  }) {
    final Matrix4 matrix = Matrix4.identity();
    matrix.rotateY(lookAtX * _maxHeadYaw);
    matrix.rotateX(-lookAtY * _maxHeadPitch);
    return matrix;
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
      return const SizedBox.shrink();
    }

    final double lookAtX = _clampLook(widget.lookAtX);
    final double lookAtY = _clampLook(widget.lookAtY);
    final double mouthVolume = widget.mouthVolume.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _breathController,
          _blinkController,
        ]),
        builder: (BuildContext context, Widget? child) {
          final double breathPhase = _breathController.value;
          final double torsoWave = _organicBreathWave(breathPhase);
          final double upperWave =
              _organicBreathWave(_delayedBreathPhase(breathPhase));

          final double torsoScaleY = 1.0 + torsoWave * _torsoBreathAmplitude;
          final double upperLift = upperWave * _upperBodyBreathLift;
          final double armSway = math.sin(breathPhase * math.pi * 2.0) * _armBreathSway;

          final double blinkClosure = _resolveBlinkClosure(_blinkController.value);
          final double parallaxX = -lookAtX * _maxParallaxShift;
          final double parallaxY = lookAtY * (_maxParallaxShift * 0.35);

          return Transform(
            alignment: Alignment.center,
            transform: _buildPerspectiveMatrix(),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double canvasSize = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                final double upperLiftPx = upperLift * canvasSize;

                return SizedBox(
                  width: canvasSize,
                  height: canvasSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: <Widget>[
                      _buildTorsoLayer(torsoScaleY: torsoScaleY),
                      Transform.translate(
                        offset: Offset(0.0, -upperLiftPx),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: <Widget>[
                            _buildArmLayer(
                              assetPath: _leftArmAsset,
                              alignment: const Alignment(0.24, -0.34),
                              angle: widget.leftArmAngle + armSway,
                            ),
                            _buildArmLayer(
                              assetPath: _rightArmAsset,
                              alignment: const Alignment(-0.24, -0.34),
                              angle: widget.rightArmAngle - armSway,
                            ),
                            _buildHeadVolumeLayer(
                              canvasSize: canvasSize,
                              lookAtX: lookAtX,
                              lookAtY: lookAtY,
                              parallaxX: parallaxX,
                              parallaxY: parallaxY,
                              blinkClosure: blinkClosure,
                              mouthVolume: mouthVolume,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  double _resolveBlinkClosure(double controllerValue) {
    if (controllerValue <= 0.5) {
      return Curves.easeIn.transform(controllerValue / 0.5) * 0.62;
    }
    return lerpDouble(0.62, 1.0, Curves.easeOut.transform((controllerValue - 0.5) / 0.5))!;
  }

  Widget _buildTorsoLayer({required double torsoScaleY}) {
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.diagonal3Values(1.0, torsoScaleY, 1.0),
      child: _layerImage(_bodyAsset),
    );
  }

  Widget _buildArmLayer({
    required String assetPath,
    required Alignment alignment,
    required double angle,
  }) {
    return Align(
      alignment: alignment,
      child: Transform.rotate(
        angle: angle,
        alignment: const Alignment(0.5, 0.08),
        child: FractionallySizedBox(
          widthFactor: 0.42,
          heightFactor: 0.42,
          child: _layerImage(assetPath),
        ),
      ),
    );
  }

  Widget _buildHeadVolumeLayer({
    required double canvasSize,
    required double lookAtX,
    required double lookAtY,
    required double parallaxX,
    required double parallaxY,
    required double blinkClosure,
    required double mouthVolume,
  }) {
    return Transform(
      alignment: const Alignment(0.0, -0.18),
      transform: _buildHeadLookMatrix(
        lookAtX: lookAtX,
        lookAtY: lookAtY,
      ),
      child: Transform.translate(
        offset: Offset(parallaxX, parallaxY),
        child: _ViolettaFacialOverlay(
          size: canvasSize,
          lookAtX: lookAtX,
          lookAtY: lookAtY,
          blinkClosure: blinkClosure,
          mouthVolume: mouthVolume,
        ),
      ),
    );
  }

  Widget _layerImage(String assetPath) {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              assetPath.split('/').last,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}

class _ViolettaFacialOverlay extends StatelessWidget {
  final double size;
  final double lookAtX;
  final double lookAtY;
  final double blinkClosure;
  final double mouthVolume;

  const _ViolettaFacialOverlay({
    required this.size,
    required this.lookAtX,
    required this.lookAtY,
    required this.blinkClosure,
    required this.mouthVolume,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ViolettaFacePainter(
          lookAtX: lookAtX,
          lookAtY: lookAtY,
          blinkClosure: blinkClosure,
          mouthVolume: mouthVolume,
        ),
      ),
    );
  }
}

class _ViolettaFacePainter extends CustomPainter {
  static const double _referenceSize = 500.0;

  final double lookAtX;
  final double lookAtY;
  final double blinkClosure;
  final double mouthVolume;

  const _ViolettaFacePainter({
    required this.lookAtX,
    required this.lookAtY,
    required this.blinkClosure,
    required this.mouthVolume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / _referenceSize;
    canvas.save();
    canvas.scale(scale, scale);

    _paintEyes(canvas);
    _paintMouth(canvas);

    canvas.restore();
  }

  void _paintEyes(Canvas canvas) {
    final Offset leftEyeCenter = Offset(188 + lookAtX * 10, 196 + lookAtY * 8);
    final Offset rightEyeCenter = Offset(312 + lookAtX * 10, 196 + lookAtY * 8);
    const double pupilRadius = 5.5;

    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF120818)
      ..style = PaintingStyle.fill;
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;

    final Offset leftPupil = leftEyeCenter + Offset(lookAtX * 4.5, lookAtY * 3.5);
    final Offset rightPupil = rightEyeCenter + Offset(lookAtX * 4.5, lookAtY * 3.5);

    canvas.drawCircle(leftPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(rightPupil, pupilRadius, pupilPaint);
    canvas.drawCircle(
      leftPupil + const Offset(-1.8, -1.6),
      1.8,
      highlightPaint,
    );
    canvas.drawCircle(
      rightPupil + const Offset(-1.8, -1.6),
      1.8,
      highlightPaint,
    );

    if (blinkClosure <= 0.001) {
      return;
    }

    final Paint lidPaint = Paint()
      ..color = const Color(0xFF1A1024).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    const double eyeWidth = 46;
    const double eyeHeight = 28;
    final double lidHeight = eyeHeight * blinkClosure;
    final RRect leftLid = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: leftEyeCenter,
        width: eyeWidth,
        height: lidHeight,
      ),
      const Radius.circular(10),
    );
    final RRect rightLid = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: rightEyeCenter,
        width: eyeWidth,
        height: lidHeight,
      ),
      const Radius.circular(10),
    );

    canvas.drawRRect(leftLid, lidPaint);
    canvas.drawRRect(rightLid, lidPaint);
  }

  void _paintMouth(Canvas canvas) {
    final Path mouthPath = _buildMouthPath(mouthVolume);
    final Paint lipFill = Paint()
      ..color = const Color(0xFF5A2040)
      ..style = PaintingStyle.fill;
    final Paint lipLine = Paint()
      ..color = const Color(0xFF2A0E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(mouthPath, lipFill);
    canvas.drawPath(mouthPath, lipLine);

    if (mouthVolume > 0.08) {
      final Paint innerMouth = Paint()
        ..color = const Color(0xFF120812).withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawPath(
        _buildInnerMouthPath(mouthVolume),
        innerMouth,
      );
    }
  }

  Path _buildMouthPath(double volume) {
    const Offset center = Offset(250, 292);
    final double openHeight = lerpDouble(3.5, 24.0, volume)!;
    final double width = lerpDouble(34.0, 42.0, volume)!;
    final double cornerDrop = lerpDouble(1.0, 6.0, volume)!;

    final Path path = Path();
    path.moveTo(center.dx - width * 0.5, center.dy - openHeight * 0.15);
    path.cubicTo(
      center.dx - width * 0.22,
      center.dy - openHeight * 0.55 - cornerDrop,
      center.dx + width * 0.22,
      center.dy - openHeight * 0.55 - cornerDrop,
      center.dx + width * 0.5,
      center.dy - openHeight * 0.15,
    );
    path.cubicTo(
      center.dx + width * 0.24,
      center.dy + openHeight * 0.75,
      center.dx - width * 0.24,
      center.dy + openHeight * 0.75,
      center.dx - width * 0.5,
      center.dy - openHeight * 0.15,
    );
    path.close();
    return path;
  }

  Path _buildInnerMouthPath(double volume) {
    const Offset center = Offset(250, 294);
    final double openHeight = lerpDouble(0.0, 14.0, volume)!;
    final double width = lerpDouble(0.0, 24.0, volume)!;

    final RRect inner = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: width,
        height: openHeight,
      ),
      Radius.circular(openHeight * 0.45),
    );
    return Path()..addRRect(inner);
  }

  @override
  bool shouldRepaint(covariant _ViolettaFacePainter oldDelegate) {
    return oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtY != lookAtY ||
        oldDelegate.blinkClosure != blinkClosure ||
        oldDelegate.mouthVolume != mouthVolume;
  }
}
