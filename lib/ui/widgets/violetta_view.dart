import 'package:flutter/material.dart';
import 'package:violetta_app/core/graphics/violetta_3d_render_engine.dart';
import 'package:violetta_app/features/avatar/application/hand_state_machine_controller.dart';

class ViolettaView extends StatelessWidget {
  static const String handDownAsset = 'assets/images/violetta_hand_down.png';
  static const Duration crossFadeDuration = Duration(milliseconds: 800);

  final HandStateMachineController controller;
  final BoxFit fit;

  const ViolettaView({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: <Widget>[
            AnimatedOpacity(
              opacity: controller.handUpOpacity,
              duration: crossFadeDuration,
              curve: Curves.easeInOutCubic,
              child: Image.asset(
                Violetta3DRenderEngine.bodyAsset,
                fit: fit,
                gaplessPlayback: true,
              ),
            ),
            AnimatedOpacity(
              opacity: controller.handDownOpacity,
              duration: crossFadeDuration,
              curve: Curves.easeInOutCubic,
              child: Image.asset(
                handDownAsset,
                fit: fit,
                gaplessPlayback: true,
              ),
            ),
          ],
        );
      },
    );
  }
}
