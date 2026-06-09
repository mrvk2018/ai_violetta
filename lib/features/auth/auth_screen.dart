import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';

class AuthScreen extends StatefulWidget {
  AuthScreen({
    super.key,
    AuthService? authService,
    this.onSignedIn,
  }) : _authService = authService ?? AuthService.instance;

  final AuthService _authService;
  final VoidCallback? onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _onSignInPressed() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final AuthSignInResult result =
          await widget._authService.signInWithGoogle();
      if (!mounted) {
        return;
      }
      if (result.cancelled) {
        return;
      }
      if (result.success) {
        widget.onSignedIn?.call();
        return;
      }
      setState(() {
        _errorMessage = 'Не удалось войти. Проверьте сеть и повторите попытку.';
      });
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.message ?? 'Ошибка авторизации. Попробуйте снова.';
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Не удалось войти. Проверьте сеть и повторите попытку.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF141920),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Violetta AI',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF00F5FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Войдите через Google — ваши личные квоты ИИ подключатся автоматически.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 32),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loader'),
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Color(0xFF00F5FF),
                          ),
                        )
                      : SizedBox(
                          key: const ValueKey('button'),
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _onSignInPressed,
                            icon: const Icon(Icons.login_rounded),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                'Войти с Google',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              backgroundColor: const Color(0xFF00F5FF),
                              foregroundColor: const Color(0xFF141920),
                              elevation: 1,
                            ),
                          ),
                        ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
