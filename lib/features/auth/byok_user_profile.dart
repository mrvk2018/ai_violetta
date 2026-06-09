/// BYOK user session: Google OAuth token + optional premium API keys.
class ByokUserProfile {
  ByokUserProfile({
    this.email,
    this.displayName,
    this.accessToken,
    this.userElevenLabsKey,
    this.naverClientId,
    this.naverClientSecret,
    this.isMockSession = false,
  });

  final String? email;
  final String? displayName;
  String? accessToken;
  String? userElevenLabsKey;
  String? naverClientId;
  String? naverClientSecret;
  final bool isMockSession;

  bool get hasGoogleAccessToken =>
      accessToken != null && accessToken!.trim().isNotEmpty;

  bool get hasElevenLabsKey =>
      userElevenLabsKey != null && userElevenLabsKey!.trim().isNotEmpty;

  bool get hasNaverKeys =>
      naverClientId != null &&
      naverClientId!.trim().isNotEmpty &&
      naverClientSecret != null &&
      naverClientSecret!.trim().isNotEmpty;
}
