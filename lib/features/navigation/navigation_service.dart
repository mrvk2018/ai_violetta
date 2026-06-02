enum NavigationTransportType {
  pedestrian,
  bicycle,
  transit,
}

class NavigationService {
  NavigationTransportType _currentTransportType = NavigationTransportType.pedestrian;

  NavigationTransportType get currentTransportType => _currentTransportType;

  void setTransportType(NavigationTransportType transportType) {
    _currentTransportType = transportType;
  }

  double calculateDynamicZoom(double distanceToNextTurn) {
    const double minZoom = 10.0;
    const double nearTurnZoom = 14.0;
    const double maxZoom = 18.0;
    const double nearTurnThresholdMeters = 50.0;
    const double farDistanceThresholdMeters = 1000.0;

    if (distanceToNextTurn <= nearTurnThresholdMeters) {
      final double normalized =
          (distanceToNextTurn / nearTurnThresholdMeters).clamp(0.0, 1.0);
      final double zoom = maxZoom - (maxZoom - nearTurnZoom) * normalized;
      return zoom.clamp(minZoom, maxZoom);
    }

    final double normalizedFar = ((distanceToNextTurn - nearTurnThresholdMeters) /
            (farDistanceThresholdMeters - nearTurnThresholdMeters))
        .clamp(0.0, 1.0);
    final double zoom = nearTurnZoom - (nearTurnZoom - minZoom) * normalizedFar;
    return zoom.clamp(minZoom, maxZoom);
  }
}
