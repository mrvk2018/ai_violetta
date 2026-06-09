import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Codec, Image, ImageByteFormat, instantiateImageCodec;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single-sprite 2.5D avatar engine for [bodyAsset] (`375×666` PNG).
class Violetta3DRenderEngine extends StatefulWidget {
  static const String bodyAsset = 'assets/violetta_bodyfull.png';
  static const Size canvasSize = Size(500, 500);
  static const Size imageReferenceSize = Size(375, 666);
  static const double imageAspectRatio = 375 / 666;

  /// Fallback norms used until color-cluster scan completes (origin top-left).
  static const Offset _fallbackLeftEyeNorm = Offset(0.3972, 0.2634);
  static const Offset _fallbackRightEyeNorm = Offset(0.4736, 0.2686);
  static const Offset _fallbackMouthNorm = Offset(0.4839, 0.3099);

  static Offset leftEyeNorm = _fallbackLeftEyeNorm;
  static Offset rightEyeNorm = _fallbackRightEyeNorm;
  static Offset mouthNorm = _fallbackMouthNorm;
  static bool landmarksDetected = false;

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

  static void applyDetectedLandmarks({
    required Offset leftEye,
    required Offset rightEye,
    required Offset mouth,
  }) {
    leftEyeNorm = leftEye;
    rightEyeNorm = rightEye;
    mouthNorm = mouth;
    landmarksDetected = true;
  }

  @override
  State<Violetta3DRenderEngine> createState() => _Violetta3DRenderEngineState();
}

/// Scans [Violetta3DRenderEngine.bodyAsset] for red eye and blue mouth markup.
class ViolettaFaceLandmarkDetector {
  static Future<void>? _initialization;

  static Future<void> ensureInitialized() {
    return _initialization ??= _scanAssetLandmarks();
  }

  @visibleForTesting
  static void resetForTest() {
    _initialization = null;
    Violetta3DRenderEngine.leftEyeNorm = Violetta3DRenderEngine._fallbackLeftEyeNorm;
    Violetta3DRenderEngine.rightEyeNorm =
        Violetta3DRenderEngine._fallbackRightEyeNorm;
    Violetta3DRenderEngine.mouthNorm = Violetta3DRenderEngine._fallbackMouthNorm;
    Violetta3DRenderEngine.landmarksDetected = false;
  }

