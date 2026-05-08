import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/services/app_location_service.dart';
import '../../../../core/services/app_location_types.dart';
import '../../../../core/services/local_onboarding_state_service.dart';
import '../../../../core/services/location_label_resolver.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../theme/app_colors.dart';

enum _LocationChoice { undecided, granted, manual, skipped }

double _loopPhase(Animation<double> animation, {required double seconds}) {
  return animation.value * math.pi * 2 * (3600 / seconds);
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.initialStep = 0});

  final int initialStep;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _assetCafe = 'assets/onboarding/onboarding_cafe.jpg';
  static const _assetBakery = 'assets/onboarding/onboarding_bakery.jpg';
  static const _assetPasta = 'assets/onboarding/onboarding_pasta.jpg';
  static const _assetBoutique = 'assets/onboarding/onboarding_boutique.jpg';
  static const _assetOnboardingLogo =
      'assets/branding/spargo_onboarding_logo.png';
  static const _assetIntroExact =
      'assets/onboarding/onboarding_intro_exact.png';
  static const _assetTrustExact =
      'assets/onboarding/onboarding_trust_exact_crop.png';

  late final PageController _pageController;
  final Animation<double> _motionController =
      const AlwaysStoppedAnimation<double>(0);
  late final AppLocationService _locationService = createAppLocationService();
  final TextEditingController _manualLocationController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(milliseconds: 900),
  );

  int _pageIndex = 0;
  Set<DealCategory> _selectedInterests = const <DealCategory>{};
  _LocationChoice _locationChoice = _LocationChoice.undecided;
  double _radiusKm = 20;
  bool _manualLocationVisible = false;
  bool _requestingLocation = false;
  bool _authenticating = false;
  bool _passwordObscured = true;
  bool _imagesPrecached = false;
  String? _locationError;
  String? _authError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _pageIndex = widget.initialStep.clamp(0, 8);
    _selectedInterests = user.favoriteCategories
        .where(_supportedInterestCategories.contains)
        .toSet();
    _radiusKm = ref
        .read(settingsControllerProvider)
        .distanceKm
        .clamp(5.0, 50.0);
    _manualLocationController.text = user.city == 'Deutschlandweit'
        ? ''
        : user.city;
    _pageController = PageController(initialPage: _pageIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imagesPrecached) {
      return;
    }
    _imagesPrecached = true;
    for (final asset in <String>[
      _assetCafe,
      _assetBakery,
      _assetPasta,
      _assetBoutique,
      _assetOnboardingLogo,
    ]) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _pageController.dispose();
    _manualLocationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFE),
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            _OnboardingBackground(
              animation: _motionController,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 760;
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 18 : 24,
                            compact ? 10 : 16,
                            compact ? 18 : 24,
                            compact ? 12 : 18,
                          ),
                          child: Column(
                            children: <Widget>[
                              _OnboardingTopBar(
                                pageIndex: _pageIndex,
                                onBack: _pageIndex == 0 ? null : _goBack,
                              ),
                              Expanded(
                                child: PageView(
                                  controller: _pageController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  onPageChanged: (index) {
                                    setState(() {
                                      _pageIndex = index;
                                      _authError = null;
                                      _locationError = null;
                                    });
                                  },
                                  children: <Widget>[
                                    _buildPage(
                                      0,
                                      _IntroPage(
                                        compact: compact,
                                        motion: _motionController,
                                        onPrimary: _goNext,
                                        onLogin: _openLogin,
                                      ),
                                    ),
                                    _buildPage(
                                      1,
                                      _TrustPage(
                                        compact: compact,
                                        motion: _motionController,
                                        onNext: _goNext,
                                      ),
                                    ),
                                    _buildPage(
                                      2,
                                      _FeaturesPage(
                                        compact: compact,
                                        onNext: _goNext,
                                      ),
                                    ),
                                    _buildPage(
                                      3,
                                      _InterestsPage(
                                        compact: compact,
                                        selected: _selectedInterests,
                                        onToggle: _toggleInterest,
                                        onNext: _saveInterestsAndContinue,
                                        onSkip: _skipInterests,
                                      ),
                                    ),
                                    _buildPage(
                                      4,
                                      _LocationPage(
                                        compact: compact,
                                        motion: _motionController,
                                        manualVisible: _manualLocationVisible,
                                        manualController:
                                            _manualLocationController,
                                        requesting: _requestingLocation,
                                        errorText: null,
                                        onRequestLocation: _requestLocation,
                                        onManualTap: _handleManualLocation,
                                        onSkip: _skipLocation,
                                      ),
                                    ),
                                    _buildPage(
                                      5,
                                      _RadiusPage(
                                        compact: compact,
                                        radiusKm: _radiusKm,
                                        onChanged: (value) {
                                          setState(() => _radiusKm = value);
                                        },
                                        onNext: _saveRadiusAndContinue,
                                      ),
                                    ),
                                    _buildPage(
                                      6,
                                      _AccountEntryPage(
                                        compact: compact,
                                        emailController: _emailController,
                                        authenticating: _authenticating,
                                        errorText: null,
                                        onGoogle: _continueWithGoogle,
                                        onApple: _continueWithApple,
                                        onEmailNext: _continueWithEmail,
                                      ),
                                    ),
                                    _buildPage(
                                      7,
                                      _PasswordPage(
                                        compact: compact,
                                        controller: _passwordController,
                                        obscure: _passwordObscured,
                                        submitting: _authenticating,
                                        errorText: null,
                                        onObscureToggle: () {
                                          setState(
                                            () => _passwordObscured =
                                                !_passwordObscured,
                                          );
                                        },
                                        onSubmit: _createEmailAccount,
                                      ),
                                    ),
                                    _buildPage(
                                      8,
                                      _SuccessPage(
                                        compact: compact,
                                        motion: _motionController,
                                        onStart: _finishSuccess,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
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
                  Color(0xFF9CD7FF),
                  Colors.white,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index, Widget child) {
    return _AnimatedPageSlot(
      controller: _pageController,
      index: index,
      child: child,
    );
  }

  void _goNext() => _animateTo((_pageIndex + 1).clamp(0, 8));

  void _goBack() => _animateTo((_pageIndex - 1).clamp(0, 8), forward: false);

  Future<void> _animateTo(int page, {bool forward = true}) async {
    FocusScope.of(context).unfocus();
    await _pageController.animateToPage(
      page,
      duration: Duration(milliseconds: forward ? 620 : 420),
      curve: forward ? Curves.easeOutQuint : Curves.easeInOutCubic,
    );
  }

  void _openLogin() {
    Navigator.of(context).pushNamed(AppRoutes.login);
  }

  void _toggleInterest(DealCategory category) {
    setState(() {
      final next = _selectedInterests.toSet();
      if (!next.remove(category)) {
        next.add(category);
      }
      _selectedInterests = next;
    });
  }

  void _saveInterestsAndContinue() {
    _persistInterestsLocally();
    _goNext();
  }

  void _skipInterests() {
    setState(() => _selectedInterests = const <DealCategory>{});
    _persistInterestsLocally();
    _goNext();
  }

  void _persistInterestsLocally() {
    ref
        .read(sessionControllerProvider.notifier)
        .selectInterests(_selectedInterests.toList(growable: false));
  }

  Future<void> _requestLocation() async {
    if (_requestingLocation) {
      return;
    }
    setState(() {
      _requestingLocation = true;
      _locationError = null;
      _manualLocationVisible = false;
    });

    try {
      final position = await _locationService.requestCurrentLocation();
      final resolvedLocation = await resolveLocationLabel(
        latitude: position.latitude,
        longitude: position.longitude,
        businesses: ref.read(businessesProvider),
      );
      ref
          .read(sessionControllerProvider.notifier)
          .grantLocation(
            city: resolvedLocation.city,
            district: resolvedLocation.district,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _locationChoice = _LocationChoice.granted;
        _manualLocationController.text = resolvedLocation.city;
      });
      _goNext();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _locationError = null);
      _showErrorToast(_friendlyLocationError(error));
    } finally {
      if (mounted) {
        setState(() => _requestingLocation = false);
      }
    }
  }

  void _handleManualLocation() {
    if (!_manualLocationVisible) {
      setState(() {
        _manualLocationVisible = true;
        _locationError = null;
      });
      return;
    }

    final value = _manualLocationController.text.trim();
    if (value.length < 2) {
      _showErrorToast('Bitte gib Stadt oder PLZ ein.');
      return;
    }

    setState(() {
      _locationChoice = _LocationChoice.manual;
      _locationError = null;
    });
    ref
        .read(sessionControllerProvider.notifier)
        .grantLocation(city: value, district: 'In deiner Nähe');
    _goNext();
  }

  void _skipLocation() {
    setState(() {
      _locationChoice = _LocationChoice.skipped;
      _locationError = null;
    });
    _goNext();
  }

  void _saveRadiusAndContinue() {
    ref.read(settingsControllerProvider.notifier).setDistance(_radiusKm);
    final authUser = ref.read(authUserProvider);
    if (authUser == null) {
      _goNext();
      return;
    }
    unawaited(_persistOnboardingCompletion());
    _animateTo(8);
  }

  Future<void> _continueWithGoogle() async {
    if (_authenticating) {
      return;
    }
    setState(() {
      _authenticating = true;
      _authError = null;
    });
    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .loginWithGoogle();
      if (result.requiresApproval) {
        throw StateError(
          'Neues Gerät erkannt. Bitte bestätige zuerst die Mail.',
        );
      }
      await _persistOnboardingCompletion();
      if (!mounted) {
        return;
      }
      await _playAuthConfetti();
      if (!mounted) {
        return;
      }
      await _animateTo(8);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _authError = null);
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  Future<void> _continueWithApple() async {
    if (_authenticating) {
      return;
    }
    setState(() {
      _authenticating = true;
      _authError = null;
    });
    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .loginWithApple();
      if (result.requiresApproval) {
        throw StateError(
          'Neues Gerät erkannt. Bitte bestätige zuerst die Mail.',
        );
      }
      await _persistOnboardingCompletion();
      if (!mounted) {
        return;
      }
      await _playAuthConfetti();
      if (!mounted) {
        return;
      }
      await _animateTo(8);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _authError = null);
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  void _continueWithEmail() {
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _showErrorToast('Bitte gib eine gültige E-Mail ein.');
      return;
    }
    setState(() => _authError = null);
    _goNext();
  }

  Future<void> _createEmailAccount() async {
    if (_authenticating) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (!_looksLikeEmail(email)) {
      _showErrorToast('Bitte gib eine gültige E-Mail ein.');
      return;
    }
    if (!_passwordIsValid(password)) {
      _showErrorToast('Das Passwort erfüllt die Anforderungen noch nicht.');
      return;
    }

    setState(() {
      _authenticating = true;
      _authError = null;
    });

    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: email,
            password: password,
            name: _nameFromEmail(email),
            handle: _handleFromEmail(email),
            city: _draftCity(),
            accountType: AccountType.user,
          );
      await _persistOnboardingCompletion();
      if (!mounted) {
        return;
      }
      await _playAuthConfetti();
      if (!mounted) {
        return;
      }
      await _animateTo(8);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _authError = null);
      _showErrorToast(_friendlyAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  Future<void> _persistOnboardingCompletion() async {
    _persistInterestsLocally();
    ref.read(settingsControllerProvider.notifier).setDistance(_radiusKm);

    final authUser = ref.read(authUserProvider);
    if (authUser == null) {
      return;
    }

    final user = ref.read(currentUserProvider);
    await ref
        .read(repositoryProvider)
        .completeUserOnboarding(
          user: user,
          interests: _selectedInterests.toList(growable: false),
          locationPermissionStatus: _locationStatusLabel,
          manualLocation: _locationChoice == _LocationChoice.manual
              ? _manualLocationController.text.trim()
              : null,
          radiusKm: _radiusKm,
        );
    await const LocalOnboardingStateService().markUserOnboardingCompleted(
      authUser.uid,
    );
    ref
        .read(sessionControllerProvider.notifier)
        .markUserOnboardingComplete(
          interests: _selectedInterests.toList(growable: false),
          hasLocationPermission:
              _locationChoice == _LocationChoice.granted ||
              _locationChoice == _LocationChoice.manual,
          radiusKm: _radiusKm,
        );
  }

  Future<void> _finishSuccess() async {
    await _persistOnboardingCompletion();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.shell,
      (route) => false,
      arguments: const ShellArgs(),
    );
  }

  Future<void> _playAuthConfetti() async {
    _confettiController.play();
    await Future<void>.delayed(const Duration(milliseconds: 820));
  }

  void _showErrorToast(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _authError = null;
      _locationError = null;
    });
    showAppToast(context, message);
  }

  String get _locationStatusLabel {
    return switch (_locationChoice) {
      _LocationChoice.granted => 'granted',
      _LocationChoice.manual => 'manual',
      _LocationChoice.skipped => 'skipped',
      _LocationChoice.undecided => 'skipped',
    };
  }

  String _draftCity() {
    final manual = _manualLocationController.text.trim();
    if (manual.isNotEmpty && _locationChoice == _LocationChoice.manual) {
      return manual;
    }
    final city = ref.read(currentUserProvider).city.trim();
    return city.isEmpty ? 'Deutschlandweit' : city;
  }

  String _nameFromEmail(String email) {
    final seed = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    final words = seed
        .split(' ')
        .where((entry) => entry.trim().isNotEmpty)
        .map((entry) {
          final lower = entry.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .toList(growable: false);
    return words.isEmpty ? 'sparGO User' : words.join(' ');
  }

  String _handleFromEmail(String email) {
    final seed = email.split('@').first.toLowerCase();
    final normalized = seed.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${normalized.isEmpty ? 'spargo' : normalized}';
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  bool _passwordIsValid(String value) {
    return value.length >= 8 &&
        RegExp(r'\d').hasMatch(value) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(value);
  }

  String _friendlyLocationError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.toLowerCase().contains('permission')) {
      return 'Standort wurde nicht freigegeben. Du kannst ihn manuell setzen.';
    }
    return message;
  }

  String _friendlyAuthError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      return switch (error.code) {
        'email-already-in-use' =>
          'Diese E-Mail hat schon ein Konto. Bitte einloggen.',
        'weak-password' => 'Bitte nimm ein stärkeres Passwort.',
        'invalid-email' => 'Die E-Mail-Adresse ist nicht gültig.',
        'popup-closed-by-user' => 'Anmeldung wurde geschlossen.',
        'account-exists-with-different-credential' =>
          'Dieses Konto existiert bereits mit einer anderen Anmeldemethode.',
        'operation-not-allowed' =>
          'Diese Anmeldemethode ist in Firebase noch nicht aktiviert.',
        'network-request-failed' => 'Netzwerkfehler. Bitte erneut versuchen.',
        _ => error.message ?? 'Anmeldung fehlgeschlagen.',
      };
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }
}

