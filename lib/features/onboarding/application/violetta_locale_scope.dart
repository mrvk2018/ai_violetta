import 'package:flutter/material.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_controller.dart';

class ViolettaLocaleScope extends InheritedNotifier<ViolettaLocaleController> {
  const ViolettaLocaleScope({
    super.key,
    required ViolettaLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static ViolettaLocaleController of(BuildContext context) {
    final ViolettaLocaleScope? scope =
        context.dependOnInheritedWidgetOfExactType<ViolettaLocaleScope>();
    assert(scope != null, 'ViolettaLocaleScope not found in widget tree');
    return scope!.notifier!;
  }
}
