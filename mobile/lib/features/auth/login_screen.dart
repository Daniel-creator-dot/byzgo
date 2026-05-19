import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/env.dart';
import '../../core/session.dart';
import '../../models/role.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_preloader.dart';
import '../../shared/widgets/ride_map_background.dart';
import '../../shared/widgets/ride_ui.dart';
import 'auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  AppRole _signupRole = AppRole.customer;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<AuthRepository>();
      final session = context.read<Session>();
      final result = await repo.login(
        email: _email.text,
        password: _password.text,
      );
      await session.setSession(token: result.token, user: result.user);
      if (!mounted) return;
      context.go(_homePathFor(result.user.role));
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<AuthRepository>();
      final session = context.read<Session>();
      final result = await repo.signInWithGoogle(role: _signupRole);
      await session.setSession(token: result.token, user: result.user);
      if (!mounted) return;
      context.go(_homePathFor(result.user.role));
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _homePathFor(AppRole role) {
    switch (role) {
      case AppRole.customer:
        return '/customer';
      case AppRole.rider:
        return '/rider';
      case AppRole.vendor:
        return '/vendor';
      case AppRole.admin:
        return '/admin';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BytzGoTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RideMapBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/branding/preloader.png',
                    width: 220,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Bike delivery,\non demand.',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: BytzGoTheme.textMuted,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: RideSheet(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Sign in', style: BytzGoTheme.sheetTitle()),
                    const SizedBox(height: 6),
                    Text(
                      'Book deliveries or drive as a rider',
                      style: BytzGoTheme.sheetBody(14),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BytzGoTheme.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: BytzGoTheme.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: BytzGoTheme.sheetText),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        labelStyle: BytzGoTheme.sheetBody(),
                        filled: true,
                        fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || !v.contains('@')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      style: const TextStyle(color: BytzGoTheme.sheetText),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: BytzGoTheme.sheetBody(),
                        filled: true,
                        fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                            color: BytzGoTheme.sheetMuted,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return 'At least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AppRole>(
                      initialValue: _signupRole,
                      dropdownColor: BytzGoTheme.sheetBg,
                      decoration: InputDecoration(
                        labelText: 'I am a',
                        labelStyle: BytzGoTheme.sheetBody(),
                        filled: true,
                        fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: AppRole.values
                          .where((r) => r != AppRole.admin)
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                r == AppRole.customer
                                    ? 'Customer — send packages'
                                    : r == AppRole.rider
                                        ? 'Rider — deliver on bike'
                                        : r.label,
                                style: const TextStyle(color: BytzGoTheme.sheetText),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _signupRole = v);
                      },
                    ),
                    const SizedBox(height: 20),
                    RidePrimaryButton(
                      label: 'Continue',
                      loading: _loading,
                      onPressed: _submitEmailLogin,
                    ),
                    if (Env.isGoogleSignInEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : _submitGoogle,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: BytzGoTheme.sheetDivider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: BytzGoTheme.sheetText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            const Positioned.fill(
              child: BytzPreloaderOverlay(message: 'Signing in…'),
            ),
        ],
      ),
    );
  }
}
