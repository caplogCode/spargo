import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../data/repositories/firebase_app_repository.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_language_provider.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../theme/app_colors.dart';

enum LoginScreenMode { login, signup }

class _LoginCopy {
  const _LoginCopy({
    required this.welcome,
    required this.subtitle,
    required this.emailLabel,
    required this.emailHint,
    required this.passwordLabel,
    required this.passwordHint,
    required this.remember,
    required this.forgot,
    required this.submit,
    required this.submitting,
    required this.sending,
    required this.or,
    required this.google,
    required this.apple,
    required this.emptyFields,
    required this.enterEmailFirst,
    required this.resetSent,
  });

  final String welcome;
  final String subtitle;
  final String emailLabel;
  final String emailHint;
  final String passwordLabel;
  final String passwordHint;
  final String remember;
  final String forgot;
  final String submit;
  final String submitting;
  final String sending;
  final String or;
  final String google;
  final String apple;
  final String emptyFields;
  final String enterEmailFirst;
  final String resetSent;

  static _LoginCopy forCode(String code) {
    return switch (code.toLowerCase()) {
      'en' => const _LoginCopy(
        welcome: 'Welcome\nback!',
        subtitle: 'Good to see you again.',
        emailLabel: 'Email address',
        emailHint: 'Your email address',
        passwordLabel: 'Password',
        passwordHint: 'Your password',
        remember: 'Keep me signed in',
        forgot: 'Forgot password?',
        submit: 'Sign in',
        submitting: 'One moment...',
        sending: 'Sending...',
        or: 'OR',
        google: 'Continue with Google',
        apple: 'Continue with Apple',
        emptyFields: 'Please enter email and password.',
        enterEmailFirst: 'Please enter your email first.',
        resetSent: 'Reset link has been sent.',
      ),
      _ => const _LoginCopy(
        welcome: 'Willkommen\nzur\u00fcck!',
        subtitle: 'Sch\u00f6n, dass du wieder da bist.',
        emailLabel: 'E-Mail Adresse',
        emailHint: 'Deine E-Mail Adresse',
        passwordLabel: 'Passwort',
        passwordHint: 'Dein Passwort',
        remember: 'Angemeldet bleiben',
        forgot: 'Passwort vergessen?',
        submit: 'Einloggen',
        submitting: 'Einen Moment...',
        sending: 'Wird gesendet...',
        or: 'ODER',
        google: 'Mit Google fortfahren',
        apple: 'Mit Apple fortfahren',
        emptyFields: 'Bitte gib E-Mail und Passwort ein.',
        enterEmailFirst: 'Bitte gib zuerst deine E-Mail ein.',
        resetSent: 'Reset-Link wurde gesendet.',
      ),
    };
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.initialMode = LoginScreenMode.login,
    this.embedded = false,
    this.onAuthenticated,
  });

  final LoginScreenMode initialMode;
  final bool embedded;
  final Future<bool> Function(SessionState session)? onAuthenticated;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(milliseconds: 900),
  );

  bool _submitting = false;
  bool _sendingReset = false;
  bool _routingAfterSubmit = false;
  bool _rememberMe = true;

  String get _languageCode =>
      ref.read(appLanguageControllerProvider).languageCode;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageControllerProvider);
    final copy = _LoginCopy.forCode(language.languageCode);
    final content = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: const Color(0xFFFCFAFD),
        systemNavigationBarColor: const Color(0xFFFCFAFD),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Stack(
          children: <Widget>[
            _LoginBackdrop(
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = _LoginLayoutMetrics.from(constraints);
                    return Center(
                      child: SizedBox(
                        width: metrics.width,
                        height: metrics.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Positioned(
                              left: metrics.logoLeft,
                              top: metrics.logoTop,
                              child: Image.asset(
                                'assets/branding/spargo_onboarding_logo.png',
                                width: metrics.logoWidth,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Positioned(
                              right: metrics.sideInset,
                              top: metrics.languageTop,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  AppBackButton(onTap: _handleBack),
                                  const SizedBox(width: 8),
                                  _LanguagePill(
                                    languageCode: language.languageCode,
                                    onTap: _showLanguageSheet,
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: metrics.sideInset,
                              right: metrics.sideInset,
                              top: metrics.titleTop,
                              child: _LoginTitleBlock(
                                compact: metrics.compact,
                                copy: copy,
                              ),
                            ),
                            Positioned(
                              left: metrics.cardInset,
                              right: metrics.cardInset,
                              top: metrics.cardTop,
                              height: metrics.cardHeight,
                              child: _buildLoginCard(metrics, copy),
                            ),
                            Positioned(
                              left: metrics.cardInset + 22,
                              right: metrics.cardInset + 22,
                              top: metrics.dividerTop,
                              child: _LoginDivider(label: copy.or),
                            ),
                            Positioned(
                              left: metrics.cardInset,
                              right: metrics.cardInset,
                              top: metrics.socialTop,
                              child: Column(
                                children: <Widget>[
                                  _SocialLoginButton(
                                    label: copy.google,
                                    onTap: _submitting
                                        ? null
                                        : _submitGoogleLogin,
                                    compact: metrics.compact,
                                    type: _SocialLoginType.google,
                                  ),
                                  SizedBox(height: metrics.compact ? 9 : 12),
                                  _SocialLoginButton(
                                    label: copy.apple,
                                    onTap: _submitting
                                        ? null
                                        : _submitAppleLogin,
                                    compact: metrics.compact,
                                    type: _SocialLoginType.apple,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.03,
                numberOfParticles: 24,
                gravity: 0.18,
                maxBlastForce: 20,
                minBlastForce: 7,
                colors: const <Color>[
                  AppColors.primary,
                  Color(0xFFFF86A0),
                  Color(0xFFFFC2D0),
                  Color(0xFFFFE2EA),
                  Colors.white,
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return Material(color: Colors.transparent, child: content);
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFFBFAFD),
      body: content,
    );
  }

  Widget _buildLoginCard(_LoginLayoutMetrics metrics, _LoginCopy copy) {
    return _LoginFormCard(
      compact: metrics.compact,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tiny = constraints.maxHeight < 390;
          final sectionGap = tiny ? 12.0 : 18.0;
          final actionGap = tiny ? 11.0 : 18.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PremiumLoginInput(
                controller: _emailController,
                label: copy.emailLabel,
                hintText: copy.emailHint,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                compact: tiny,
              ),
              SizedBox(height: sectionGap),
              _PremiumLoginInput(
                controller: _passwordController,
                label: copy.passwordLabel,
                hintText: copy.passwordHint,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                compact: tiny,
                onSubmitted: (_) => _submitEmailLogin(),
              ),
              SizedBox(height: tiny ? 10 : 15),
              Row(
                children: <Widget>[
                  _RememberCheck(
                    checked: _rememberMe,
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      copy.remember,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6D6871),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _sendingReset ? null : _handleForgotPassword,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        _sendingReset ? copy.sending : copy.forgot,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _PremiumLoginButton(
                label: _submitting ? copy.submitting : copy.submit,
                onTap: _submitting ? null : _submitEmailLogin,
                compact: tiny,
              ),
              SizedBox(height: actionGap),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitEmailLogin() async {
    if (_submitting) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showErrorToast(_LoginCopy.forCode(_languageCode).emptyFields);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .login(email: email, password: password);
      if (result.requiresApproval) {
        throw StateError(
          'Neues ${result.deviceLabel} erkannt. Bitte best\u00e4tige zuerst die Mail an ${result.email}.',
        );
      }
      await _handleSubmitSuccess();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitGoogleLogin() async {
    await _submitSocialLogin(
      () => ref.read(sessionControllerProvider.notifier).loginWithGoogle(),
    );
  }

  Future<void> _submitAppleLogin() async {
    await _submitSocialLogin(
      () => ref.read(sessionControllerProvider.notifier).loginWithApple(),
    );
  }

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
  }

  Future<void> _showLanguageSheet() async {
    final currentCode = ref.read(appLanguageControllerProvider).languageCode;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (context) => _LanguageSheet(selectedCode: currentCode),
    );
    if (selected == null || selected == currentCode) {
      return;
    }
    await ref
        .read(appLanguageControllerProvider.notifier)
        .setLanguageCode(selected);
  }

  Future<void> _submitSocialLogin(
    Future<DeviceLoginResult> Function() action,
  ) async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final result = await action();
      if (result.requiresApproval) {
        throw StateError(
          'Neues ${result.deviceLabel} erkannt. Bitte best\u00e4tige zuerst die Mail an ${result.email}.',
        );
      }
      await _handleSubmitSuccess();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_sendingReset) {
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showErrorToast(_LoginCopy.forCode(_languageCode).enterEmailFirst);
      return;
    }

    setState(() {
      _sendingReset = true;
    });

    try {
      await ref.read(repositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        _LoginCopy.forCode(_languageCode).resetSent,
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _sendingReset = false);
      }
    }
  }

  Future<void> _handleSubmitSuccess() async {
    if (_routingAfterSubmit) {
      return;
    }
    _routingAfterSubmit = true;

    final callback = widget.onAuthenticated;
    if (callback != null) {
      final handled = await callback(ref.read(sessionControllerProvider));
      if (handled) {
        return;
      }
    }

    _confettiController.play();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted) {
      return;
    }

    await _routeAfterSubmit();
  }

  void _showErrorToast(String message) {
    if (!mounted) {
      return;
    }
    showAppToast(context, message);
  }

  Future<void> _routeAfterSubmit() async {
    final session = await _waitForResolvedSession();
    if (!mounted) {
      return;
    }

    if (session.isBusinessAccount &&
        (session.needsBusinessSetup || !(sessionAuthEmailVerified()))) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.businessOnboarding, (route) => false);
      return;
    }
    if (session.isBusinessAccount) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.businessDashboard, (route) => false);
      return;
    }

    final needsUserSetup = !session.userOnboardingComplete;
    if (needsUserSetup) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.locationPermission, (route) => false);
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.shell,
      (route) => false,
      arguments: const ShellArgs(),
    );
  }

  bool sessionAuthEmailVerified() {
    final authUser = ref.read(authUserProvider);
    return authUser != null && !authUser.isAnonymous && authUser.emailVerified;
  }

  Future<SessionState> _waitForResolvedSession() async {
    for (var attempt = 0; attempt < 30; attempt += 1) {
      if (!mounted) {
        return ref.read(sessionControllerProvider);
      }

      final authUser = ref.read(authUserProvider);
      final session = ref.read(sessionControllerProvider);
      final userRecord = ref
          .read(firebaseSessionUserRecordProvider)
          .valueOrNull;

      final sessionResolved =
          authUser != null &&
          userRecord != null &&
          session.isAuthenticated &&
          session.user.id == authUser.uid &&
          session.user.accountType == userRecord.user.accountType &&
          session.userOnboardingComplete == userRecord.onboardingCompleted &&
          session.businessOnboardingComplete ==
              userRecord.businessOnboardingComplete &&
          session.ownedBusinessId == userRecord.ownedBusinessId;

      if (sessionResolved) {
        return session;
      }

      await Future<void>.delayed(const Duration(milliseconds: 140));
    }

    return ref.read(sessionControllerProvider);
  }

  String _friendlyAuthError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      final english = _languageCode.toLowerCase() == 'en';
      return switch (error.code) {
        'invalid-email' =>
          english
              ? 'The email address is invalid.'
              : 'Die E-Mail-Adresse ist nicht g\u00fcltig.',
        'wrong-password' || 'invalid-credential' || 'user-not-found' =>
          english
              ? 'Email or password is incorrect.'
              : 'E-Mail oder Passwort stimmen nicht.',
        'popup-closed-by-user' =>
          english ? 'Sign-in was closed.' : 'Anmeldung wurde geschlossen.',
        'too-many-requests' =>
          english
              ? 'Too many attempts. Please try again later.'
              : 'Zu viele Versuche. Bitte kurz sp\u00e4ter nochmal.',
        'network-request-failed' =>
          english
              ? 'Network error. Please check your connection.'
              : 'Netzwerkfehler. Bitte pr\u00fcfe deine Verbindung.',
        'operation-not-allowed' =>
          english
              ? 'This sign-in method is not enabled in Firebase yet.'
              : 'Diese Anmeldemethode ist in Firebase noch nicht aktiviert.',
        _ =>
          error.message ??
              (english ? 'Sign-in failed.' : 'Anmeldung fehlgeschlagen.'),
      };
    }

    final message = error.toString();
    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }
}