class _OnboardingBackground extends StatelessWidget {
  const _OnboardingBackground({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: ColoredBox(color: Color(0xFFF7F8FC))),
        const Positioned(
          top: -150,
          right: -130,
          child: _AmbientOrb(
            size: 420,
            color: Color(0xFFFFCAD6),
            opacity: 0.42,
          ),
        ),
        const Positioned(
          top: -18,
          right: -82,
          child: _AmbientOrb(
            size: 240,
            color: Color(0xFFFF1B55),
            opacity: 0.10,
          ),
        ),
        const Positioned(
          bottom: -150,
          left: -120,
          child: _AmbientOrb(
            size: 340,
            color: Color(0xFFEADFFF),
            opacity: 0.34,
          ),
        ),
        const Positioned(
          top: 160,
          left: -170,
          child: _AmbientOrb(
            size: 290,
            color: Color(0xFFDFF5FF),
            opacity: 0.28,
          ),
        ),
        RepaintBoundary(child: child),
      ],
    );
  }
}

class _AnimatedPageSlot extends StatelessWidget {
  const _AnimatedPageSlot({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var page = index.toDouble();
        if (controller.positions.isNotEmpty) {
          try {
            page = controller.page ?? controller.initialPage.toDouble();
          } catch (_) {
            page = controller.initialPage.toDouble();
          }
        }
        final delta = (page - index).clamp(-1.0, 1.0).toDouble();
        final distance = delta.abs();
        final eased = Curves.easeOutCubic.transform(1 - distance);
        return Opacity(
          opacity: 0.48 + eased * 0.52,
          child: Transform.translate(
            offset: Offset(delta * -34, 10 * distance),
            child: Transform.scale(
              scale: 0.965 + eased * 0.035,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _LiquidBackdropPainter extends CustomPainter {
  const _LiquidBackdropPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[
          Color(0xFFF9FAFE),
          Color(0xFFF6F8FD),
          Color(0xFFFFF7FA),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final wash = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              const Color(0xFFFFE2EA).withValues(alpha: 0.42),
              const Color(0xFFEAF2FF).withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * (0.58 + math.sin(t * 0.7) * 0.08),
                size.height * 0.33,
              ),
              radius: size.width * 0.62,
            ),
          );
    canvas.drawRect(rect, wash);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.34);
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.18 + i * 0.10) + math.sin(t + i) * 4;
      final path = Path()
        ..moveTo(-20, y)
        ..cubicTo(
          size.width * 0.28,
          y - 26,
          size.width * 0.62,
          y + 34,
          size.width + 20,
          y - 10,
        );
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidBackdropPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  color.withValues(alpha: opacity),
                  color.withValues(alpha: opacity * 0.38),
                  Colors.transparent,
                ],
                stops: const <double>[0, 0.46, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({required this.pageIndex, this.onBack});

  final int pageIndex;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final showProgress = pageIndex < 8;
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            AppBackButton(onTap: onBack!),
            const SizedBox(width: 14),
          ] else ...<Widget>[
            Transform.translate(
              offset: const Offset(0, 3),
              child: Transform.scale(
                scale: 1.05,
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  _WelcomeScreenState._assetOnboardingLogo,
                  width: 138,
                  height: 44,
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const Spacer(),
          ],
          if (showProgress)
            SizedBox(
              width: onBack == null ? 132 : 112,
              child: Row(
                children: List<Widget>.generate(4, (index) {
                  final active = index <= (pageIndex / 2).floor();
                  return Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: AppDurations.fast,
                        height: 3,
                        width: active ? 38 : 24,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFFF2D55)
                              : const Color(0xFFE7E9F1),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.compact,
    required this.motion,
    required this.onPrimary,
    required this.onLogin,
  });

  final bool compact;
  final Animation<double> motion;
  final VoidCallback onPrimary;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: compact ? 9 : 10,
      contentFlex: compact ? 5 : 6,
      visual: _HeroComposition(motion: motion),
      headline: 'Finde echte\nDeals in deiner\nNähe.',
      body: 'Keine Werbung. Nur Vorteile,\ndie sich wirklich lohnen.',
      primaryLabel: 'Entdecken',
      onPrimary: onPrimary,
      secondary: _TextAction(
        text: 'Schon ein Konto? ',
        actionText: 'Einloggen',
        onTap: onLogin,
      ),
    );

    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: compact ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Image.asset(
            'assets/branding/spargo_complete_logo.png',
            width: 104,
            fit: BoxFit.contain,
          ),
          SizedBox(height: compact ? 26 : 34),
          Text(
            'Finde echte\nDeals in deiner\nNähe.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              height: 1.08,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            'Keine Werbung. Nur Vorteile,\ndie sich wirklich lohnen.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF596170),
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: compact ? 174 : 204,
            width: double.infinity,
            child: _HeroComposition(motion: motion),
          ),
          SizedBox(height: compact ? 16 : 22),
          _PrimaryGradientButton(label: 'Entdecken', onTap: onPrimary),
          const SizedBox(height: 12),
          _TextAction(
            text: 'Schon ein Konto? ',
            actionText: 'Einloggen',
            onTap: onLogin,
          ),
        ],
      ),
    );
  }
}

class _ExactIntroReference extends StatelessWidget {
  const _ExactIntroReference({
    required this.motion,
    required this.onPrimary,
    required this.onLogin,
  });

  static const Size _sourceSize = Size(853, 1844);
  static const Rect _statusChromeRect = Rect.fromLTWH(0, 0, 853, 110);
  static const Rect _primaryRect = Rect.fromLTWH(89, 1564, 676, 110);
  static const Rect _loginRect = Rect.fromLTWH(220, 1708, 420, 76);
  static const Rect _cardStageRect = Rect.fromLTWH(0, 886, 853, 636);
  static const Rect _leftCardRect = Rect.fromLTWH(50, 1084, 281, 438);
  static const Rect _centerCardRect = Rect.fromLTWH(286, 936, 338, 528);
  static const Rect _rightCardRect = Rect.fromLTWH(582, 1098, 279, 426);

