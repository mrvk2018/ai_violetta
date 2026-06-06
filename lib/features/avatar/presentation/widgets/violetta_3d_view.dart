import 'package:flutter/material.dart';
import 'package:violetta_app/features/avatar/application/violetta_gesture_binding_controller.dart';
import 'package:violetta_app/features/avatar/application/violetta_lipsync_controller.dart';
import 'package:violetta_app/features/avatar/presentation/widgets/violetta_3d_render_engine.dart';

/// Primary HUD avatar surface combining lipsync mouth and air-gesture skeletal inputs.
class Violetta3DView extends StatelessWidget {
  final ViolettaLipsyncController lipsyncController;
  final ViolettaGestureBindingController gestureController;

  const Violetta3DView({
    super.key,
    required this.lipsyncController,
    required this.gestureController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        lipsyncController,
        gestureController,
      ]),
      builder: (BuildContext context, Widget? child) {
        return Violetta3DRenderEngine(
          lookAtX: gestureController.lookAtX,
          lookAtY: gestureController.lookAtY,
          leftArmAngle: gestureController.leftArmAngle,
          rightArmAngle: gestureController.rightArmAngle,
          mouthVolume: lipsyncController.currentMouthVolume,
        );
      },
    );
  }
}
