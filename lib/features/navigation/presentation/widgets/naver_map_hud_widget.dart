import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:violetta_app/features/navigation/services/naver_map_bootstrap_service.dart';

class NaverMapHudWidget extends StatelessWidget {
  const NaverMapHudWidget({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.25),
          alignment: Alignment.center,
          child: const Text(
            'Naver Map background (mobile only)',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (!NaverMapBootstrapService.instance.isReady) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.25),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Text(
            'Карта Naver: добавьте Naver Client ID в панели BYOK-ключей.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }

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