  final Animation<double> motion;
  final VoidCallback onPrimary;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final statusChromeRect = _coverRect(size, _statusChromeRect);
        final primaryRect = _coverRect(size, _primaryRect);
        final loginRect = _coverRect(size, _loginRect);
        final cardStageRect = _coverRect(size, _cardStageRect);
        final leftCardRect = _coverRect(size, _leftCardRect);
        final centerCardRect = _coverRect(size, _centerCardRect);
        final rightCardRect = _coverRect(size, _rightCardRect);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: Image.asset(
                _WelcomeScreenState._assetIntroExact,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned.fromRect(
              rect: statusChromeRect,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFF4F7FE), Color(0xFFFAF7FB)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: cardStageRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.00),
                        const Color(0xFFFFEFF4).withValues(alpha: 0.48),
                        const Color(0xFFFFF8FB).withValues(alpha: 0.58),
                        Colors.white.withValues(alpha: 0.00),
                      ],
                      stops: const <double>[0.00, 0.30, 0.62, 1.00],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            _AnimatedIntroDealCard(
              motion: motion,
              rect: leftCardRect,
              asset: _WelcomeScreenState._assetCafe,
              title: 'Café Mahlzeit',
              badge: '-20%',
              distance: '0,3 km',
              angle: -0.105,
              phaseOffset: 0.4,
              glowColor: const Color(0xFFFFA3B4),
            ),
            _AnimatedIntroDealCard(
              motion: motion,
              rect: rightCardRect,
              asset: _WelcomeScreenState._assetBoutique,
              title: 'Maison Store',
              badge: '-15%',
              distance: '0,7 m',
              angle: 0.105,
              phaseOffset: 2.1,
              glowColor: const Color(0xFFCAB7FF),
            ),
            _AnimatedIntroDealCard(
              motion: motion,
              rect: centerCardRect,
              asset: _WelcomeScreenState._assetPasta,
              title: 'Pasta Brothers',
              badge: '2 für 1',
              distance: '0,5 km',
              angle: 0.012,
              phaseOffset: 1.2,
              glowColor: const Color(0xFFFFC576),
              elevated: true,
            ),
            Positioned.fromRect(
              rect: primaryRect,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(primaryRect.height / 2),
                  onTap: onPrimary,
                ),
              ),
            ),
            Positioned.fromRect(
              rect: loginRect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLogin,
              ),
            ),
          ],
        );
      },
    );
  }

  Rect _coverRect(Size targetSize, Rect sourceRect) {
    final scale = math.max(
      targetSize.width / _sourceSize.width,
      targetSize.height / _sourceSize.height,
    );
    final renderedWidth = _sourceSize.width * scale;
    final renderedHeight = _sourceSize.height * scale;
    final dx = (targetSize.width - renderedWidth) / 2;
    final dy = (targetSize.height - renderedHeight) / 2;

    return Rect.fromLTWH(
      dx + sourceRect.left * scale,
      dy + sourceRect.top * scale,
      sourceRect.width * scale,
      sourceRect.height * scale,
    );
  }
}

class _AnimatedIntroDealCard extends StatelessWidget {
  const _AnimatedIntroDealCard({
    required this.motion,
    required this.rect,
    required this.asset,
    required this.title,
    required this.badge,
    required this.distance,
    required this.angle,
    required this.phaseOffset,
    required this.glowColor,
    this.elevated = false,
  });

  final Animation<double> motion;
  final Rect rect;
  final String asset;
  final String title;
  final String badge;
  final String distance;
  final double angle;
  final double phaseOffset;
  final Color glowColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final phase = _loopPhase(motion, seconds: elevated ? 7.5 : 8.5);
        final dy = math.sin(phase + phaseOffset) * (elevated ? 5.0 : 4.0);
        final dx =
            math.cos(phase * 0.72 + phaseOffset) * (elevated ? 2.2 : 1.5);
        final rotate = angle + math.sin(phase * 0.62 + phaseOffset) * 0.010;

        return Positioned.fromRect(
          rect: rect.translate(dx, dy),
          child: Transform.rotate(
            angle: rotate,
            alignment: Alignment.center,
            child: _IntroReferenceDealCard(
              asset: asset,
              title: title,
              badge: badge,
              distance: distance,
              glowColor: glowColor,
              elevated: elevated,
            ),
          ),
        );
      },
    );
  }
}

class _IntroReferenceDealCard extends StatelessWidget {
  const _IntroReferenceDealCard({
    required this.asset,
    required this.title,
    required this.badge,
    required this.distance,
    required this.glowColor,
    required this.elevated,
  });

  final String asset;
  final String title;
  final String badge;
  final String distance;
  final Color glowColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(elevated ? 22 : 20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor.withValues(alpha: elevated ? 0.28 : 0.20),
            blurRadius: elevated ? 36 : 28,
            spreadRadius: elevated ? -5 : -7,
            offset: Offset(0, elevated ? 22 : 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: elevated ? 0.20 : 0.16),
            blurRadius: elevated ? 28 : 22,
            offset: Offset(0, elevated ? 18 : 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(elevated ? 22 : 20),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(asset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.06),
                    Colors.transparent,
                    Colors.black.withValues(alpha: elevated ? 0.74 : 0.70),
                  ],
                  stops: const <double>[0.0, 0.48, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.34),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(elevated ? 22 : 20),
              ),
            ),
            Positioned(
              left: elevated ? 34 : 40,
              right: elevated ? 34 : 38,
              bottom: elevated ? 120 : 104,
              child: Center(
                child: _IntroBadge(label: badge, elevated: elevated),
              ),
            ),
            Positioned(
              left: elevated ? 32 : 32,
              right: 18,
              bottom: elevated ? 68 : 58,
              child: Text(
                title,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: elevated ? 24 : 20,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: 0,
                  inherit: false,
                ),
              ),
            ),
            Positioned(
              left: elevated ? 32 : 32,
              bottom: elevated ? 32 : 28,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.location_on_rounded,
                    size: elevated ? 18 : 15,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    distance,
                    textScaler: TextScaler.noScaling,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: elevated ? 18 : 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      inherit: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroBadge extends StatelessWidget {
  const _IntroBadge({required this.label, required this.elevated});

  final String label;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: elevated ? 22 : 18,
        vertical: elevated ? 12 : 9,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        label,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: Colors.white,
          fontSize: elevated ? 18 : 16,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: 0,
          inherit: false,
        ),
      ),
    );
  }
}

class _TrustPage extends StatelessWidget {
  const _TrustPage({
    required this.compact,
    required this.motion,
    required this.onNext,
  });

  final bool compact;
  final Animation<double> motion;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: 8,
      contentFlex: 9,
      visual: _TrustCouponPlacesVisual(motion: motion),
      headline: 'Von echten Orten,\ndie du kennst.',
      body: 'Cafés, Shops & Highlights\naus deiner Umgebung.',
      primaryLabel: 'Weiter',
      onPrimary: onNext,
    );
  }
}

class _TrustReferenceImage extends StatelessWidget {
  const _TrustReferenceImage({required this.onNext});

