import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_controller.dart';
import 'package:violetta_app/features/onboarding/data/repositories/onboarding_vault_repository.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';
import 'package:violetta_app/features/onboarding/presentation/copy/onboarding_copy.dart';
import 'package:violetta_app/features/voice_control/data/services/native_bridge_service.dart';

class ViolettaOnboardingWizard extends StatefulWidget {
  final OnboardingVaultRepository vault;
  final ViolettaLocaleController localeController;
  final VoidCallback onCompleted;

  const ViolettaOnboardingWizard({
    super.key,
    required this.vault,
    required this.localeController,
    required this.onCompleted,
  });

  @override
  State<ViolettaOnboardingWizard> createState() =>
      _ViolettaOnboardingWizardState();
}

class _ViolettaOnboardingWizardState extends State<ViolettaOnboardingWizard>
    with WidgetsBindingObserver {
  static const Color _background = Color(0xFF141920);
  static const Color _panel = Color(0xFF1C222B);
  static const Color _neonCyan = Color(0xFF00F5FF);
  static const Color _neonPink = Color(0xFFFF4FCB);

  final PageController _pageController = PageController();
  final ScrollController _policyScrollController = ScrollController();

  int _currentStep = 0;
  bool _policyScrolledToEnd = false;
  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _accessibilityEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _policyScrollController.addListener(_handlePolicyScroll);
    widget.localeController.addListener(_handleLocaleChanged);
    _refreshPermissionStates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.localeController.removeListener(_handleLocaleChanged);
    _policyScrollController.removeListener(_handlePolicyScroll);
    _policyScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStates();
    }
  }

  void _handleLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handlePolicyScroll() {
    if (_policyScrolledToEnd || !_policyScrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _policyScrollController.position;
    if (position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 12) {
      setState(() {
        _policyScrolledToEnd = true;
      });
    }
  }

  void _evaluatePolicyScrollRequirement() {
    if (_policyScrolledToEnd || !_policyScrollController.hasClients) {
      return;
    }
    if (_policyScrollController.position.maxScrollExtent <= 0) {
      setState(() {
        _policyScrolledToEnd = true;
      });
    }
  }

  OnboardingCopy get _copy => OnboardingCopy(widget.localeController.locale);

  Future<void> _refreshPermissionStates() async {
    final bool cameraGranted = await Permission.camera.isGranted;
    final bool microphoneGranted = await Permission.microphone.isGranted;
    final bool accessibilityEnabled =
        await NativeBridgeService.isAccessibilityServiceEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraGranted = cameraGranted;
      _microphoneGranted = microphoneGranted;
      _accessibilityEnabled = accessibilityEnabled;
    });
  }

  Future<void> _selectLocale(ViolettaAppLocale locale) async {
    await widget.localeController.setLocale(locale);
    setState(() {
      _policyScrolledToEnd = false;
    });
    if (_policyScrollController.hasClients) {
      _policyScrollController.jumpTo(0);
    }
    _goToStep(1);
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _requestCamera() async {
    await Permission.camera.request();
    await _refreshPermissionStates();
  }

  Future<void> _requestMicrophone() async {
    await Permission.microphone.request();
    await _refreshPermissionStates();
  }

  Future<void> _openAccessibilitySettings() async {
    await NativeBridgeService.openAccessibilitySettings();
  }

  Future<void> _finishOnboarding() async {
    await widget.vault.completeOnboarding();
    widget.onCompleted();
  }

  bool get _canFinish =>
      _cameraGranted && _microphoneGranted && _accessibilityEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (int index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: <Widget>[
                  _buildLanguageStep(),
                  _buildPrivacyStep(),
                  _buildPermissionsStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _copy.wizardTitle,
            style: const TextStyle(
              color: _neonCyan,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List<Widget>.generate(3, (int index) {
              final bool active = index <= _currentStep;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: active
                        ? (index == 1 ? _neonPink : _neonCyan)
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageStep() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _copy.stepLanguageTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _copy.stepLanguageSubtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const Spacer(),
          _buildLocaleButton(
            label: 'Русский',
            locale: ViolettaAppLocale.russian,
            accent: _neonCyan,
          ),
          const SizedBox(height: 14),
          _buildLocaleButton(
            label: '한국어',
            locale: ViolettaAppLocale.korean,
            accent: _neonPink,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLocaleButton({
    required String label,
    required ViolettaAppLocale locale,
    required Color accent,
  }) {
    final bool selected = widget.localeController.locale == locale;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: () => _selectLocale(locale),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(
            color: selected ? accent : accent.withValues(alpha: 0.45),
            width: selected ? 2 : 1.2,
          ),
          backgroundColor: selected ? accent.withValues(alpha: 0.12) : _panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildPrivacyStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _copy.stepPrivacyTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _copy.stepPrivacyHint,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _neonPink.withValues(alpha: 0.35)),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                controller: _policyScrollController,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _evaluatePolicyScrollRequirement();
                    });
                    return SingleChildScrollView(
                      controller: _policyScrollController,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _copy.privacyPolicyText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.45,
                          fontSize: 13.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _policyScrolledToEnd ? () => _goToStep(2) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _neonPink.withValues(alpha: 0.9),
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _copy.acceptContinue,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _copy.stepPermissionsTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _copy.stepPermissionsSubtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 18),
          _buildPermissionRow(
            label: _copy.cameraLabel,
            granted: _cameraGranted,
            onAction: _requestCamera,
          ),
          const SizedBox(height: 12),
          _buildPermissionRow(
            label: _copy.microphoneLabel,
            granted: _microphoneGranted,
            onAction: _requestMicrophone,
          ),
          const SizedBox(height: 12),
          _buildPermissionRow(
            label: _copy.accessibilityLabel,
            granted: _accessibilityEnabled,
            actionLabel: _copy.openSettingsAction,
            onAction: _openAccessibilitySettings,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canFinish ? _finishOnboarding : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _neonCyan.withValues(alpha: 0.92),
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _copy.finishAction,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow({
    required String label,
    required bool granted,
    required Future<void> Function() onAction,
    String? actionLabel,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? const Color(0xFF47FF8A).withValues(alpha: 0.55)
              : _neonCyan.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(
              granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: granted ? const Color(0xFF47FF8A) : Colors.white38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: granted ? null : onAction,
              child: Text(actionLabel ?? _copy.grantAction),
            ),
          ],
        ),
      ),
    );
  }
}
