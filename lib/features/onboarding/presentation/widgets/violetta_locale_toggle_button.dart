import 'package:flutter/material.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_scope.dart';

class ViolettaLocaleToggleButton extends StatelessWidget {
  final VoidCallback onToggle;

  const ViolettaLocaleToggleButton({
    super.key,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final controller = ViolettaLocaleScope.of(context);
    final bool isKorean = controller.locale.isKorean;
    const Color neonCyan = Color(0xFF00F5FF);
    const Color neonPink = Color(0xFFFF4FCB);
    final Color accent = isKorean ? neonPink : neonCyan;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.75)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.translate_rounded, color: accent, size: 16),
              const SizedBox(width: 6),
              Text(
                'RU/KO',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  controller.localeToggleLabel,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