  static const Size _sourceSize = Size(630, 1024);
  static const Rect _statusChromeRect = Rect.fromLTWH(0, 0, 630, 62);
  static const Rect _primaryRect = Rect.fromLTWH(36, 858, 558, 78);

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final statusRect = _coverRect(size, _statusChromeRect);
        final primaryRect = _coverRect(size, _primaryRect);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: Image.asset(
                _WelcomeScreenState._assetTrustExact,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned.fromRect(
              rect: statusRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      const Color(0xFFF8FAFE).withValues(alpha: 0.99),
                      const Color(0xFFFFF8FB).withValues(alpha: 0.99),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: primaryRect,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(primaryRect.height / 2),
                  onTap: onNext,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Rect _coverRect(Size targetSize, Rect sourceRect) {
    final scale = math.max(
      targetSize.width / _sourceSize.width,
      targetSize.height / _sourceSize.height,
    );
    final renderedWidth = _sourceSize.width * scale;
    final renderedHeight = _sourceSize.height * scale;
    final dx = (targetSize.width - renderedWidth) / 2;
    final dy = (targetSize.height - renderedHeight) / 2;

    return Rect.fromLTWH(
      dx + sourceRect.left * scale,
      dy + sourceRect.top * scale,
      sourceRect.width * scale,
      sourceRect.height * scale,
    );
  }
}

class _ExactTrustReference extends StatelessWidget {
  const _ExactTrustReference({
    required this.compact,
    required this.motion,
    required this.onNext,
  });

  final bool compact;
  final Animation<double> motion;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _TrustReferenceImage(onNext: onNext);

    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final scale = math
            .min(width / 390, height / 812)
            .clamp(0.82, 1.08)
            .toDouble();
        final horizontal = math.max(30.0, width * 0.105);
        final contentWidth = math.min(316.0 * scale, width - horizontal * 2);
        final topLogoGap = math.max(24.0, height * 0.048);
        final headlineGap = math.max(36.0, height * 0.075);
        final gridGap = compact ? 24.0 : 30.0;
        final buttonGap = compact ? 20.0 : 26.0;
        final topCardHeight = math.min(132.0 * scale, height * 0.18);
        final bottomCardHeight = math.min(118.0 * scale, height * 0.16);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.55, -0.52),
                    radius: 0.88,
                    colors: <Color>[
                      const Color(0xFFFFDCE8).withValues(alpha: 0.86),
                      const Color(0xFFF8F9FD).withValues(alpha: 0.96),
                      const Color(0xFFF9FAFE),
                    ],
                    stops: const <double>[0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -56 * scale,
              top: 20 * scale,
              child: _TrustSoftHalo(
                size: 180 * scale,
                color: const Color(0xFFFFC6D7),
                opacity: 0.35,
              ),
            ),
            Positioned(
              left: 48 * scale,
              bottom: 82 * scale,
              child: _TrustSoftHalo(
                size: 230 * scale,
                color: const Color(0xFFFFB6CA),
                opacity: 0.20,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(height: topLogoGap),
                    Image.asset(
                      'assets/branding/spargo_complete_logo.png',
                      width: 98 * scale,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: headlineGap),
                    SizedBox(
                      width: contentWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Von echten Orten,\ndie du kennst.',
                            textScaler: TextScaler.noScaling,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: AppColors.ink,
                              fontSize: 34 * scale,
                              fontWeight: FontWeight.w900,
                              height: 1.12,
                              letterSpacing: 0,
                            ),
                          ),
                          SizedBox(height: 18 * scale),
                          Text(
                            'Cafés, Shops & Highlights\naus deiner Umgebung.',
                            textScaler: TextScaler.noScaling,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF626A78),
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w600,
                              height: 1.46,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gridGap),
                    SizedBox(
                      width: contentWidth,
                      child: _TrustPlaceGrid(
                        motion: motion,
                        topCardHeight: topCardHeight,
                        bottomCardHeight: bottomCardHeight,
                        scale: scale,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: contentWidth,
                      child: _TrustPrimaryButton(onTap: onNext, scale: scale),
                    ),
                    SizedBox(height: buttonGap),
                    const _TrustProgressBars(),
                    SizedBox(height: math.max(22.0, height * 0.035)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrustPlaceGrid extends StatelessWidget {
  const _TrustPlaceGrid({
    required this.motion,
    required this.topCardHeight,
    required this.bottomCardHeight,
    required this.scale,
  });

  final Animation<double> motion;
  final double topCardHeight;
  final double bottomCardHeight;
  final double scale;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final phase = _loopPhase(motion, seconds: 13);
        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _AnimatedTrustPlaceCard(
                    phase: phase,
                    phaseOffset: 0.0,
                    asset: _WelcomeScreenState._assetCafe,
                    label: 'Cafés',
                    icon: Icons.local_cafe_rounded,
                    height: topCardHeight,
                    glowColor: const Color(0xFFFFB8C7),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _AnimatedTrustPlaceCard(
                    phase: phase,
                    phaseOffset: 1.6,
                    asset: _WelcomeScreenState._assetBakery,
                    label: 'Bäckereien',
                    icon: Icons.local_mall_rounded,
                    height: topCardHeight,
                    glowColor: const Color(0xFFFFD29B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: gap),
            Row(
              children: <Widget>[
                Expanded(
                  child: _AnimatedTrustPlaceCard(
                    phase: phase,
                    phaseOffset: 2.4,
                    asset: _WelcomeScreenState._assetBoutique,
                    label: 'Shops',
                    icon: Icons.shopping_bag_rounded,
                    height: bottomCardHeight,
                    glowColor: const Color(0xFFCFC3FF),
                    compactBadge: true,
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _AnimatedTrustPlaceCard(
                    phase: phase,
                    phaseOffset: 3.1,
                    asset: _WelcomeScreenState._assetPasta,
                    label: 'Restaurants',
                    icon: Icons.restaurant_rounded,
                    height: bottomCardHeight,
                    glowColor: const Color(0xFFFFC27B),
                    compactBadge: true,
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _TrustMoreHighlightsCard(
                    height: bottomCardHeight,
                    phase: phase,
                    scale: scale,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AnimatedTrustPlaceCard extends StatelessWidget {
  const _AnimatedTrustPlaceCard({
    required this.phase,
    required this.phaseOffset,
    required this.asset,
    required this.label,
    required this.icon,
    required this.height,
    required this.glowColor,
    this.compactBadge = false,
  });

  final double phase;
  final double phaseOffset;
  final String asset;
  final String label;
  final IconData icon;
  final double height;
  final Color glowColor;
  final bool compactBadge;

  @override
  Widget build(BuildContext context) {
    final dy = math.sin(phase + phaseOffset) * 2.8;
    final dx = math.cos(phase * 0.8 + phaseOffset) * 1.3;
    final angle = math.sin(phase * 0.58 + phaseOffset) * 0.006;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: angle,
        child: _TrustImageCard(
          asset: asset,
          label: label,
          icon: icon,
          height: height,
          glowColor: glowColor,
          compactBadge: compactBadge,
        ),
      ),
    );
  }
}

class _TrustImageCard extends StatelessWidget {
  const _TrustImageCard({
    required this.asset,
    required this.label,
    required this.icon,
    required this.height,
    required this.glowColor,
    required this.compactBadge,
  });

  final String asset;
  final String label;
  final IconData icon;
  final double height;
  final Color glowColor;
  final bool compactBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor.withValues(alpha: 0.22),
            blurRadius: 26,
            spreadRadius: -7,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(asset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 0.8,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: _TrustPlaceBadge(
                label: label,
                icon: icon,
                compact: compactBadge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustPlaceBadge extends StatelessWidget {
  const _TrustPlaceBadge({
    required this.label,
    required this.icon,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 37 : 42,
      padding: EdgeInsets.only(
        left: compact ? 10 : 12,
        right: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: compact ? 16 : 17, color: AppColors.primary),
          SizedBox(width: compact ? 6 : 8),
          Text(
            label,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.ink,
              fontSize: compact ? 14.5 : 16,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustMoreHighlightsCard extends StatelessWidget {
  const _TrustMoreHighlightsCard({
    required this.height,
    required this.phase,
    required this.scale,
  });

  final double height;
  final double phase;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final dy = math.sin(phase + 4.2) * 2.3;
    return Transform.translate(
      offset: Offset(0, dy),
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: <Color>[
              Colors.white.withValues(alpha: 0.88),
              const Color(0xFFFFE7F0).withValues(alpha: 0.90),
              const Color(0xFFFFBBDD).withValues(alpha: 0.66),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.13),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(painter: _HoloSheenPainter(phase * 0.55)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '+120',
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.primary,
                      fontSize: 30 * scale,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Text(
                    'weitere',
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.ink,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 5 * scale),
                  Text(
                    'Highlights',
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustPrimaryButton extends StatelessWidget {
  const _TrustPrimaryButton({required this.onTap, required this.scale});

  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58 * scale,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.primary,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.24),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Text(
                'Weiter',
                textScaler: TextScaler.noScaling,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            Positioned(
              right: 28 * scale,
              top: 0,
              bottom: 0,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 25 * scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustProgressBars extends StatelessWidget {
  const _TrustProgressBars();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (index) {
        final active = index == 0;
        return Container(
          width: active ? 42 : 40,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : const Color(0xFFDDE0E9).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        );
      }),
    );
  }
}

class _TrustSoftHalo extends StatelessWidget {
  const _TrustSoftHalo({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage({required this.compact, required this.onNext});

  final bool compact;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: 0,
      contentFlex: 1,
      headline: 'Alles in\neinem Flow.',
      body: '',
      fillContent: true,
      content: Column(
        children: <Widget>[
          const Spacer(),
          _FeatureGlassCard(
            icon: Icons.auto_stories_rounded,
            iconColor: Color(0xFFFF2D55),
            title: 'Stories entdecken',
            subtitle: 'Neue Deals im Feed',
          ),
          const SizedBox(height: 14),
          _FeatureGlassCard(
            icon: Icons.location_on_rounded,
            iconColor: Color(0xFF18B978),
            title: 'Auf Karte finden',
            subtitle: 'Direkt in deiner Nähe',
          ),
          const SizedBox(height: 14),
          _FeatureGlassCard(
            icon: Icons.account_balance_wallet_rounded,
            iconColor: Color(0xFF7657FF),
            title: 'Speichern & einlösen',
            subtitle: 'Alles in deinem Wallet',
          ),
          const Spacer(),
        ],
      ),
      primaryLabel: 'Klingt gut',
      onPrimary: onNext,
    );
  }
}

class _InterestsPage extends StatelessWidget {
  const _InterestsPage({
    required this.compact,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    required this.onSkip,
  });

  final bool compact;
  final Set<DealCategory> selected;
  final ValueChanged<DealCategory> onToggle;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: 0,
      contentFlex: 1,
      headline: 'Was interessiert\ndich?',
      body: 'Wir zeigen dir nur,\nwas wirklich passt.',
      content: _InterestsGrid(selected: selected, onToggle: onToggle),
      primaryLabel: 'Weiter',
      onPrimary: onNext,
      secondary: _PlainTextButton(label: 'Überspringen', onTap: onSkip),
    );
  }
}

class _InterestsGrid extends StatelessWidget {
  const _InterestsGrid({required this.selected, required this.onToggle});

  final Set<DealCategory> selected;
  final ValueChanged<DealCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 330 ? 2 : 2;
        final gap = width < 330 ? 8.0 : 12.0;
        final itemWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _supportedInterestCategories
              .map((category) {
                return SizedBox(
                  width: itemWidth,
                  child: _InterestGlassChip(
                    category: category,
                    selected: selected.contains(category),
                    onTap: () => onToggle(category),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _LocationPage extends StatelessWidget {
  const _LocationPage({
    required this.compact,
    required this.motion,
    required this.manualVisible,
    required this.manualController,
    required this.requesting,
    required this.errorText,
    required this.onRequestLocation,
    required this.onManualTap,
    required this.onSkip,
  });

  final bool compact;
  final Animation<double> motion;
  final bool manualVisible;
  final TextEditingController manualController;
  final bool requesting;
  final String? errorText;
  final VoidCallback onRequestLocation;
  final VoidCallback onManualTap;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: compact ? 8 : 9,
      contentFlex: compact ? 12 : 11,
      visual: _LocationOrbitalVisual(motion: motion),
      headline: 'Deals in deiner\nNähe',
      body: 'Mit Standort zeigen wir dir\nsofort passende Angebote.',
      content: Column(
        children: <Widget>[
          if (manualVisible) ...<Widget>[
            _GlassTextField(
              controller: manualController,
              hintText: context.t('Stadt oder PLZ'),
              keyboardType: TextInputType.streetAddress,
              icon: Icons.search_rounded,
            ),
            const SizedBox(height: 10),
          ],
          if (errorText != null)
            _InlineError(text: errorText!)
          else
            const SizedBox.shrink(),
        ],
      ),
      primaryLabel: requesting
          ? 'Standort wird geholt...'
          : 'Standort freigeben',
      onPrimary: requesting ? null : onRequestLocation,
      secondary: _SecondaryGlassButton(
        label: manualVisible ? 'Manuellen Ort speichern' : 'Manuell eingeben',
        onTap: onManualTap,
      ),
      tertiary: _PlainTextButton(label: 'Später entscheiden', onTap: onSkip),
    );
  }
}

class _RadiusPage extends StatelessWidget {
  const _RadiusPage({
    required this.compact,
    required this.radiusKm,
    required this.onChanged,
    required this.onNext,
  });

  final bool compact;
  final double radiusKm;
  final ValueChanged<double> onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: compact ? 7 : 9,
      contentFlex: compact ? 4 : 5,
      visual: _RadiusArcVisual(radiusKm: radiusKm, onChanged: onChanged),
      headline: 'Wie weit willst du\nschauen?',
      body: 'Passe deinen Radius\njederzeit an.',
      content: Column(
        children: <Widget>[
          const Row(
            children: <Widget>[
              Text('5 km', style: TextStyle(color: Color(0xFF68707F))),
              Spacer(),
              Text('50 km', style: TextStyle(color: Color(0xFF68707F))),
            ],
          ),
          const SizedBox(height: 18),
          _GlassInfoCard(
            icon: Icons.location_on_rounded,
            title: '~120 Deals verfügbar',
            subtitle: 'in deinem Umkreis',
          ),
        ],
      ),
      primaryLabel: 'Weiter',
      onPrimary: onNext,
    );
  }
}

class _AccountEntryPage extends StatelessWidget {
  const _AccountEntryPage({
    required this.compact,
    required this.emailController,
    required this.authenticating,
    required this.errorText,
    required this.onGoogle,
    required this.onApple,
    required this.onEmailNext,
  });

  final bool compact;
  final TextEditingController emailController;
  final bool authenticating;
  final String? errorText;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onEmailNext;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: 0,
      contentFlex: 1,
      headline: 'Fast geschafft.',
      body: 'Speichere deine Deals\nund starte sofort.',
      content: Column(
        children: <Widget>[
          _SocialAuthButton(
            label: 'Mit Google weiter',
            mark: 'G',
            onTap: authenticating ? null : onGoogle,
          ),
          const SizedBox(height: 12),
          _SocialAuthButton(
            label: 'Mit Apple weiter',
            mark: 'apple',
            onTap: authenticating ? null : onApple,
          ),
          const SizedBox(height: 22),
          const _DividerLabel(label: 'oder'),
          const SizedBox(height: 16),
          _GlassTextField(
            controller: emailController,
            hintText: context.t('E-Mail eingeben'),
            keyboardType: TextInputType.emailAddress,
            icon: Icons.mail_outline_rounded,
          ),
          if (errorText != null) ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(text: errorText!),
          ],
        ],
      ),
      primaryLabel: authenticating ? 'Einen Moment...' : 'Weiter',
      onPrimary: authenticating ? null : onEmailNext,
    );
  }
}

class _PasswordPage extends StatefulWidget {
  const _PasswordPage({
    required this.compact,
    required this.controller,
    required this.obscure,
    required this.submitting,
    required this.errorText,
    required this.onObscureToggle,
    required this.onSubmit,
  });

  final bool compact;
  final TextEditingController controller;
  final bool obscure;
  final bool submitting;
  final String? errorText;
  final VoidCallback onObscureToggle;
  final VoidCallback onSubmit;

  @override
  State<_PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<_PasswordPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _PasswordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final password = widget.controller.text;
    return _PremiumStep(
      compact: widget.compact,
      visualFlex: 0,
      contentFlex: 1,
      headline: 'Sicheres\nPasswort',
      body: '',
      content: Column(
        children: <Widget>[
          _GlassTextField(
            controller: widget.controller,
            hintText: context.t('Passwort eingeben'),
            icon: Icons.lock_outline_rounded,
            obscureText: widget.obscure,
            suffix: IconButton(
              onPressed: widget.onObscureToggle,
              icon: Icon(
                widget.obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF5F6673),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PasswordRule(
            label: 'Mindestens 8 Zeichen',
            active: password.length >= 8,
          ),
          _PasswordRule(
            label: 'Mindestens 1 Zahl',
            active: RegExp(r'\d').hasMatch(password),
          ),
          _PasswordRule(
            label: 'Mindestens 1 Sonderzeichen',
            active: RegExp(r'[^A-Za-z0-9]').hasMatch(password),
          ),
          if (widget.errorText != null) ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(text: widget.errorText!),
          ],
        ],
      ),
      primaryLabel: widget.submitting
          ? 'Konto wird erstellt...'
          : 'Konto erstellen',
      onPrimary: widget.submitting ? null : widget.onSubmit,
    );
  }
}

class _SuccessPage extends StatelessWidget {
  const _SuccessPage({
    required this.compact,
    required this.motion,
    required this.onStart,
  });

  final bool compact;
  final Animation<double> motion;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _PremiumStep(
      compact: compact,
      visualFlex: compact ? 9 : 11,
      contentFlex: compact ? 8 : 7,
      visual: _SuccessOrbVisual(motion: motion),
      headline: 'Du bist drin.',
      body: 'Deine Deals warten schon.',
      visualBeforeHeadline: true,
      primaryLabel: 'Loslegen',
      onPrimary: onStart,
    );
  }
}

class _PremiumStep extends StatelessWidget {
  const _PremiumStep({
    required this.compact,
    required this.headline,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.visual,
    this.content,
    this.secondary,
    this.tertiary,
    this.visualFlex = 8,
    this.contentFlex = 9,
    this.fillContent = false,
    this.visualBeforeHeadline = false,
  });

  final bool compact;
  final String headline;
  final String body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final Widget? visual;
  final Widget? content;
  final Widget? secondary;
  final Widget? tertiary;
  final int visualFlex;
  final int contentFlex;
  final bool fillContent;
  final bool visualBeforeHeadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headlineStyle = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w900,
      color: AppColors.ink,
      height: 1.05,
      letterSpacing: -0.2,
    );

    final headlineBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(headline, style: headlineStyle),
        if (body.trim().isNotEmpty) ...<Widget>[
          SizedBox(height: compact ? 9 : 13),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF596170),
              height: 1.38,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );

    final middle = Column(
      children: <Widget>[
        if (visual != null && visualFlex > 0)
          Expanded(flex: visualFlex, child: visual!),
        if (content != null) ...<Widget>[
          if (visual != null) SizedBox(height: compact ? 10 : 14),
          fillContent
              ? Expanded(flex: contentFlex, child: content!)
              : Flexible(flex: contentFlex, child: content!),
        ],
        if (visual == null && content == null) const Spacer(),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 18),
      child: _OnboardingGlassSurface(
        child: Padding(
          padding: EdgeInsets.all(compact ? 18 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (visualBeforeHeadline && visual != null) ...<Widget>[
                Expanded(flex: visualFlex, child: visual!),
                SizedBox(height: compact ? 12 : 18),
                headlineBlock,
              ] else ...<Widget>[
                headlineBlock,
                SizedBox(height: compact ? 16 : 24),
                Expanded(child: middle),
              ],
              SizedBox(height: compact ? 12 : 16),
              _PrimaryGradientButton(label: primaryLabel, onTap: onPrimary),
              if (secondary != null) ...<Widget>[
                const SizedBox(height: 12),
                secondary!,
              ],
              if (tertiary != null) ...<Widget>[
                const SizedBox(height: 8),
                tertiary!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingGlassSurface extends StatefulWidget {
  const _OnboardingGlassSurface({required this.child});

  final Widget child;

  @override
  State<_OnboardingGlassSurface> createState() =>
      _OnboardingGlassSurfaceState();
}

class _OnboardingGlassSurfaceState extends State<_OnboardingGlassSurface> {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.88),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF7B7280).withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -12,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.92),
                      const Color(0xFFFFF3F7).withValues(alpha: 0.54),
                      const Color(0xFFF6F8FF).withValues(alpha: 0.40),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _HeroComposition extends StatelessWidget {
  const _HeroComposition({required this.motion});

  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, _) {
          final t = _loopPhase(motion, seconds: 12);
          return LayoutBuilder(
            builder: (context, constraints) {
              const horizontalSafetyInset = 6.0;
              final cardWidth = math.min(
                154.0,
                math.max(126.0, constraints.maxWidth * 0.40),
              );
              final cardHeight = math.min(
                constraints.maxHeight * 0.94,
                cardWidth * 1.36,
              );
              final centerLeft = (constraints.maxWidth - cardWidth) / 2;
              final sideTop = math.max(
                12.0,
                constraints.maxHeight - cardHeight - 4,
              );
              final centerTop = math.max(2.0, sideTop - 26);

              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _HeroStagePainter(t)),
                    ),
                  ),
                  Positioned(
                    left: horizontalSafetyInset,
                    top: sideTop + math.sin(t * 0.7) * 3,
                    child: Transform.rotate(
                      angle: -0.105 + math.sin(t * 0.8) * 0.012,
                      child: _PhotoDealCard(
                        asset: _WelcomeScreenState._assetCafe,
                        title: 'Café Mahlzeit',
                        badge: '-20%',
                        width: cardWidth,
                        height: cardHeight,
                        glowColor: const Color(0xFFFFB2C0),
                      ),
                    ),
                  ),
                  Positioned(
                    left: centerLeft + math.sin(t * 0.45) * 2,
                    top: centerTop + math.cos(t * 0.65) * 3,
                    child: Transform.rotate(
                      angle: 0.022 + math.sin(t * 0.9) * 0.008,
                      child: _PhotoDealCard(
                        asset: _WelcomeScreenState._assetPasta,
                        title: 'Pasta Brothers',
                        badge: '2 für 1',
                        width: cardWidth,
                        height: cardHeight,
                        glowColor: const Color(0xFFFFC986),
                      ),
                    ),
                  ),
                  Positioned(
                    right: horizontalSafetyInset,
                    top: sideTop + math.cos(t * 0.6) * 3,
                    child: Transform.rotate(
                      angle: 0.105 + math.cos(t * 0.7) * 0.012,
                      child: _PhotoDealCard(
                        asset: _WelcomeScreenState._assetBoutique,
                        title: 'Maison Store',
                        badge: '-15%',
                        width: cardWidth,
                        height: cardHeight,
                        glowColor: const Color(0xFFCDBBFF),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HeroStagePainter extends CustomPainter {
  const _HeroStagePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.50, size.height * 0.62);
    final glowRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.92,
      height: size.height * 0.62,
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.primary.withValues(alpha: 0.20),
          const Color(0xFFFFD9E4).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(glowRect);
    canvas.drawOval(glowRect, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.72);
    for (var i = 0; i < 3; i++) {
      final pulse = math.sin(t * 0.55 + i) * 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(math.sin(t + i) * 5, math.cos(t + i) * 3),
          width: size.width * (0.46 + i * 0.15) + pulse,
          height: size.height * (0.25 + i * 0.09) + pulse,
        ),
        ringPaint..color = Colors.white.withValues(alpha: 0.54 - i * 0.10),
      );
    }

    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 7; i++) {
      final x = size.width * (0.14 + i * 0.12);
      final y =
          size.height * (0.18 + (i.isEven ? 0.08 : 0.0)) + math.sin(t + i) * 6;
      final sparkle = 2.4 + math.sin(t * 1.2 + i) * 0.7;
      canvas.drawLine(
        Offset(x - sparkle, y),
        Offset(x + sparkle, y),
        sparklePaint,
      );
      canvas.drawLine(
        Offset(x, y - sparkle),
        Offset(x, y + sparkle),
        sparklePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeroStagePainter oldDelegate) {
    return oldDelegate.t != t;
  }
}

class _GlassCouponBooklet extends StatelessWidget {
  const _GlassCouponBooklet({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    final pageLift = (math.sin(phase * 1.12) + 1) / 2;
    return SizedBox(
      width: 132,
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 18,
            top: 22,
            child: Container(
              width: 98,
              height: 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.primary.withValues(alpha: 0.20),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16 + math.sin(phase * 0.7) * 1.2,
            top: 18,
            child: Transform.rotate(
              angle: -0.12,
              child: _CouponBookPage(
                width: 98,
                height: 66,
                color: const Color(0xFFFFEDF2),
                phase: phase + 1.2,
                muted: true,
              ),
            ),
          ),
          Positioned(
            left: 21,
            top: 14 + math.cos(phase * 0.8) * 1.2,
            child: Transform.rotate(
              angle: 0.07,
              child: _CouponBookPage(
                width: 98,
                height: 66,
                color: Colors.white.withValues(alpha: 0.92),
                phase: phase + 0.6,
                muted: true,
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 10 - pageLift * 4,
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(-0.16 - pageLift * 0.34)
                ..rotateZ(-0.025 + math.sin(phase) * 0.018),
              child: _CouponBookPage(
                width: 100,
                height: 68,
                color: Colors.white.withValues(alpha: 0.78),
                phase: phase,
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2 + math.sin(phase * 1.3) * 2,
            child: _CouponSparkle(phase: phase),
          ),
        ],
      ),
    );
  }
}

class _CouponBookPage extends StatelessWidget {
  const _CouponBookPage({
    required this.width,
    required this.height,
    required this.color,
    required this.phase,
    this.muted = false,
  });

  final double width;
  final double height;
  final Color color;
  final double phase;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: muted ? 0.08 : 0.16),
              blurRadius: muted ? 14 : 20,
              spreadRadius: -7,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _CouponBookPagePainter(phase: phase, muted: muted),
        ),
      ),
    );
  }
}

class _CouponBookPagePainter extends CustomPainter {
  const _CouponBookPagePainter({required this.phase, required this.muted});

  final double phase;
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sheen = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: muted ? 0.12 : 0.30),
          AppColors.storyEnd.withValues(alpha: muted ? 0.05 : 0.16),
          Colors.transparent,
        ],
        begin: Alignment(-1 + math.sin(phase) * 0.35, -1),
        end: Alignment(1 + math.sin(phase) * 0.35, 1),
      ).createShader(rect);
    canvas.drawRect(rect, sheen);

    final accentPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: muted ? 0.22 : 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = muted ? 1.2 : 1.8
      ..strokeCap = StrokeCap.round;
    final dashY = size.height * 0.46;
    for (var x = size.width * 0.14; x < size.width * 0.82; x += 8) {
      canvas.drawLine(Offset(x, dashY), Offset(x + 3.6, dashY), accentPaint);
    }

    final iconPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: muted ? 0.24 : 0.86);
    canvas.drawCircle(
      Offset(size.width * 0.23, size.height * 0.27),
      5.5,
      iconPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.70),
      4.2,
      iconPaint
        ..color = AppColors.primary.withValues(alpha: muted ? 0.14 : 0.42),
    );

    final linePaint = Paint()
      ..color = const Color(0xFF1E1E24).withValues(alpha: muted ? 0.16 : 0.42)
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.37, size.height * 0.25),
      Offset(size.width * 0.68, size.height * 0.25),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.68),
      Offset(size.width * 0.55, size.height * 0.68),
      linePaint..color = linePaint.color.withValues(alpha: muted ? 0.12 : 0.26),
    );
  }

  @override
  bool shouldRepaint(covariant _CouponBookPagePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.muted != muted;
  }
}

class _CouponSparkle extends StatelessWidget {
  const _CouponSparkle({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    final scale = 0.85 + math.sin(phase * 1.6) * 0.12;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.70),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          size: 13,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _HeroMicroBadge extends StatelessWidget {
  const _HeroMicroBadge({
    required this.phase,
    required this.icon,
    required this.label,
  });

  final double phase;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.sin(phase) * 0.025,
      child: _GlassPanel(
        borderRadius: 999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCompositionOldUnused extends StatelessWidget {
  const _HeroCompositionOldUnused({required this.motion});

  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final t = _loopPhase(motion, seconds: 12);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _HeroCityPainter(t),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 4 + math.sin(t * 0.9) * 4,
              bottom: 10 + math.cos(t) * 3,
              child: Transform.rotate(
                angle: -0.045 + math.sin(t) * 0.018,
                child: const _PhotoDealCard(
                  asset: _WelcomeScreenState._assetCafe,
                  title: 'Café Mahlzeit',
                  badge: '-20%',
                  width: 118,
                  height: 112,
                  glowColor: Color(0xFFFF87A0),
                ),
              ),
            ),
            Positioned(
              right: 2 + math.cos(t * 0.85) * 5,
              bottom: 22 + math.sin(t * 0.7) * 4,
              child: Transform.rotate(
                angle: 0.075 + math.cos(t) * 0.015,
                child: const _PhotoDealCard(
                  asset: _WelcomeScreenState._assetPasta,
                  title: 'Pasta Brothers',
                  badge: '2 für 1',
                  width: 118,
                  height: 112,
                  glowColor: Color(0xFFFFC36F),
                ),
              ),
            ),
            Positioned(
              left: 144 + math.cos(t * 0.75) * 6,
              top: 100 + math.sin(t * 1.1) * 5,
              child: Transform.rotate(
                angle: -0.18 + math.sin(t * 0.8) * 0.025,
                child: _FloatingDiscountTile(phase: t),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrustCouponPlacesVisual extends StatefulWidget {
  const _TrustCouponPlacesVisual({required this.motion});

  final Animation<double> motion;

  @override
  State<_TrustCouponPlacesVisual> createState() =>
      _TrustCouponPlacesVisualState();
}

class _TrustCouponPlacesVisualState extends State<_TrustCouponPlacesVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const coupons = <_TrustCouponData>[
      _TrustCouponData(
        asset: _WelcomeScreenState._assetCafe,
        store: 'Café Mahlzeit',
        category: 'Café',
        badge: '-20%',
        icon: Icons.local_cafe_rounded,
        glowColor: Color(0xFFFFB4C2),
      ),
      _TrustCouponData(
        asset: _WelcomeScreenState._assetBakery,
        store: 'Bäckerei Jung',
        category: 'Bäckerei',
        badge: '2 für 1',
        icon: Icons.bakery_dining_rounded,
        glowColor: Color(0xFFFFD38A),
      ),
      _TrustCouponData(
        asset: _WelcomeScreenState._assetBoutique,
        store: 'Maison Store',
        category: 'Shopping',
        badge: '-15%',
        icon: Icons.shopping_bag_rounded,
        glowColor: Color(0xFFC9B8FF),
      ),
      _TrustCouponData(
        asset: _WelcomeScreenState._assetPasta,
        store: 'Pasta Brothers',
        category: 'Restaurant',
        badge: '2 für 1',
        icon: Icons.restaurant_rounded,
        glowColor: Color(0xFFFFC36F),
      ),
      _TrustCouponData(
        asset: _WelcomeScreenState._assetBoutique,
        store: 'Beauty Loft',
        category: 'Beauty',
        badge: '-10%',
        icon: Icons.spa_rounded,
        glowColor: Color(0xFFFFB7DE),
      ),
      _TrustCouponData(
        asset: _WelcomeScreenState._assetCafe,
        store: 'Barber Club',
        category: 'Barber',
        badge: '-5 €',
        icon: Icons.content_cut_rounded,
        glowColor: Color(0xFFB7D8FF),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final gap = width < 330 ? 8.0 : 10.0;
        final availableHeight = math.max(118.0, height);
        final cardWidth = math.max(78.0, (width - gap * 2) / 3);
        final preferredHeight = cardWidth * (width < 340 ? 1.08 : 1.18);
        final maxHeight = math.max(46.0, (availableHeight - gap) / 2);
        final cardHeight = math
            .min(preferredHeight, maxHeight)
            .clamp(54.0, 146.0)
            .toDouble();
        final stageHeight = cardHeight * 2 + gap;

        return Center(
          child: SizedBox(
            height: stageHeight,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value * math.pi * 2;
                  return Column(
                    children: <Widget>[
                      Row(
                        children: List<Widget>.generate(3, (index) {
                          return _TrustCouponGridItem(
                            data: coupons[index],
                            width: cardWidth,
                            height: cardHeight,
                            phase: t,
                            phaseOffset: index * 1.13,
                            trailingGap: index == 2 ? 0 : gap,
                          );
                        }),
                      ),
                      SizedBox(height: gap),
                      Row(
                        children: List<Widget>.generate(3, (index) {
                          final couponIndex = index + 3;
                          return _TrustCouponGridItem(
                            data: coupons[couponIndex],
                            width: cardWidth,
                            height: cardHeight,
                            phase: t,
                            phaseOffset: couponIndex * 1.13,
                            trailingGap: index == 2 ? 0 : gap,
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrustCouponData {
  const _TrustCouponData({
    required this.asset,
    required this.store,
    required this.category,
    required this.badge,
    required this.icon,
    required this.glowColor,
  });

  final String asset;
  final String store;
  final String category;
  final String badge;
  final IconData icon;
  final Color glowColor;
}

class _TrustCouponGridItem extends StatelessWidget {
  const _TrustCouponGridItem({
    required this.data,
    required this.width,
    required this.height,
    required this.phase,
    required this.phaseOffset,
    required this.trailingGap,
  });

  final _TrustCouponData data;
  final double width;
  final double height;
  final double phase;
  final double phaseOffset;
  final double trailingGap;

  @override
  Widget build(BuildContext context) {
    final float = math.sin(phase + phaseOffset);
    final drift = math.cos(phase + phaseOffset);
    final dx = drift * 2.0;
    final dy = float * 3.0;
    final angle =
        math.sin(phase + phaseOffset) * 0.014 +
        math.cos((phase * 2) + phaseOffset) * 0.004;
    final scale = 1 + math.sin(phase + phaseOffset) * 0.006;

    return Padding(
      padding: EdgeInsets.only(right: trailingGap),
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: _TrustCouponCard(data: data, width: width, height: height),
          ),
        ),
      ),
    );
  }
}

class _TrustCouponCard extends StatelessWidget {
  const _TrustCouponCard({
    required this.data,
    required this.width,
    required this.height,
  });

  final _TrustCouponData data;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final compact = width < 100 || height < 96;
    final radius = compact ? 16.0 : 20.0;
    final badgeFontSize = compact ? 11.0 : 12.5;
    final storeFontSize = compact ? 11.2 : 13.0;
    final categoryFontSize = compact ? 8.8 : 10.0;
    final iconSize = compact ? 11.5 : 13.0;

    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: data.glowColor.withValues(alpha: 0.28),
              blurRadius: compact ? 20 : 28,
              spreadRadius: -7,
              offset: const Offset(0, 15),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: compact ? 15 : 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipPath(
          clipper: _CouponTicketClipper(radius: radius),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(data.asset, fit: BoxFit.cover),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.72, -0.84),
                      radius: 0.78,
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.32),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.16),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.76),
                    ],
                    stops: const <double>[0, 0.42, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              const _CardPrismOverlay(),
              CustomPaint(
                painter: _CouponTicketDetailsPainter(
                  radius: radius,
                  compact: compact,
                ),
              ),
              Positioned(
                left: compact ? 7 : 9,
                top: compact ? 7 : 9,
                child: Container(
                  height: compact ? 24 : 28,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    data.badge,
                    textScaler: TextScaler.noScaling,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: badgeFontSize,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                      inherit: false,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: compact ? 8 : 10,
                right: compact ? 7 : 9,
                bottom: compact ? 8 : 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: compact ? 20 : 23,
                          height: compact ? 20 : 23,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            data.icon,
                            size: iconSize,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            data.category,
                            textScaler: TextScaler.noScaling,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.84),
                              fontSize: categoryFontSize,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: 0,
                              inherit: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 5 : 7),
                    Text(
                      data.store,
                      textScaler: TextScaler.noScaling,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: storeFontSize,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: 0,
                        inherit: false,
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 0.8,
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

class _CouponTicketClipper extends CustomClipper<Path> {
  const _CouponTicketClipper({required this.radius});

  final double radius;

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final notchRadius = math.min(size.width, size.height) * 0.085;
    final notches = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(0, size.height * 0.52),
          radius: notchRadius,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, size.height * 0.52),
          radius: notchRadius,
        ),
      );
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant _CouponTicketClipper oldClipper) {
    return oldClipper.radius != radius;
  }
}

class _CouponTicketDetailsPainter extends CustomPainter {
  const _CouponTicketDetailsPainter({
    required this.radius,
    required this.compact,
  });

  final double radius;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.46)
      ..strokeWidth = compact ? 0.8 : 1.0
      ..strokeCap = StrokeCap.round;
    final y = size.height * 0.52;
    final dashWidth = compact ? 3.0 : 4.0;
    final dashGap = compact ? 3.0 : 4.0;
    var x = size.width * 0.14;
    while (x < size.width * 0.86) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), linePaint);
      x += dashWidth + dashGap;
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.42);
    canvas.drawPath(
      _CouponTicketClipper(radius: radius).getClip(size),
      borderPaint,
    );

    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.white.withValues(alpha: 0.36),
          Colors.white.withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const <double>[0, 0.24, 0.72],
      ).createShader(Offset.zero & size);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.66, 0)
        ..lineTo(size.width * 0.18, size.height)
        ..lineTo(0, size.height)
        ..close(),
      sheenPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CouponTicketDetailsPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.compact != compact;
  }
}

class _LocalPlacesVisual extends StatelessWidget {
  const _LocalPlacesVisual({required this.motion});

  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final t = _loopPhase(motion, seconds: 15);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              top: 10 + math.sin(t) * 5,
              child: Transform.rotate(
                angle: -0.035,
                child: const _PhotoDealCard(
                  asset: _WelcomeScreenState._assetCafe,
                  title: 'Café Mahlzeit',
                  badge: '-20%',
                  width: 142,
                  height: 178,
                  glowColor: Color(0xFFFFB4C2),
                ),
              ),
            ),
            Positioned(
              left: 132,
              top: 2 + math.cos(t * 0.8) * 5,
              child: Transform.rotate(
                angle: 0.025,
                child: const _PhotoDealCard(
                  asset: _WelcomeScreenState._assetBakery,
                  title: 'Bäckerei Jung',
                  badge: '2 für 1',
                  width: 142,
                  height: 178,
                  glowColor: Color(0xFFFFD38A),
                ),
              ),
            ),
            Positioned(
              left: 264,
              top: 12 + math.sin(t * 0.7) * 5,
              child: Transform.rotate(
                angle: -0.018,
                child: const _PhotoDealCard(
                  asset: _WelcomeScreenState._assetBoutique,
                  title: 'Maison Store',
                  badge: '-15%',
                  width: 142,
                  height: 178,
                  glowColor: Color(0xFFC9B8FF),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: -2,
              child: _TinyProgressDots(activeIndex: 0, count: 4),
            ),
          ],
        );
      },
    );
  }
}

class _TinyProgressDots extends StatelessWidget {
  const _TinyProgressDots({required this.activeIndex, required this.count});

  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: AppDurations.fast,
          width: active ? 9 : 8,
          height: active ? 9 : 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AppColors.primary
                : const Color(0xFFDDE1EA).withValues(alpha: 0.92),
          ),
        );
      }),
    );
  }
}

