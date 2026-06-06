import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:violetta_app/core/presentation/layout/responsive_layout_info.dart';
import 'package:violetta_app/features/avatar/presentation/widgets/violetta_3d_render_engine.dart';

/// Interactive desktop-oriented debug HUD for tuning the 2.5D avatar render engine.
class ViolettaDebugScreen extends StatefulWidget {
  const ViolettaDebugScreen({super.key});

  @override
  State<ViolettaDebugScreen> createState() => _ViolettaDebugScreenState();
}

class _ViolettaDebugScreenState extends State<ViolettaDebugScreen>
    with SingleTickerProviderStateMixin {
  static const Color _hudBackground = Color(0xFF1C222B);
  static const Color _canvasBackground = Color(0xFF141920);
  static const Color _neonCyan = Color(0xFF00F5FF);
  static const Color _neonPink = Color(0xFFFF4FCB);

  static const double _controlPanelWidth = 340.0;
  static const double _controlPanelMinHeight = 280.0;
  static const double _lookAtSmoothing = 0.2;
  static const double _armAngleMin = -1.85;
  static const double _armAngleMax = 1.85;

  double _targetLookAtX = 0.0;
  double _targetLookAtY = 0.0;
  double _lookAtX = 0.0;
  double _lookAtY = 0.0;
  double _mouthVolume = 0.0;
  double _manualMouthVolume = 0.0;
  double _leftArmAngle = 0.0;
  double _rightArmAngle = 0.0;
  bool _simulateSpeech = false;

  Timer? _speechSimulationTimer;
  Ticker? _lookAtTicker;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _lookAtTicker = createTicker(_onLookAtTick)..start();
  }

  @override
  void dispose() {
    _speechSimulationTimer?.cancel();
    _lookAtTicker?.dispose();
    super.dispose();
  }

  void _onLookAtTick(Duration elapsed) {
    final double? nextX = lerpDouble(_lookAtX, _targetLookAtX, _lookAtSmoothing);
    final double? nextY = lerpDouble(_lookAtY, _targetLookAtY, _lookAtSmoothing);
    if (nextX == null || nextY == null) {
      return;
    }

    if ((nextX - _lookAtX).abs() < 0.0005 && (nextY - _lookAtY).abs() < 0.0005) {
      return;
    }

    setState(() {
      _lookAtX = nextX.clamp(-1.0, 1.0);
      _lookAtY = nextY.clamp(-1.0, 1.0);
    });
  }

  void _updateLookTarget(Offset localPosition, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }

    final double normalizedX =
        ((localPosition.dx / canvasSize.width) * 2.0 - 1.0).clamp(-1.0, 1.0);
    final double normalizedY =
        ((localPosition.dy / canvasSize.height) * 2.0 - 1.0).clamp(-1.0, 1.0);

    _targetLookAtX = normalizedX;
    _targetLookAtY = normalizedY;
  }

  void _setSimulateSpeech(bool enabled) {
    _speechSimulationTimer?.cancel();
    setState(() {
      _simulateSpeech = enabled;
      if (!enabled) {
        _mouthVolume = _manualMouthVolume;
      }
    });

    if (!enabled) {
      return;
    }

    final math.Random random = math.Random();
    _speechSimulationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      Timer timer,
    ) {
      if (!mounted || !_simulateSpeech) {
        timer.cancel();
        return;
      }

      final double syllablePeak = random.nextDouble();
      final double microJitter = (random.nextDouble() - 0.5) * 0.08;
      setState(() {
        _mouthVolume = (syllablePeak * 0.82 + microJitter + 0.08).clamp(0.0, 1.0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ResponsiveLayoutInfo layout = ResponsiveLayoutInfo.fromContext(context);
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final bool stackControlsBelow = mediaQuery.size.width < 860.0;

    return Scaffold(
      backgroundColor: _hudBackground,
      appBar: AppBar(
        backgroundColor: _canvasBackground,
        foregroundColor: _neonCyan,
        elevation: 0,
        title: const Text(
          'Violetta 2.5D Debug HUD',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                layout.formFactor == DeviceFormFactor.flexed ? 'FLEXED' : 'FLAT',
                style: TextStyle(
                  color: layout.formFactor == DeviceFormFactor.flexed
                      ? _neonPink
                      : _neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: layout.formFactor == DeviceFormFactor.flexed
            ? _buildFlexedLayout(layout, stackControlsBelow)
            : _buildFlatLayout(stackControlsBelow),
      ),
    );
  }

  Widget _buildFlatLayout(bool stackControlsBelow) {
    if (stackControlsBelow) {
      return Column(
        children: <Widget>[
          Expanded(child: _buildInteractiveCanvas()),
          SizedBox(
            height: _controlPanelMinHeight,
            child: _buildControlPanel(),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: _buildInteractiveCanvas()),
        SizedBox(width: _controlPanelWidth, child: _buildControlPanel()),
      ],
    );
  }

  Widget _buildFlexedLayout(
    ResponsiveLayoutInfo layout,
    bool stackControlsBelow,
  ) {
    final double topHeight = layout.topPanelHeight - kToolbarHeight;
    final double bottomHeight = layout.bottomPanelHeight;

    if (stackControlsBelow || bottomHeight > 0) {
      return Column(
        children: <Widget>[
          SizedBox(
            height: topHeight.clamp(220.0, layout.topPanelHeight),
            child: _buildInteractiveCanvas(),
          ),
          if (layout.hingeHeight > 0)
            SizedBox(
              height: layout.hingeHeight,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.65)),
            ),
          Expanded(
            child: bottomHeight > 0
                ? _buildControlPanel()
                : SizedBox(
                    height: _controlPanelMinHeight,
                    child: _buildControlPanel(),
                  ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        SizedBox(
          width: layout.topPanelHeight,
          child: _buildInteractiveCanvas(),
        ),
        Expanded(child: _buildControlPanel()),
      ],
    );
  }

  Widget _buildInteractiveCanvas() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size canvasSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        _canvasSize = canvasSize;

        final double avatarSize = math.min(
          canvasSize.width * 0.82,
          canvasSize.height * 0.88,
        ).clamp(160.0, 520.0);

        return MouseRegion(
          onHover: (PointerHoverEvent event) {
            _updateLookTarget(event.localPosition, canvasSize);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerMove: (PointerMoveEvent event) {
              _updateLookTarget(event.localPosition, canvasSize);
            },
            onPointerDown: (PointerDownEvent event) {
              _updateLookTarget(event.localPosition, canvasSize);
            },
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _canvasBackground,
                border: Border(
                  right: BorderSide(color: Color(0x332EEAFF)),
                  bottom: BorderSide(color: Color(0x332EEAFF)),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                fit: StackFit.expand,
                children: <Widget>[
                  _buildCanvasGrid(canvasSize),
                  Center(
                    child: SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: Violetta3DRenderEngine(
                        lookAtX: _lookAtX,
                        lookAtY: _lookAtY,
                        leftArmAngle: _leftArmAngle,
                        rightArmAngle: _rightArmAngle,
                        mouthVolume: _mouthVolume,
                      ),
                    ),
                  ),
                  _buildCanvasTelemetry(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCanvasGrid(Size canvasSize) {
    return CustomPaint(
      size: canvasSize,
      painter: _DebugGridPainter(
        lineColor: _neonCyan.withValues(alpha: 0.08),
        crosshairColor: _neonPink.withValues(alpha: 0.22),
      ),
    );
  }

  Widget _buildCanvasTelemetry() {
    return Positioned(
      left: 14,
      top: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _neonCyan.withValues(alpha: 0.45)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('lookAtX ${_lookAtX.toStringAsFixed(3)}'),
              Text('lookAtY ${_lookAtY.toStringAsFixed(3)}'),
              Text('canvas ${_canvasSize.width.toInt()}×${_canvasSize.height.toInt()}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _hudBackground.withValues(alpha: 0.94),
            const Color(0xFF10151C).withValues(alpha: 0.96),
          ],
        ),
        border: Border(
          left: BorderSide(color: _neonPink.withValues(alpha: 0.35)),
          top: BorderSide(color: _neonCyan.withValues(alpha: 0.18)),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Avatar Debug Controls',
              style: TextStyle(
                color: _neonCyan,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Move the mouse over the canvas to drive head look-at parallax.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 12),
            ),
            const SizedBox(height: 18),
            _buildSliderControl(
              label: 'mouthVolume',
              value: _simulateSpeech ? _mouthVolume : _manualMouthVolume,
              min: 0.0,
              max: 1.0,
              displayValue: _mouthVolume.toStringAsFixed(2),
              accent: _neonPink,
              enabled: !_simulateSpeech,
              onChanged: (double value) {
                setState(() {
                  _manualMouthVolume = value;
                  _mouthVolume = value;
                });
              },
            ),
            const SizedBox(height: 14),
            _buildSliderControl(
              label: 'leftArmAngle (rad)',
              value: _leftArmAngle,
              min: _armAngleMin,
              max: _armAngleMax,
              displayValue: _leftArmAngle.toStringAsFixed(2),
              accent: _neonCyan,
              onChanged: (double value) {
                setState(() {
                  _leftArmAngle = value;
                });
              },
            ),
            const SizedBox(height: 14),
            _buildSliderControl(
              label: 'rightArmAngle (rad)',
              value: _rightArmAngle,
              min: _armAngleMin,
              max: _armAngleMax,
              displayValue: _rightArmAngle.toStringAsFixed(2),
              accent: _neonCyan,
              onChanged: (double value) {
                setState(() {
                  _rightArmAngle = value;
                });
              },
            ),
            const SizedBox(height: 18),
            _buildSpeechSimulationSwitch(),
            const SizedBox(height: 16),
            _buildResetButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required Color accent,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                displayValue,
                style: const TextStyle(
                  color: Colors.white70,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.18),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechSimulationSwitch() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _simulateSpeech
              ? _neonPink.withValues(alpha: 0.75)
              : _neonCyan.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Simulate Continuous Speech Engine',
              style: TextStyle(
                color: _simulateSpeech ? _neonPink : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          Switch.adaptive(
            value: _simulateSpeech,
            activeTrackColor: _neonPink.withValues(alpha: 0.55),
            activeThumbColor: _neonPink,
            onChanged: _setSimulateSpeech,
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return OutlinedButton.icon(
      onPressed: () {
        _speechSimulationTimer?.cancel();
        setState(() {
          _targetLookAtX = 0.0;
          _targetLookAtY = 0.0;
          _lookAtX = 0.0;
          _lookAtY = 0.0;
          _manualMouthVolume = 0.0;
          _mouthVolume = 0.0;
          _leftArmAngle = 0.0;
          _rightArmAngle = 0.0;
          _simulateSpeech = false;
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: _neonCyan,
        side: BorderSide(color: _neonCyan.withValues(alpha: 0.55)),
      ),
      icon: const Icon(Icons.restart_alt_rounded, size: 18),
      label: const Text('Reset Debug State'),
    );
  }
}

class _DebugGridPainter extends CustomPainter {
  final Color lineColor;
  final Color crosshairColor;

  const _DebugGridPainter({
    required this.lineColor,
    required this.crosshairColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    const int divisions = 8;
    final double stepX = size.width / divisions;
    final double stepY = size.height / divisions;

    for (int i = 1; i < divisions; i++) {
      final double x = stepX * i;
      final double y = stepY * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final Paint crossPaint = Paint()
      ..color = crosshairColor
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      crossPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DebugGridPainter oldDelegate) => false;
}
