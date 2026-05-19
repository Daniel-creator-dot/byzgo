import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/env.dart';
import '../../core/session.dart';
import '../../models/role.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_brand.dart';
import '../../shared/widgets/bytz_preloader.dart';
import '../../shared/widgets/ride_ui.dart';
import 'auth_repository.dart';
import 'ghana_phone.dart';

enum _AuthMode { signIn, signUp, forgotPhone, forgotReset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  AppRole _signupRole = AppRole.customer;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _otp.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<AuthRepository>();
      final session = context.read<Session>();

      switch (_mode) {
        case _AuthMode.signIn:
          final result = await repo.login(
            email: _email.text,
            password: _password.text,
          );
          await session.setSession(token: result.token, user: result.user);
          if (!mounted) return;
          context.go(_homePathFor(result.user.role));
          break;

        case _AuthMode.signUp:
          if (_signupRole == AppRole.customer) {
            if (!isValidGhanaPhone(_phone.text)) {
              setState(() => _error = 'Enter a valid Ghana phone (e.g. 0247904675).');
              return;
            }
            await repo.sendSignupOtp(phone: _phone.text, email: _email.text);
            if (!mounted) return;
            final otp = await _promptOtp(
              title: 'Verify your phone',
              subtitle: 'Enter the 6-digit code sent to ${_phone.text} via SMS.',
              onResend: () => repo.sendSignupOtp(
                phone: _phone.text,
                email: _email.text,
              ),
            );
            if (otp == null || !mounted) return;
            await repo.verifyOtp(
              phone: _phone.text,
              otp: otp,
              purpose: 'signup_verify',
            );
            final registered = await repo.register(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              role: _signupRole,
              phone: _phone.text,
              otp: otp,
            );
            await session.setSession(
              token: registered.token,
              user: registered.user,
            );
            if (!mounted) return;
            context.go(_homePathFor(registered.user.role));
          } else {
            final registered = await repo.register(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              role: _signupRole,
              phone: _phone.text.isNotEmpty ? _phone.text : null,
            );
            await session.setSession(
              token: registered.token,
              user: registered.user,
            );
            if (!mounted) return;
            context.go(_homePathFor(registered.user.role));
          }
          break;

        case _AuthMode.forgotPhone:
          if (!isValidGhanaPhone(_phone.text)) {
            setState(() => _error = 'Enter a valid Ghana phone (e.g. 0247904675).');
            return;
          }
          await repo.sendForgotPasswordOtp(_phone.text);
          if (!mounted) return;
          setState(() {
            _mode = _AuthMode.forgotReset;
            _otp.clear();
            _newPassword.clear();
            _confirmPassword.clear();
          });
          break;

        case _AuthMode.forgotReset:
          if (_otp.text.trim().length != 6) {
            setState(() => _error = 'Enter the 6-digit SMS code.');
            return;
          }
          if (_newPassword.text != _confirmPassword.text) {
            setState(() => _error = 'Passwords do not match.');
            return;
          }
          await repo.resetPasswordWithOtp(
            phone: _phone.text,
            otp: _otp.text.trim(),
            newPassword: _newPassword.text,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated. Sign in with your new password.')),
          );
          _setMode(_AuthMode.signIn);
          break;
      }
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _promptOtp({
    required String title,
    required String subtitle,
    required Future<void> Function() onResend,
  }) async {
    _otp.clear();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var resending = false;
        String? localError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: BytzGoTheme.sheetBg,
              title: Text(title, style: BytzGoTheme.sheetTitle(18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(subtitle, style: BytzGoTheme.sheetBody(13)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otp,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: '6-digit code',
                      filled: true,
                      fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                    ),
                  ),
                  if (localError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        localError!,
                        style: const TextStyle(color: BytzGoTheme.danger, fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: resending
                        ? null
                        : () async {
                            setDialogState(() {
                              resending = true;
                              localError = null;
                            });
                            try {
                              await onResend();
                            } catch (e) {
                              setDialogState(() {
                                localError = AuthRepository.errorMessage(e);
                              });
                            } finally {
                              setDialogState(() => resending = false);
                            }
                          },
                    child: Text(resending ? 'Sending…' : 'Resend code'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final code = _otp.text.trim();
                    if (code.length != 6) {
                      setDialogState(() => localError = 'Enter the 6-digit code.');
                      return;
                    }
                    Navigator.pop(ctx, code);
                  },
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
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

  String get _primaryLabel {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in';
      case _AuthMode.signUp:
        return 'Continue';
      case _AuthMode.forgotPhone:
        return 'Send reset code';
      case _AuthMode.forgotReset:
        return 'Reset password';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForgot = _mode == _AuthMode.forgotPhone || _mode == _AuthMode.forgotReset;
    final isSignUp = _mode == _AuthMode.signUp;

    return Scaffold(
      backgroundColor: BytzGoTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BrandHeroBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BytzGoLogo(fontSize: 42),
                  const SizedBox(height: 10),
                  Text(
                    isForgot
                        ? 'Reset via SMS'
                        : 'Fast bike delivery,\non demand.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.3,
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
                    Text(
                      isForgot
                          ? 'Recover password'
                          : isSignUp
                              ? 'Create account'
                              : 'Sign in',
                      style: BytzGoTheme.sheetTitle(),
                    ),
                    if (!isForgot) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Sign in'),
                              selected: _mode == _AuthMode.signIn,
                              onSelected: (_) => _setMode(_AuthMode.signIn),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Join'),
                              selected: _mode == _AuthMode.signUp,
                              onSelected: (_) => _setMode(_AuthMode.signUp),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    if (isSignUp) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _name,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('Full name'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Name required' : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (!isForgot)
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('Email'),
                        validator: (v) =>
                            v == null || !v.contains('@') ? 'Valid email required' : null,
                      ),
                    if (isSignUp || isForgot) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        readOnly: _mode == _AuthMode.forgotReset,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco(
                          isForgot ? 'Registered phone' : 'Phone (SMS verify)',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return isSignUp && _signupRole != AppRole.customer
                                ? null
                                : 'Phone required';
                          }
                          if (!isValidGhanaPhone(v)) {
                            return 'Use format 0247904675';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_mode == _AuthMode.forgotReset) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('6-digit SMS code'),
                        validator: (v) =>
                            v == null || v.length != 6 ? 'Enter 6-digit code' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPassword,
                        obscureText: _obscure,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('New password'),
                        validator: (v) =>
                            v == null || v.length < 6 ? 'Min 6 characters' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: _obscure,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('Confirm password'),
                        validator: (v) => v != _newPassword.text ? 'Passwords must match' : null,
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () async {
                                try {
                                  await context
                                      .read<AuthRepository>()
                                      .resendOtp(
                                        phone: _phone.text,
                                        purpose: 'forgot_password',
                                      );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('New reset code sent by SMS.'),
                                    ),
                                  );
                                } catch (e) {
                                  setState(() =>
                                      _error = AuthRepository.errorMessage(e));
                                }
                              },
                        child: const Text('Resend SMS code'),
                      ),
                    ],
                    if (!isForgot) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        decoration: _fieldDeco('Password').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off,
                              color: BytzGoTheme.sheetMuted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.length < 6 ? 'Min 6 characters' : null,
                      ),
                    ],
                    if (isSignUp) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AppRole>(
                        initialValue: _signupRole,
                        dropdownColor: BytzGoTheme.sheetBg,
                        decoration: _fieldDeco('I am a'),
                        items: AppRole.values
                            .where((r) => r != AppRole.admin)
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r.label,
                                    style: const TextStyle(
                                        color: BytzGoTheme.sheetText)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _signupRole = v);
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    RidePrimaryButton(
                      label: _primaryLabel,
                      loading: _loading,
                      color: BytzGoTheme.accent,
                      onPressed: _submit,
                    ),
                    if (_mode == _AuthMode.signIn) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _setMode(_AuthMode.forgotPhone),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                    if (isForgot)
                      TextButton(
                        onPressed: () => _setMode(_AuthMode.signIn),
                        child: const Text('Back to sign in'),
                      ),
                    if (!isForgot && Env.isGoogleSignInEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : _submitGoogle,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: BytzGoTheme.brandBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: BytzGoTheme.brandBlue,
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
              child: BytzPreloaderOverlay(message: 'Please wait…'),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: BytzGoTheme.sheetBody(),
      filled: true,
      fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BytzGoTheme.brandBlue, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