class _LocationOrbitalVisual extends StatelessWidget {
  const _LocationOrbitalVisual({required this.motion});

  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final t = _loopPhase(motion, seconds: 18);
        return CustomPaint(
          painter: _OrbitalMapPainter(phase: t),
          child: Center(
            child: Transform.translate(
              offset: Offset(0, math.sin(t) * 4),
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: <Color>[
                      Color(0xFFFF8AA0),
                      Color(0xFFFF315A),
                      Color(0xFFD30E3C),
                    ],
                    stops: <double>[0, 0.62, 1],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.34),
                      blurRadius: 38,
                      spreadRadius: 4,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RadiusArcVisual extends StatelessWidget {
  const _RadiusArcVisual({required this.radiusKm, required this.onChanged});

  final double radiusKm;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset localPosition) {
          final width = constraints.maxWidth;
          final normalized = (localPosition.dx / width).clamp(0.0, 1.0);
          onChanged(5 + normalized * 45);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) => update(details.localPosition),
          onPanUpdate: (details) => update(details.localPosition),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: _RadiusArcPainter(progress: (radiusKm - 5) / 45),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: constraints.maxHeight * 0.18),
                  child: Text(
                    '${radiusKm.round()} km',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SuccessOrbVisual extends StatelessWidget {
  const _SuccessOrbVisual({required this.motion});

  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final t = _loopPhase(motion, seconds: 16);
        return CustomPaint(
          painter: _ConfettiPainter(phase: t),
          child: Center(
            child: Transform.scale(
              scale: 1 + math.sin(t) * 0.025,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: 188,
                    height: 188,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFB6A8FF).withValues(alpha: 0.12),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(
                            0xFF8D7DFF,
                          ).withValues(alpha: 0.34),
                          blurRadius: 62,
                          spreadRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  ClipOval(
                    child: Container(
                      width: 152,
                      height: 152,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.35, -0.45),
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.98),
                            const Color(0xFFE7ECFF),
                            const Color(0xFFB8A8FF),
                            const Color(0xFF8F7BFF),
                          ],
                          stops: const <double>[0.0, 0.42, 0.78, 1],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(painter: _HoloSheenPainter(t)),
                          ),
                          const Center(
                            child: Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 76,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardPrismOverlay extends StatelessWidget {
  const _CardPrismOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Colors.white.withValues(alpha: 0.34),
                  Colors.transparent,
                  const Color(0xFFFFBFD0).withValues(alpha: 0.18),
                  const Color(0xFFBFD7FF).withValues(alpha: 0.16),
                  Colors.transparent,
                ],
                stops: const <double>[0, 0.24, 0.48, 0.72, 1],
                begin: const Alignment(-1.0, -0.95),
                end: const Alignment(0.95, 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCityPainter extends CustomPainter {
  const _HeroCityPainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.transparent,
            const Color(0xFFFFEEF4).withValues(alpha: 0.72),
            const Color(0xFFEAF2FF).withValues(alpha: 0.48),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    final sunCenter = Offset(
      size.width * (0.30 + math.sin(phase * 0.15) * 0.015),
      size.height * 0.58,
    );
    canvas.drawCircle(
      sunCenter,
      size.width * 0.34,
      Paint()
        ..shader =
            RadialGradient(
              colors: <Color>[
                const Color(0xFFFFD9C9).withValues(alpha: 0.44),
                const Color(0xFFFFE8F0).withValues(alpha: 0.20),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: sunCenter, radius: size.width * 0.38),
            ),
    );

    final groundTop = size.height * 0.72;
    final path = Path()
      ..moveTo(0, groundTop + 26)
      ..cubicTo(
        size.width * 0.26,
        groundTop - 8,
        size.width * 0.64,
        groundTop + 24,
        size.width,
        groundTop - 4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            const Color(0xFFE6F5EA).withValues(alpha: 0.58),
            const Color(0xFFFFE4EA).withValues(alpha: 0.62),
          ],
        ).createShader(rect),
    );

    _drawBuilding(
      canvas,
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.42,
        size.width * 0.54,
        size.height * 0.34,
      ),
      const Color(0xFFFFFAF7),
      const Color(0xFFE7D7D0),
    );
    _drawBuilding(
      canvas,
      Rect.fromLTWH(
        size.width * 0.56,
        size.height * 0.34,
        size.width * 0.26,
        size.height * 0.42,
      ),
      const Color(0xFFF4F0FF),
      const Color(0xFFD7DDF0),
    );

    final treePaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFA4D7B7), Color(0xFF7FB895)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    for (final data in <({double x, double y, double r})>[
      (x: .15, y: .72, r: 17),
      (x: .72, y: .69, r: 20),
      (x: .84, y: .74, r: 15),
    ]) {
      final center = Offset(size.width * data.x, size.height * data.y);
      canvas.drawCircle(center, data.r, treePaint);
      canvas.drawRect(
        Rect.fromCenter(
          center: center + Offset(0, data.r + 9),
          width: 5,
          height: 24,
        ),
        Paint()..color = const Color(0xFFC7A284).withValues(alpha: 0.74),
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.38),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.16),
          ],
          stops: const <double>[0, 0.56, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
  }

  void _drawBuilding(Canvas canvas, Rect rect, Color fill, Color stroke) {
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = fill.withValues(alpha: 0.78));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke.withValues(alpha: 0.42),
    );
    final awningHeight = rect.height * 0.14;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left - 4,
          rect.top + rect.height * 0.28,
          rect.width + 8,
          awningHeight,
        ),
        const Radius.circular(8),
      ),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            const Color(0xFFFFB8C6).withValues(alpha: 0.74),
            const Color(0xFFFFE0E7).withValues(alpha: 0.62),
          ],
        ).createShader(rect),
    );

    final windowPaint = Paint()
      ..color = const Color(0xFFD7E7FF).withValues(alpha: 0.50);
    for (var i = 0; i < 4; i++) {
      final left = rect.left + rect.width * (0.14 + i * 0.20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, rect.top + rect.height * 0.13, 18, 24),
          const Radius.circular(4),
        ),
        windowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeroCityPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