class _LoginLayoutMetrics {
  const _LoginLayoutMetrics({
    required this.width,
    required this.height,
    required this.compact,
    required this.sideInset,
    required this.logoLeft,
    required this.cardInset,
    required this.languageTop,
    required this.logoTop,
    required this.logoWidth,
    required this.titleTop,
    required this.cardTop,
    required this.cardHeight,
    required this.dividerTop,
    required this.socialTop,
  });

  final double width;
  final double height;
  final bool compact;
  final double sideInset;
  final double logoLeft;
  final double cardInset;
  final double languageTop;
  final double logoTop;
  final double logoWidth;
  final double titleTop;
  final double cardTop;
  final double cardHeight;
  final double dividerTop;
  final double socialTop;

  factory _LoginLayoutMetrics.from(BoxConstraints constraints) {
    final width = constraints.maxWidth.clamp(320.0, 430.0).toDouble();
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 844.0;
    final compact = height < 790 || width < 370;
    final veryCompact = height < 735;
    final widthScale = width / 430.0;
    final heightScale = (height / 844.0).clamp(0.82, 1.06).toDouble();
    var cardTop = veryCompact ? 266.0 : (compact ? 288.0 : 312.0) * heightScale;
    var cardHeight = veryCompact ? 284.0 : (compact ? 306.0 : 342.0);
    final bottomReserve = veryCompact ? 150.0 : (compact ? 164.0 : 186.0);
    final maxCardBottom = height - bottomReserve;
    if (cardTop + cardHeight > maxCardBottom) {
      final minCardHeight = veryCompact ? 270.0 : 296.0;
      cardHeight = math.max(minCardHeight, maxCardBottom - cardTop);
      if (cardTop + cardHeight > maxCardBottom) {
        cardTop = math.max(238.0, maxCardBottom - cardHeight);
      }
    }
    final dividerTop = cardTop + cardHeight + (veryCompact ? 12.0 : 22.0);
    final socialTop = dividerTop + (veryCompact ? 30.0 : 42.0);

    return _LoginLayoutMetrics(
      width: width,
      height: height,
      compact: compact,
      sideInset: 34 * widthScale,
      logoLeft: 34 * widthScale,
      cardInset: 26 * widthScale,
      languageTop: veryCompact ? 50 : (compact ? 58 : 74) * heightScale,
      logoTop: veryCompact ? 50 : (compact ? 58 : 74) * heightScale,
      logoWidth: veryCompact ? 122 : (compact ? 136 : 176) * widthScale,
      titleTop: veryCompact ? 154 : (compact ? 178 : 214) * heightScale,
      cardTop: cardTop,
      cardHeight: cardHeight,
      dividerTop: dividerTop,
      socialTop: socialTop,
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFFCFD),
            Color(0xFFFFF7FA),
            Color(0xFFFFFFFF),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            right: -130,
            top: 88,
            child: _LoginRedGlow(size: 310, opacity: 0.20),
          ),
          const Positioned(
            left: -180,
            bottom: -120,
            child: _LoginRedGlow(size: 360, opacity: 0.10),
          ),
          child,
        ],
      ),
    );
  }
}

