import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:violetta_app/features/auth/auth_service.dart';

/// Initializes Naver Map SDK with the signed-in user's BYOK client ID.
class NaverMapBootstrapService {
  NaverMapBootstrapService._();

  static final NaverMapBootstrapService instance = NaverMapBootstrapService._();

  bool _isInitialized = false;
  String? _activeClientId;

  bool get isReady => _isInitialized;

  String? get activeClientId => _activeClientId;

  Future<bool> initializeFromAuth({AuthService? authService}) async {
    if (kIsWeb) {
      return false;
    }

    final AuthService auth = authService ?? AuthService.instance;
    final String? clientId = auth.naverClientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      debugPrint('[BYOK] Naver Map skipped: naverClientId is not configured.');
      return false;
    }

    if (_isInitialized && _activeClientId == clientId) {
      return true;
    }

    await FlutterNaverMap().init(
      clientId: clientId,
      onAuthFailed: (NAuthFailedException ex) {
        debugPrint('[BYOK] Naver Map auth failed: $ex');
      },
    );

    _isInitialized = true;
    _activeClientId = clientId;
    debugPrint('[BYOK] Naver Map initialized for clientId=$clientId');
    return true;
  }

  Future<bool> reinitialize({AuthService? authService}) async {
    _isInitialized = false;
    _activeClientId = null;
    return initializeFromAuth(authService: authService);
  }
}