class _HoloSheenPainter extends CustomPainter {
  const _HoloSheenPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final dx = math.sin(t * 0.65) * 0.28;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          Colors.transparent,
          Colors.white.withValues(alpha: 0.22),
          const Color(0xFFFFB4C7).withValues(alpha: 0.12),
          const Color(0xFFBFD8FF).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const <double>[0.05, 0.28, 0.48, 0.66, 0.95],
        begin: Alignment(-1 + dx, -1),
        end: Alignment(1 + dx, 1),
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    final glint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          Colors.transparent,
          Colors.white.withValues(alpha: 0.26),
          Colors.transparent,
        ],
        stops: const <double>[0.35, 0.50, 0.65],
        begin: Alignment(-1 + dx * 1.4, -1),
        end: Alignment(1 + dx * 1.4, 1),
      ).createShader(rect);
    canvas.drawRect(rect, glint);
  }

  @override
  bool shouldRepaint(covariant _HoloSheenPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}

class _PhotoDealCard extends StatelessWidget {
  const _PhotoDealCard({
    required this.asset,
    required this.title,
    required this.badge,
    required this.width,
    required this.height,
    this.glowColor = const Color(0xFFFF8EA5),
  });

  final String asset;
  final String title;
  final String badge;
  final double width;
  final double height;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glowColor.withValues(alpha: 0.30),
              blurRadius: 30,
              spreadRadius: -5,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(asset, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    stops: const <double>[0, 0.48, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              const _CardPrismOverlay(),
              Positioned(
                left: 10,
                bottom: 10,
                right: 10,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 34,
                child: _MiniGlassBadge(label: badge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingDiscountTile extends StatelessWidget {
  const _FloatingDiscountTile({required this.phase, this.compact = false});

  final double phase;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: 24,
      child: Container(
        width: compact ? 66 : 94,
        height: compact ? 62 : 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Colors.white.withValues(alpha: 0.94),
              Colors.white.withValues(alpha: 0.58),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(painter: _HoloSheenPainter(phase)),
            Center(
              child: Icon(
                Icons.local_offer_rounded,
                color: const Color(0xFFFF2D55),
                size: compact ? 28 : 38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGlassCard extends StatelessWidget {
  const _FeatureGlassCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF677080),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InterestGlassChip extends StatelessWidget {
  const _InterestGlassChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final DealCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE7ED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.78),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.045),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(_interestIcon(category), color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            AnimatedScale(
              duration: AppDurations.fast,
              scale: selected ? 1 : 0,
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 58,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 24,
                spreadRadius: -8,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryGlassButton extends StatelessWidget {
  const _SecondaryGlassButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEFE7EC)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({
    required this.label,
    required this.mark,
    required this.onTap,
  });

  final String label;
  final String mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isApple = mark.toLowerCase() == 'apple' || label.contains('Apple');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: onTap == null ? 0.56 : 1,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEFE7EC)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Center(
                  child: isApple
                      ? const Icon(Icons.apple, color: AppColors.ink, size: 24)
                      : Text(
                          mark,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: mark == 'G'
                                    ? const Color(0xFF4285F4)
                                    : AppColors.ink,
                              ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF697181)),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.78),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.52),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

class _PremiumRadiusSlider extends StatelessWidget {
  const _PremiumRadiusSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 10,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
        thumbColor: Colors.white,
        overlayColor: AppColors.primary.withValues(alpha: 0.10),
        trackShape: const _GradientSliderTrackShape(),
      ),
      child: Slider(value: value, min: 5, max: 50, onChanged: onChanged),
    );
  }
}

class _GradientSliderTrackShape extends SliderTrackShape {
  const _GradientSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 10;
    final trackLeft = offset.dx + 4;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - 8;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final canvas = context.canvas;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFE8EBF2));
    final activeRect = Rect.fromLTRB(
      rect.left,
      rect.top,
      thumbCenter.dx.clamp(rect.left, rect.right).toDouble(),
      rect.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, const Radius.circular(999)),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFFFF3B5F), Color(0xFF9E5CFF)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      thumbCenter,
      18,
      Paint()..color = AppColors.primary.withValues(alpha: 0.10),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, required this.borderRadius});

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF7E8AA0).withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
    );
  }
}

