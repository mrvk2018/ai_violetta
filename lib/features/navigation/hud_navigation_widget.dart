import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class HudNavigationWidget extends StatefulWidget {
  const HudNavigationWidget({super.key});

  @override
  State<HudNavigationWidget> createState() => _HudNavigationWidgetState();
}

class _HudNavigationWidgetState extends State<HudNavigationWidget> {
  static const double _hudOpacity = 0.45;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double hudWidth = screenSize.width * 0.38;
    final double hudHeight = screenSize.height * 0.38;

    return Align(
      alignment: Alignment.topRight,
      child: SizedBox(
        width: hudWidth,
        height: hudHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Opacity(
            opacity: _hudOpacity,
            child: NaverMap(
              options: const NaverMapViewOptions(
                indoorEnable: false, // indoorLayerEnable: false
                locationButtonEnable: false, // locationButtonOptions: false
                scaleBarEnable: false,
                compassEnable: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
