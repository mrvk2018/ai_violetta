import 'package:hive_flutter/hive_flutter.dart';

/// Encrypted Hive vault for BYOK credentials and auth persistence.
class ByokVaultRepository {
  ByokVaultRepository._();

  static final ByokVaultRepository instance = ByokVaultRepository._();

  static const String boxName = 'byok_vault';

  static const String isLoggedInKey = 'isLoggedIn';
  static const String accessTokenKey = 'accessToken';
  static const String emailKey = 'email';
  static const String displayNameKey = 'displayName';
  static const String isMockSessionKey = 'isMockSession';
  static const String userElevenLabsKeyKey = 'userElevenLabsKey';
  static const String naverClientIdKey = 'naverClientId';
  static const String naverClientSecretKey = 'naverClientSecret';

  /// Same test key as messages_box (AES-256).
  static const List<int> encryptionKey = <int>[
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
  ];

  Box<dynamic>? _box;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    _box = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    _isInitialized = true;
  }

  bool get isLoggedIn =>
      (_box?.get(isLoggedInKey, defaultValue: false) as bool?) ?? false;

  String? _readString(String key) {
    final dynamic value = _box?.get(key);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Map<String, dynamic> readSessionSnapshot() {
    _ensureReady();
    return <String, dynamic>{
      isLoggedInKey: isLoggedIn,
      accessTokenKey: _readString(accessTokenKey),
      emailKey: _readString(emailKey),
      displayNameKey: _readString(displayNameKey),
      isMockSessionKey:
          (_box!.get(isMockSessionKey, defaultValue: false) as bool?) ?? false,
      userElevenLabsKeyKey: _readString(userElevenLabsKeyKey),
      naverClientIdKey: _readString(naverClientIdKey),
      naverClientSecretKey: _readString(naverClientSecretKey),
    };
  }

  Future<void> saveSession({
    required bool isLoggedIn,
    String? accessToken,
    String? email,
    String? displayName,
    bool isMockSession = false,
    String? userElevenLabsKey,
    String? naverClientId,
    String? naverClientSecret,
  }) async {
    _ensureReady();
    await _box!.put(isLoggedInKey, isLoggedIn);
    await _putOptional(accessTokenKey, accessToken);
    await _putOptional(emailKey, email);
    await _putOptional(displayNameKey, displayName);
    await _box!.put(isMockSessionKey, isMockSession);
    await _putOptional(userElevenLabsKeyKey, userElevenLabsKey);
    await _putOptional(naverClientIdKey, naverClientId);
    await _putOptional(naverClientSecretKey, naverClientSecret);
  }

  Future<void> saveByokKeys({
    String? userElevenLabsKey,
    String? naverClientId,
    String? naverClientSecret,
  }) async {
    _ensureReady();
    await _putOptional(userElevenLabsKeyKey, userElevenLabsKey);
    await _putOptional(naverClientIdKey, naverClientId);
    await _putOptional(naverClientSecretKey, naverClientSecret);
  }

  Future<void> clearSession() async {
    _ensureReady();
    await _box!.clear();
  }

  Future<void> _putOptional(String key, String? value) async {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _box!.delete(key);
      return;
    }
    await _box!.put(key, trimmed);
  }

  void _ensureReady() {
    if (_box == null) {
      throw StateError('ByokVaultRepository.init() must be called first.');
    }
  }
}