class _LoginRedGlow extends StatelessWidget {
  const _LoginRedGlow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: <Color>[
                AppColors.primary.withValues(alpha: opacity),
                const Color(0xFFFF8CA3).withValues(alpha: opacity * 0.42),
                Colors.transparent,
              ],
              stops: const <double>[0, 0.46, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginTitleBlock extends StatelessWidget {
  const _LoginTitleBlock({required this.compact, required this.copy});

  final bool compact;
  final _LoginCopy copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.welcome,
          style: theme.textTheme.displayMedium?.copyWith(
            color: AppColors.ink,
            fontSize: compact ? 30 : 42,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          copy.subtitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF666A75),
            fontSize: compact ? 14 : 18,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({required this.child, required this.compact});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        compact ? 20 : 26,
        compact ? 16 : 22,
        compact ? 12 : 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(compact ? 26 : 30),
        border: Border.all(color: const Color(0xFFF1E8ED)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 36,
            spreadRadius: -12,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 24 : 28),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Colors.white,
                      Color(0xFFFFFBFD),
                      Color(0xFFFDF8FB),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.languageCode, required this.onTap});

  final String languageCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0E7EC)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF7B707A).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.language_rounded,
              color: Color(0xFF2B292D),
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              languageCode.toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF2B292D),
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.selectedCode});

  final String selectedCode;

  @override
  Widget build(BuildContext context) {
    final languages = <({String code, String label})>[
      (code: 'de', label: 'Deutsch'),
      (code: 'en', label: 'English'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFF0E7EC)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF7B707A).withValues(alpha: 0.12),
                blurRadius: 38,
                spreadRadius: -12,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages
                .map((language) {
                  final selected = language.code == selectedCode;
                  return _LanguageOption(
                    code: language.code,
                    label: language.label,
                    selected: selected,
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.code,
    required this.label,
    required this.selected,
  });

  final String code;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(code),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Text(
              code.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected ? AppColors.primary : AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _RememberCheck extends StatelessWidget {
  const _RememberCheck({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: checked ? AppColors.primary : const Color(0xFFF5EEF2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: checked
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.20),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: checked
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

class _PremiumLoginInput extends StatefulWidget {
  const _PremiumLoginInput({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.compact,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final bool compact;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PremiumLoginInput> createState() => _PremiumLoginInputState();
}

class _PremiumLoginInputState extends State<_PremiumLoginInput> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontSize: widget.compact ? 14 : 18,
            fontWeight: FontWeight.w900,
            height: 1.22,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: widget.compact ? 6 : 12),
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          decoration: InputDecoration(
            isDense: true,
            constraints: BoxConstraints.tightFor(
              height: widget.compact ? 48 : 62,
            ),
            hintText: widget.hintText,
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF8A8790),
              fontSize: widget.compact ? 13.5 : 16,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(
              widget.icon,
              color: AppColors.primary,
              size: widget.compact ? 20 : 25,
            ),
            suffixIcon: widget.obscureText
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF7B7780),
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFFFFBFD),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(
                color: const Color(0xFFEEDFE6).withValues(alpha: 0.95),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(
                color: const Color(0xFFEEDFE6).withValues(alpha: 0.95),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.25,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumLoginButton extends StatelessWidget {
  const _PremiumLoginButton({
    required this.label,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: onTap == null ? 0.58 : 1,
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: -8,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Container(
              height: compact ? 48 : 58,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFFF5C61), Color(0xFFFF0F4F)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  Positioned(
                    right: compact ? 19 : 23,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: compact ? 24 : 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SocialLoginType { google, apple }

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.label,
    required this.onTap,
    required this.compact,
    required this.type,
  });

  final String label;
  final VoidCallback? onTap;
  final bool compact;
  final _SocialLoginType type;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: onTap == null ? 0.58 : 1,
        child: Container(
          height: compact ? 48 : 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1E8ED)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF746A73).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 34,
                child: Center(
                  child: switch (type) {
                    _SocialLoginType.google => const _GoogleGlyph(),
                    _SocialLoginType.apple => const Icon(
                      Icons.apple,
                      color: Colors.black,
                      size: 28,
                    ),
                  },
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 34),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.16
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
      size.width * 0.16,
      size.height * 0.16,
      size.width * 0.68,
      size.height * 0.68,
    );
    stroke.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.05, 1.35, false, stroke);
    stroke.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 1.35, 1.18, false, stroke);
    stroke.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.53, 1.02, false, stroke);
    stroke.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.55, 1.35, false, stroke);
    final bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.53, size.height * 0.50),
      Offset(size.width * 0.86, size.height * 0.50),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGlyphPainter oldDelegate) => false;
}

class _LoginDivider extends StatelessWidget {
  const _LoginDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: Color(0xFFE6DDE2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFF8D8992),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE6DDE2))),
      ],
    );
  }
}
