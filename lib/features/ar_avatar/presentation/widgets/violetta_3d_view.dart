import 'package:flutter/material.dart';
import 'package:o3d/o3d.dart';
import 'package:violetta_app/features/ar_avatar/domain/avatar_state.dart';

class Violetta3DView extends StatefulWidget {
  final AvatarAnimationState currentState;

  const Violetta3DView({
    super.key,
    required this.currentState,
  });

  @override
  State<Violetta3DView> createState() => _Violetta3DViewState();
}

class _Violetta3DViewState extends State<Violetta3DView>
    with WidgetsBindingObserver {
  late O3DController _o3dController;
  bool _isRenderActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _o3dController = O3DController();
  }

  @override
  void didUpdateWidget(covariant Violetta3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentState != widget.currentState) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    _o3dController.animationName = widget.currentState.trackName;
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRenderActive) {
      return const SizedBox.shrink();
    }
    return O3D(
      controller: _o3dController,
      src: 'assets/models/violetta_beanie.glb',
      autoPlay: true,
      animationName: widget.currentState.trackName,
      cameraControls: false,
      autoRotate: false,
      shadowIntensity: 0.0,
      backgroundColor: Colors.transparent,
    );
  }
}
