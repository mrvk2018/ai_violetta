import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final OnboardingVaultRepository _onboardingVault = OnboardingVaultRepository();
  late final ViolettaLocaleController _localeController;

  bool _isReady = false;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _localeController = ViolettaLocaleController(_onboardingVault);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _onboardingVault.init();
    await _localeController.loadPersistedLocale();
    if (!mounted) {
      return;
    }
    setState(() {
      _showOnboarding = _onboardingVault.isFirstLaunch;
      _isReady = true;
    });
  }

  void _completeOnboarding() {
    setState(() {
      _showOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
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

    return ViolettaLocaleScope(
      controller: _localeController,
      child: ListenableBuilder(
        listenable: _localeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: _localeController.flutterLocale,
            home: _showOnboarding
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