class _MiniGlassBadge extends StatelessWidget {
  const _MiniGlassBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.text,
    required this.actionText,
    required this.onTap,
  });

  final String text;
  final String actionText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF596170),
              fontWeight: FontWeight.w600,
            ),
            children: <TextSpan>[
              TextSpan(text: text),
              TextSpan(
                text: actionText,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainTextButton extends StatelessWidget {
  const _PlainTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF687080),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassInfoCard extends StatelessWidget {
  const _GlassInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: 18,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: AppColors.primary, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: Color(0xFFE6E9F1))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider(color: Color(0xFFE6E9F1))),
      ],
    );
  }
}

class _PasswordRule extends StatelessWidget {
  const _PasswordRule({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: active ? AppColors.success : const Color(0xFF9AA2B2),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: active ? const Color(0xFF2D7F61) : const Color(0xFF687080),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OrbitalMapPainter extends CustomPainter {
  const _OrbitalMapPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase;
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.primary.withValues(alpha: 0.12);
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.primary.withValues(alpha: 0.18),
          AppColors.primary.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 160));
    canvas.drawCircle(center, 160, fillPaint);
    for (final radius in <double>[64, 104, 146]) {
      canvas.drawCircle(center, radius, ringPaint);
    }
    _smallBubble(
      canvas,
      center + Offset(-104 + math.sin(t) * 7, -14 + math.cos(t) * 5),
      Icons.storefront,
    );
    _smallBubble(
      canvas,
      center + Offset(96 + math.cos(t * 0.8) * 7, 32 + math.sin(t) * 5),
      Icons.local_offer,
    );
    _smallBubble(
      canvas,
      center + Offset(82 + math.sin(t * 0.9) * 6, -72 + math.cos(t) * 6),
      Icons.percent,
    );
  }

