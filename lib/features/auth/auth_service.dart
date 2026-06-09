import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:violetta_app/features/auth/byok_user_profile.dart';
import 'package:violetta_app/features/auth/data/byok_vault_repository.dart';
import 'package:violetta_app/features/navigation/services/naver_map_bootstrap_service.dart';

/// Result of a Google sign-in attempt for the auth gate.
class AuthSignInResult {
  const AuthSignInResult({
    required this.success,
    this.cancelled = false,
    this.isMockSession = false,
  });

  final bool success;
  final bool cancelled;
  final bool isMockSession;
}

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    ByokVaultRepository? vault,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _vault = vault ?? ByokVaultRepository.instance;

  static final AuthService instance = AuthService();

  static const String mockAccessToken = 'byok-mock-google-access-token';

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final ByokVaultRepository _vault;

  ByokUserProfile? _profile;
  bool _isInitialized = false;

  bool get isAuthenticated => _profile?.hasGoogleAccessToken ?? false;

  ByokUserProfile? get currentUser => _profile;

  String? get userElevenLabsKey => _profile?.userElevenLabsKey;

  String? get naverClientId => _profile?.naverClientId;

  String? get naverClientSecret => _profile?.naverClientSecret;

  bool get hasNaverKeys => _profile?.hasNaverKeys ?? false;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    await _vault.init();
    await _restorePersistedSession();
    _isInitialized = true;
  }

  Future<String?> getUserAccessToken() async {
    final String? token = _profile?.accessToken?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }

  Future<void> setUserElevenLabsKey(String? key) async {
    final ByokUserProfile? profile = _ensureMutableProfile();
    if (profile == null) {
      return;
    }
    final String? trimmed = _normalizeOptional(key);
    profile.userElevenLabsKey = trimmed;
    await _persistCurrentProfile();
  }

  Future<void> setNaverKeys({
    required String clientId,
    required String clientSecret,
  }) async {
    final ByokUserProfile? profile = _ensureMutableProfile();
    if (profile == null) {
      return;
    }
    profile.naverClientId = _normalizeOptional(clientId);
    profile.naverClientSecret = _normalizeOptional(clientSecret);
    await _persistCurrentProfile();
    await NaverMapBootstrapService.instance.reinitialize(authService: this);
  }

  Future<void> saveByokKeys({
    String? userElevenLabsKey,
    String? naverClientId,
    String? naverClientSecret,
  }) async {
    final ByokUserProfile? profile = _ensureMutableProfile();
    if (profile == null) {
      return;
    }
    profile.userElevenLabsKey = _normalizeOptional(userElevenLabsKey);
    profile.naverClientId = _normalizeOptional(naverClientId);
    profile.naverClientSecret = _normalizeOptional(naverClientSecret);
    await _persistCurrentProfile();
    await NaverMapBootstrapService.instance.reinitialize(authService: this);
  }

  Future<AuthSignInResult> signInWithGoogle() async {
    await init();
    final bool firebaseConfigured = await _hasGoogleServicesJson();

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const AuthSignInResult(success: false, cancelled: true);
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? accessToken = googleAuth.accessToken;

      if (!firebaseConfigured) {
        return _activateMockSession(
          email: googleUser.email,
          displayName: googleUser.displayName,
          accessToken: accessToken,
        );
      }

      try {
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCredential =
            await _firebaseAuth.signInWithCredential(credential);

        await _activateAuthenticatedSession(
          email: userCredential.user?.email ?? googleUser.email,
          displayName:
              userCredential.user?.displayName ?? googleUser.displayName,
          accessToken: accessToken ?? mockAccessToken,
          isMockSession: false,
        );
        return const AuthSignInResult(success: true);
      } on FirebaseAuthException catch (error, stackTrace) {
        debugPrint(
          '[BYOK_MOCK]: Firebase bypass (${error.code}): $stackTrace',
        );
        return _activateMockSession(
          email: googleUser.email,
          displayName: googleUser.displayName,
          accessToken: accessToken,
        );
      } on Object catch (error, stackTrace) {
        debugPrint('[BYOK_MOCK]: Firebase bypass: $error $stackTrace');
        return _activateMockSession(
          email: googleUser.email,
          displayName: googleUser.displayName,
          accessToken: accessToken,
        );
      }
    } on Object catch (error, stackTrace) {
      debugPrint('[BYOK_MOCK]: Симуляция авторизации Google: $error');
      debugPrint('$stackTrace');
      return _activateMockSession();
    }
  }

  Future<void> signOut() async {
    _profile = null;
    await _vault.clearSession();
    try {
      await Future.wait<void>([
        _firebaseAuth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } on Object catch (error) {
      debugPrint('[AuthService] signOut: $error');
    }
  }

  Future<bool> _hasGoogleServicesJson() async {
    if (kIsWeb) {
      return false;
    }
    try {
      return await File('android/app/google-services.json').exists();
    } on Object {
      return false;
    }
  }

  Future<void> _restorePersistedSession() async {
    if (!_vault.isLoggedIn) {
      return;
    }

    final Map<String, dynamic> snapshot = _vault.readSessionSnapshot();
    final String? savedToken = snapshot[ByokVaultRepository.accessTokenKey] as String?;
    if (savedToken == null || savedToken.isEmpty) {
      return;
    }

    final bool isMockSession =
        snapshot[ByokVaultRepository.isMockSessionKey] as bool? ?? false;

    _profile = ByokUserProfile(
      email: snapshot[ByokVaultRepository.emailKey] as String?,
      displayName: snapshot[ByokVaultRepository.displayNameKey] as String?,
      accessToken: savedToken,
      userElevenLabsKey:
          snapshot[ByokVaultRepository.userElevenLabsKeyKey] as String?,
      naverClientId: snapshot[ByokVaultRepository.naverClientIdKey] as String?,
      naverClientSecret:
          snapshot[ByokVaultRepository.naverClientSecretKey] as String?,
      isMockSession: isMockSession,
    );

    if (!isMockSession) {
      try {
        final GoogleSignInAccount? silentUser =
            await _googleSignIn.signInSilently();
        if (silentUser != null) {
          final GoogleSignInAuthentication googleAuth =
              await silentUser.authentication;
          _profile = ByokUserProfile(
            email: silentUser.email,
            displayName: silentUser.displayName,
            accessToken: googleAuth.accessToken ?? savedToken,
            userElevenLabsKey: _profile!.userElevenLabsKey,
            naverClientId: _profile!.naverClientId,
            naverClientSecret: _profile!.naverClientSecret,
            isMockSession: false,
          );
          await _persistCurrentProfile();
          debugPrint('[BYOK] Silent Google sign-in restored session.');
        }
      } on Object catch (error) {
        debugPrint('[BYOK] Silent sign-in skipped, using saved token: $error');
      }
    } else {
      debugPrint('[BYOK] Restored mock Google session from vault.');
    }

    await NaverMapBootstrapService.instance.initializeFromAuth(authService: this);
  }

  Future<AuthSignInResult> _activateMockSession({
    String? email,
    String? displayName,
    String? accessToken,
  }) async {
    debugPrint('[BYOK_MOCK]: Симуляция авторизации Google');
    await _activateAuthenticatedSession(
      email: email ?? 'byok.mock.user@gmail.com',
      displayName: displayName ?? 'BYOK Mock User',
      accessToken: accessToken ?? mockAccessToken,
      isMockSession: true,
    );
    return const AuthSignInResult(success: true, isMockSession: true);
  }

  Future<void> _activateAuthenticatedSession({
    required String? email,
    required String? displayName,
    required String accessToken,
    required bool isMockSession,
  }) async {
    final Map<String, dynamic> snapshot = _vault.readSessionSnapshot();
    _profile = ByokUserProfile(
      email: email,
      displayName: displayName,
      accessToken: accessToken,
      userElevenLabsKey: _profile?.userElevenLabsKey ??
          snapshot[ByokVaultRepository.userElevenLabsKeyKey] as String?,
      naverClientId: _profile?.naverClientId ??
          snapshot[ByokVaultRepository.naverClientIdKey] as String?,
      naverClientSecret: _profile?.naverClientSecret ??
          snapshot[ByokVaultRepository.naverClientSecretKey] as String?,
      isMockSession: isMockSession,
    );
    await _persistCurrentProfile();
    await NaverMapBootstrapService.instance.initializeFromAuth(authService: this);
  }

  Future<void> _persistCurrentProfile() async {
    final ByokUserProfile? profile = _profile;
    if (profile == null) {
      return;
    }
    await _vault.saveSession(
      isLoggedIn: profile.hasGoogleAccessToken,
      accessToken: profile.accessToken,
      email: profile.email,
      displayName: profile.displayName,
      isMockSession: profile.isMockSession,
      userElevenLabsKey: profile.userElevenLabsKey,
      naverClientId: profile.naverClientId,
      naverClientSecret: profile.naverClientSecret,
    );
  }

  ByokUserProfile? _ensureMutableProfile() {
    if (_profile != null) {
      return _profile;
    }
    if (!_vault.isLoggedIn) {
      return null;
    }
    final Map<String, dynamic> snapshot = _vault.readSessionSnapshot();
    _profile = ByokUserProfile(
      email: snapshot[ByokVaultRepository.emailKey] as String?,
      displayName: snapshot[ByokVaultRepository.displayNameKey] as String?,
      accessToken: snapshot[ByokVaultRepository.accessTokenKey] as String?,
      userElevenLabsKey:
          snapshot[ByokVaultRepository.userElevenLabsKeyKey] as String?,
      naverClientId: snapshot[ByokVaultRepository.naverClientIdKey] as String?,
      naverClientSecret:
          snapshot[ByokVaultRepository.naverClientSecretKey] as String?,
      isMockSession:
          snapshot[ByokVaultRepository.isMockSessionKey] as bool? ?? false,
    );
    return _profile;
  }

  String? _normalizeOptional(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
