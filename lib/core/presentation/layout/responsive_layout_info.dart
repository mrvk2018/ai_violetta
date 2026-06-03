import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum DeviceFormFactor {
  flat, // Обычный плоский экран (моноблок, iOS/Android)
  flexed // Сложенное состояние (ноутбук-стайл, Flex Mode)
}

class ResponsiveLayoutInfo {
  final DeviceFormFactor formFactor;
  final double topPanelHeight;
  final double bottomPanelHeight;
  final double hingeHeight;

  const ResponsiveLayoutInfo({
    required this.formFactor,
    required this.topPanelHeight,
    required this.bottomPanelHeight,
    this.hingeHeight = 0.0,
  });

  factory ResponsiveLayoutInfo.fromContext(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final Size screenSize = mediaQuery.size;

    ui.DisplayFeature? horizontalHinge;
    for (final ui.DisplayFeature feature in mediaQuery.displayFeatures) {
      if ((feature.type == ui.DisplayFeatureType.hinge ||
              feature.type == ui.DisplayFeatureType.fold) &&
          feature.bounds.top > 0 &&
          feature.bounds.left == 0) {
        horizontalHinge = feature;
        break;
      }
    }

    if (horizontalHinge != null) {
      final double topHeight = horizontalHinge.bounds.top;
      final double hingeH = horizontalHinge.bounds.height;
      final double bottomHeight = screenSize.height - horizontalHinge.bounds.bottom;

      return ResponsiveLayoutInfo(
        formFactor: DeviceFormFactor.flexed,
        topPanelHeight: topHeight,
        bottomPanelHeight: bottomHeight,
        hingeHeight: hingeH,
      );
    }

    return ResponsiveLayoutInfo(
      formFactor: DeviceFormFactor.flat,
      topPanelHeight: screenSize.height,
      bottomPanelHeight: 0.0,
    );
  }
}
