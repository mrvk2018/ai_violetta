import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class NaverMapHudWidget extends StatelessWidget {
  const NaverMapHudWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(37.5665, 126.9780),
            zoom: 15,
          ),
          mapType: NMapType.navi,
          nightModeEnable: true,
          locationButtonEnable: false,
          compassEnable: false,
          scaleBarEnable: false,
          indoorEnable: false,
        ),
        onMapReady: (_) {
          debugPrint('[NAV] NaverMap ready (Seoul HUD background)');
        },
      ),
    );
  }
}
