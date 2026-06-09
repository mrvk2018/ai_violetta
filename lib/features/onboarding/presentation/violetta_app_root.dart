import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:violetta_app/features/auth/auth_screen.dart';
import 'package:violetta_app/features/auth/auth_service.dart';
import 'package:violetta_app/features/avatar/presentation/screens/violetta_debug_screen.dart';
import 'package:violetta_app/features/main_hud/presentation/screens/hud_main_screen.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_controller.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_scope.dart';
import 'package:violetta_app/features/onboarding/data/repositories/onboarding_vault_repository.dart';
import 'package:violetta_app/features/onboarding/presentation/screens/violetta_onboarding_wizard.dart';

class ViolettaAppRoot extends StatefulWidget {
  const ViolettaAppRoot({super.key});

  @override
  State<ViolettaAppRoot> createState() => _ViolettaAppRootState();
}

class _ViolettaAppRootState extends State<ViolettaAppRoot> {
  /// TEMP: skip onboarding/HUD and open avatar debug on web until Windows toolchain is ready.
  static const bool _kTempLaunchAvatarDebug = false;

  final OnboardingVaultRepository _onboardingVault = OnboardingVaultRepository();
  final AuthService _authService = AuthService.instance;
  late final ViolettaLocaleController _localeController;

  bool _isReady = false;
  bool _isAuthenticated = false;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _localeController = ViolettaLocaleController(_onboardingVault);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _authService.init();
    await _onboardingVault.init();
    await _localeController.loadPersistedLocale();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAuthenticated = _authService.isAuthenticated;
      _showOnboarding = _onboardingVault.isFirstLaunch;
      _isReady = true;
    });
  }

  void _onSignedIn() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  void _completeOnboarding() {
    setState(() {
      _showOnboarding = false;
    });
  }

  Widget _buildLoadingShell() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF141920),
        body: Center(
          child: CircularProgressIndicator(
            color: const Color(0xFF00F5FF).withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return _buildLoadingShell();
    }

    if (!_isAuthenticated) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AuthScreen(
          authService: _authService,
          onSignedIn: _onSignedIn,
        ),
      );
    }

    return ViolettaLocaleScope(
      controller: _localeController,
      child: ListenableBuilder(
        listenable: _localeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: _localeController.flutterLocale,
            home: _kTempLaunchAvatarDebug
                ? const ViolettaDebugScreen()
                : _showOnboarding
                    ? ViolettaOnboardingWizard(
                        vault: _onboardingVault,
                        localeController: _localeController,
                        onCompleted: _completeOnboarding,
                      )
                    : const HudMainScreen(),
            routes: <String, WidgetBuilder>{
              if (kDebugMode) '/avatar-debug': (_) => const ViolettaDebugScreen(),
            },
          );
        },
      ),
    );
  }
}