  static Future<void> _scanAssetLandmarks() async {
    final ByteData assetBytes =
        await rootBundle.load(Violetta3DRenderEngine.bodyAsset);
    final ui.Codec codec = await ui.instantiateImageCodec(
      assetBytes.buffer.asUint8List(),
    );
    final ui.Image image = (await codec.getNextFrame()).image;
    final ByteData? rawRgba = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    final int imageWidth = image.width;
    final int imageHeight = image.height;
    image.dispose();

    if (rawRgba == null) {
      debugPrint(
        'Asset Scan Failed: unable to read raw RGBA bytes from '
        '${Violetta3DRenderEngine.bodyAsset}',
      );
      return;
    }

    final List<Offset> redPixels = <Offset>[];
    final List<Offset> bluePixels = <Offset>[];

    for (int y = 0; y < imageHeight; y++) {
      for (int x = 0; x < imageWidth; x++) {
        final int index = (y * imageWidth + x) * 4;
        final int red = rawRgba.getUint8(index);
        final int green = rawRgba.getUint8(index + 1);
        final int blue = rawRgba.getUint8(index + 2);

        if (red > 230 && green < 25 && blue < 25) {
          redPixels.add(Offset(x.toDouble(), y.toDouble()));
        } else if (blue > 230 && red < 25 && green < 25) {
          bluePixels.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }

    if (redPixels.isEmpty || bluePixels.isEmpty) {
      debugPrint(
        'Asset Scan Failed: color markup not found on ${imageWidth}x$imageHeight '
        '(red=${redPixels.length}, blue=${bluePixels.length})',
      );
      return;
    }

    final List<List<Offset>> eyeClusters = _splitRedEyeClusters(redPixels);
    final List<Offset> leftCluster = eyeClusters[0];
    final List<Offset> rightCluster = eyeClusters[1];

    if (leftCluster.isEmpty || rightCluster.isEmpty) {
      debugPrint(
        'Asset Scan Failed: could not split red eye clusters '
        '(left=${leftCluster.length}, right=${rightCluster.length})',
      );
      return;
    }

    final Offset leftEyePx = _pixelCentroid(leftCluster);
    final Offset rightEyePx = _pixelCentroid(rightCluster);
    final Offset mouthPx = _pixelCentroid(bluePixels);

    final Offset leftEyeNorm = Offset(
      leftEyePx.dx / imageWidth,
      leftEyePx.dy / imageHeight,
    );
    final Offset rightEyeNorm = Offset(
      rightEyePx.dx / imageWidth,
      rightEyePx.dy / imageHeight,
    );
    final Offset mouthNorm = Offset(
      mouthPx.dx / imageWidth,
      mouthPx.dy / imageHeight,
    );

    Violetta3DRenderEngine.applyDetectedLandmarks(
      leftEye: leftEyeNorm,
      rightEye: rightEyeNorm,
      mouth: mouthNorm,
    );

    debugPrint(
      'Asset Scan Success (${imageWidth}x$imageHeight): '
      'red=${redPixels.length}, blue=${bluePixels.length}',
    );
    debugPrint(
      'Asset Scan Success: Left Eye at '
      '${leftEyePx.dx.toStringAsFixed(1)}, ${leftEyePx.dy.toStringAsFixed(1)}',
    );
    debugPrint(
      'Asset Scan Success: Right Eye at '
      '${rightEyePx.dx.toStringAsFixed(1)}, ${rightEyePx.dy.toStringAsFixed(1)}',
    );
    debugPrint(
      'Asset Scan Success: Mouth at '
      '${mouthPx.dx.toStringAsFixed(1)}, ${mouthPx.dy.toStringAsFixed(1)}',
    );
    debugPrint(
      'Asset Scan Success: leftEyeNorm='
      '(${leftEyeNorm.dx.toStringAsFixed(4)}, ${leftEyeNorm.dy.toStringAsFixed(4)})',
    );
    debugPrint(
      'Asset Scan Success: rightEyeNorm='
      '(${rightEyeNorm.dx.toStringAsFixed(4)}, ${rightEyeNorm.dy.toStringAsFixed(4)})',
    );
    debugPrint(
      'Asset Scan Success: mouthNorm='
      '(${mouthNorm.dx.toStringAsFixed(4)}, ${mouthNorm.dy.toStringAsFixed(4)})',
    );
  }

  static Offset _pixelCentroid(List<Offset> pixels) {
    double sumX = 0.0;
    double sumY = 0.0;
    for (final Offset pixel in pixels) {
      sumX += pixel.dx;
      sumY += pixel.dy;
    }
    final double count = pixels.length.toDouble();
    return Offset(sumX / count, sumY / count);
  }

  static List<List<Offset>> _splitRedEyeClusters(List<Offset> redPixels) {
    final List<double> xs = redPixels.map((Offset p) => p.dx).toList()..sort();
    final double splitX = (xs.first + xs.last) * 0.5;

    final List<Offset> leftCluster = <Offset>[];
    final List<Offset> rightCluster = <Offset>[];
    for (final Offset pixel in redPixels) {
      if (pixel.dx < splitX) {
        leftCluster.add(pixel);
      } else {
        rightCluster.add(pixel);
      }
    }

    return <List<Offset>>[leftCluster, rightCluster];
  }

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
    unawaited(
      ViolettaFaceLandmarkDetector.ensureInitialized().then((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    );
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
                            landmarksDetected:
                                Violetta3DRenderEngine.landmarksDetected,
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
  final bool landmarksDetected;

  const _ViolettaFaceOverlayPainter({
    required this.lookAtX,
    required this.lookAtY,
    required this.blinkProgress,
    required this.mouthVolume,
    required this.landmarksDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final _SpriteDrawBox drawBox = _SpriteDrawBox.fromCanvasSize(size);
    final double currentScale = drawBox.currentScale;

    final Offset leftEye = drawBox.landmark(Violetta3DRenderEngine.leftEyeNorm);
    final Offset rightEye =
        drawBox.landmark(Violetta3DRenderEngine.rightEyeNorm);
    final Offset mouth = drawBox.landmark(Violetta3DRenderEngine.mouthNorm);

    final double eyeRadiusX = 5.2 * currentScale;
    final double eyeRadiusY = 3.6 * currentScale;
    final double pupilRadius = 2.0 * currentScale;
    final double mouthWidth = 12.0 * currentScale;

    final Paint eyeBasePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint pupilPaint = Paint()
      ..color = const Color(0xFF3D2A1C)
      ..style = PaintingStyle.fill;
    final Paint skinPaint = Paint()
      ..color = const Color(0xFFC89472)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: leftEye,
        width: eyeRadiusX * 2,
        height: eyeRadiusY * 2,
      ),
      eyeBasePaint,
    );
    canvas.drawCircle(
      leftEye + Offset(lookAtX * 3.0 * currentScale, lookAtY * 2.0 * currentScale),
      pupilRadius,
      pupilPaint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: rightEye,
        width: eyeRadiusX * 2,
        height: eyeRadiusY * 2,
      ),
      eyeBasePaint,
    );
    canvas.drawCircle(
      rightEye + Offset(lookAtX * 3.0 * currentScale, lookAtY * 2.0 * currentScale),
      pupilRadius,
      pupilPaint,
    );

    if (blinkProgress > 0.0) {
      final double lidHeight = eyeRadiusY * 2 * blinkProgress;
      canvas.drawRect(
        Rect.fromLTWH(
          leftEye.dx - eyeRadiusX,
          leftEye.dy - eyeRadiusY,
          eyeRadiusX * 2,
          lidHeight,
        ),
        skinPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          rightEye.dx - eyeRadiusX,
          rightEye.dy - eyeRadiusY,
          eyeRadiusX * 2,
          lidHeight,
        ),
        skinPaint,
      );
    }

    final Paint mouthPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * currentScale
      ..strokeCap = StrokeCap.round;
    final double mouthOpenHeight = 6.0 * currentScale * mouthVolume;

    if (mouthVolume < 0.1) {
      canvas.drawLine(
        Offset(mouth.dx - mouthWidth / 2, mouth.dy),
        Offset(mouth.dx + mouthWidth / 2, mouth.dy),
        mouthPaint,
      );
    } else {
      final Path mouthPath = Path()
        ..moveTo(mouth.dx - mouthWidth / 2, mouth.dy)
        ..quadraticBezierTo(
          mouth.dx,
          mouth.dy + mouthOpenHeight,
          mouth.dx + mouthWidth / 2,
          mouth.dy,
        );
      canvas.drawPath(mouthPath, mouthPaint);
    }

    if (landmarksDetected) {
      final Paint debugPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(leftEye, 1.5, debugPaint);
      canvas.drawCircle(rightEye, 1.5, debugPaint);
      canvas.drawCircle(mouth, 1.5, debugPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ViolettaFaceOverlayPainter oldDelegate) {
    return oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtY != lookAtY ||
        oldDelegate.blinkProgress != blinkProgress ||
        oldDelegate.mouthVolume != mouthVolume ||
        oldDelegate.landmarksDetected != landmarksDetected;
  }
}