  void _smallBubble(Canvas canvas, Offset center, IconData icon) {
    canvas.drawCircle(
      center,
      23,
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: AppColors.primary,
          fontFamily: icon.fontFamily,
          fontSize: 19,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitalMapPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

class _RadiusArcPainter extends CustomPainter {
  _RadiusArcPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.92);
    final radius = math.min(size.width * 0.42, size.height * 0.76);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final start = math.pi * 1.08;
    final sweep = math.pi * 0.84;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE5E9F2);
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFC7B6FF), Color(0xFFFF6684)],
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, trackPaint);
    final clampedProgress = progress.clamp(0, 1).toDouble();
    canvas.drawArc(rect, start, sweep * clampedProgress, false, progressPaint);
    final knobAngle = start + sweep * clampedProgress;
    final knob = Offset(
      center.dx + math.cos(knobAngle) * radius,
      center.dy + math.sin(knobAngle) * radius,
    );
    canvas.drawCircle(knob, 12, Paint()..color = Colors.white);
    canvas.drawCircle(knob, 8, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant _RadiusArcPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final t = phase;
    const colors = <Color>[
      Color(0xFFFF6D88),
      Color(0xFF7BC8B8),
      Color(0xFFFFB64D),
      Color(0xFF8E85FF),
    ];
    for (var i = 0; i < 18; i++) {
      final angle = (math.pi * 2 / 18) * i;
      final distance = (96 + (i.isEven ? 28 : 54) + math.sin(t + i) * 8)
          .toDouble();
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + math.sin(t + i) * 0.18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -7, 6, 14),
          const Radius.circular(3),
        ),
        Paint()..color = colors[i % colors.length].withValues(alpha: 0.72),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

IconData _interestIcon(DealCategory category) {
  return switch (category) {
    DealCategory.food => Icons.restaurant_rounded,
    DealCategory.cafe => Icons.local_cafe_rounded,
    DealCategory.breakfast => Icons.breakfast_dining_rounded,
    DealCategory.drinks => Icons.local_bar_rounded,
    DealCategory.beauty => Icons.spa_rounded,
    DealCategory.shopping => Icons.shopping_bag_rounded,
    DealCategory.online => Icons.language_rounded,
    DealCategory.leisure => Icons.directions_bike_rounded,
    _ => Icons.auto_awesome_rounded,
  };
}

const List<DealCategory> _supportedInterestCategories = <DealCategory>[
  DealCategory.food,
  DealCategory.cafe,
  DealCategory.breakfast,
  DealCategory.drinks,
  DealCategory.beauty,
  DealCategory.shopping,
  DealCategory.online,
  DealCategory.leisure,
];
