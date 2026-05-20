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
import 'widgets/login_ui.dart';

enum _AuthMode { signIn, signUp, forgot }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  AppRole _signupRole = AppRole.customer;
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;
  String? _error;
  late final AnimationController _heroAnim;

  @override
  void initState() {
    super.initState();
    _heroAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    _login.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
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

  bool _isValidLoginId(String value) {
    final v = value.trim();
    if (v.contains('@')) return v.contains('.');
    return isValidGhanaPhone(v);
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
            login: _login.text,
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
          }
          final registered = await repo.register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            role: _signupRole,
            phone: _signupRole == AppRole.customer || _phone.text.isNotEmpty
                ? _phone.text
                : null,
          );
          await session.setSession(
            token: registered.token,
            user: registered.user,
          );
          if (!mounted) return;
          context.go(_homePathFor(registered.user.role));
          break;

        case _AuthMode.forgot:
          if (!isValidGhanaPhone(_phone.text)) {
            setState(() => _error = 'Enter a valid Ghana phone (e.g. 0247904675).');
            return;
          }
          if (_newPassword.text != _confirmPassword.text) {
            setState(() => _error = 'Passwords do not match.');
            return;
          }
          await repo.resetPassword(
            phone: _phone.text,
            email: _email.text,
            newPassword: _newPassword.text,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: BytzGoTheme.sheetText,
              content: const Text('Password updated. Sign in with your phone or email.'),
            ),
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

  Future<void> _submitGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthRepository>().signInWithGoogle();
      await context.read<Session>().setSession(
        token: result.token,
        user: result.user,
      );
      if (!mounted) return;
      context.go(_homePathFor(result.user.role));
    } catch (e) {
      final msg = AuthRepository.errorMessage(e);
      if (msg.toLowerCase().contains('cancel')) {
        return;
      }
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
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
        return 'Create account';
      case _AuthMode.forgot:
        return 'Reset password';
    }
  }

  String get _sheetTitle {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Welcome back';
      case _AuthMode.signUp:
        return 'Join BytzGo';
      case _AuthMode.forgot:
        return 'Recover password';
    }
  }

  String? get _sheetSubtitle {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in with phone, email, or Google';
      case _AuthMode.signUp:
        return 'Deliveries, rides, and shops in one app';
      case _AuthMode.forgot:
        return 'Use your registered phone and email';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForgot = _mode == _AuthMode.forgot;
    final isSignUp = _mode == _AuthMode.signUp;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: BytzGoTheme.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BrandHeroBackground(bottomFade: 0.82),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.08),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: _heroAnim, curve: Curves.easeOutCubic)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BytzGoLogo(fontSize: 44),
                      const SizedBox(height: 14),
                      Text(
                        isForgot
                            ? 'Reset your password'
                            : 'Fast bike delivery,\non demand.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.25,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (!isForgot) ...[
                        const SizedBox(height: 16),
                        const AuthHeroFeatures(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Theme(
              data: BytzGoTheme.sheetTheme(),
              child: RideSheet(
                maxHeightFraction: 0.78,
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8 + bottomPad),
                child: Form(
                  key: _formKey,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Column(
                      key: ValueKey(_mode),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AuthSheetHeader(
                          title: _sheetTitle,
                          subtitle: _sheetSubtitle,
                        ),
                        if (!isForgot) ...[
                          const SizedBox(height: 18),
                          AuthModeSegment(
                            signInSelected: _mode == _AuthMode.signIn,
                            onSignIn: () => _setMode(_AuthMode.signIn),
                            onJoin: () => _setMode(_AuthMode.signUp),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          AuthErrorBanner(
                            message: _error!,
                            onDismiss: () => setState(() => _error = null),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (isSignUp)
                          AuthTextField(
                            controller: _name,
                            label: 'Full name',
                            icon: Icons.person_outline_rounded,
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Name required' : null,
                          ),
                        if (isSignUp) const SizedBox(height: 12),
                        if (_mode == _AuthMode.signIn)
                          AuthTextField(
                            controller: _login,
                            label: 'Phone or email',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Phone or email required';
                              }
                              if (!_isValidLoginId(v)) {
                                return 'Use 024… or name@example.com';
                              }
                              return null;
                            },
                          ),
                        if (isSignUp || isForgot) ...[
                          AuthTextField(
                            controller: _email,
                            label: isForgot ? 'Registered email' : 'Email',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) =>
                                v == null || !v.contains('@') ? 'Valid email required' : null,
                          ),
                          const SizedBox(height: 12),
                          AuthTextField(
                            controller: _phone,
                            label: isForgot ? 'Registered phone' : 'Phone number',
                            icon: Icons.phone_android_rounded,
                            keyboardType: TextInputType.phone,
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
                        if (isForgot) ...[
                          const SizedBox(height: 12),
                          AuthTextField(
                            controller: _newPassword,
                            label: 'New password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            validator: (v) =>
                                v == null || v.length < 6 ? 'Min 6 characters' : null,
                          ),
                          const SizedBox(height: 12),
                          AuthTextField(
                            controller: _confirmPassword,
                            label: 'Confirm password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: BytzGoTheme.sheetMuted,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            validator: (v) =>
                                v != _confirmPassword.text ? 'Passwords must match' : null,
                          ),
                        ],
                        if (!isForgot) ...[
                          const SizedBox(height: 12),
                          AuthTextField(
                            controller: _password,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: BytzGoTheme.sheetMuted,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
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
                            decoration: const InputDecoration(
                              labelText: 'I am a',
                              filled: true,
                              fillColor: Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(14)),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: AppRole.values
                                .where((r) => r != AppRole.admin)
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(
                                      r.label,
                                      style: const TextStyle(
                                        color: BytzGoTheme.sheetText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _signupRole = v);
                            },
                          ),
                        ],
                        const SizedBox(height: 22),
                        RidePrimaryButton(
                          label: _primaryLabel,
                          loading: _loading,
                          icon: _mode == _AuthMode.signIn
                              ? Icons.arrow_forward_rounded
                              : Icons.check_rounded,
                          color: BytzGoTheme.accent,
                          onPressed: _submit,
                        ),
                        if (_mode == _AuthMode.signIn) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _setMode(_AuthMode.forgot),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                        if (isForgot)
                          TextButton(
                            onPressed: () => _setMode(_AuthMode.signIn),
                            child: const Text('Back to sign in'),
                          ),
                        if (!isForgot && Env.isGoogleSignInEnabled) ...[
                          const SizedBox(height: 8),
                          const AuthOrDivider(),
                          const SizedBox(height: 14),
                          AuthGoogleButton(
                            onPressed: _loading ? null : _submitGoogle,
                            loading: _googleLoading,
                          ),
                        ],
                        const SizedBox(height: 18),
                        const AuthPartnerFooter(),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
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
}
