import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';
import '../../../app_shell/presentation/main_shell.dart';
import '../../../business/presentation/screens/business_dashboard_screen.dart';
import '../../../business/presentation/screens/business_onboarding_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 980),
  )..forward();

  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.42, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _logoScale = Tween<double>(begin: 0.90, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.56, curve: Curves.easeOutBack),
        ),
      );

  late final Animation<double> _logoLift = Tween<double>(begin: 16, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.46, curve: Curves.easeOutCubic),
        ),
      );

  late final Animation<double> _glowReveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.08, 0.70, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _exitReveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.56, 1.0, curve: Curves.easeInOutCubic),
  );

  Timer? _timer;
  bool _minimumFinished = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 920), () {
      _minimumFinished = true;
      _openNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget? _resolveNextPage() {
    final authUser = ref.read(authUserProvider);
    if (authUser == null) {
      return const WelcomeScreen();
    }

    final session = ref.read(sessionControllerProvider);
    final needsUserOnboarding =
        !session.isBusinessAccount && !session.userOnboardingComplete;
    if (needsUserOnboarding) {
      final initialStep = session.user.favoriteCategories.isEmpty ? 3 : 4;
      return WelcomeScreen(initialStep: initialStep);
    }
    if (session.isBusinessAccount &&
        (session.needsBusinessSetup || !authUser.emailVerified)) {
      return const BusinessOnboardingScreen();
    }
    if (session.isBusinessAccount) {
      return const BusinessDashboardScreen();
    }
    return const MainShell();
  }

  void _openNext() {
    if (!mounted || _navigated || !_minimumFinished) {
      return;
    }

    final nextPage = _resolveNextPage();
    if (nextPage == null) {
      return;
    }

    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) => nextPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final slide =
              Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authUserProvider);
    final session = ref.watch(sessionControllerProvider);
    final readyForRoute = authUser == null || session.isAuthenticated;

    if (readyForRoute && _minimumFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNext());
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openNext,
        child: Scaffold(
          backgroundColor: AppColors.primary,
          body: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final size = MediaQuery.sizeOf(context);
              final logoWidth = (size.width * 0.54)
                  .clamp(196.0, 248.0)
                  .toDouble();
              final glowOpacity = 0.06 + (_glowReveal.value * 0.14);
              final exitOpacity = Tween<double>(
                begin: 0.0,
                end: 1.0,
              ).evaluate(_exitReveal);
              final exitScale = Tween<double>(
                begin: 0.34,
                end: 2.8,
              ).evaluate(_exitReveal);

              return Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: ColoredBox(color: AppColors.primary),
                  ),
                  Positioned(
                    top: -48,
                    right: -36,
                    child: _SplashCircle(
                      size: 176,
                      opacity: 0.08 + (_glowReveal.value * 0.04),
                    ),
                  ),
                  Positioned(
                    left: -34,
                    bottom: 96,
                    child: _SplashCircle(
                      size: 138,
                      opacity: 0.04 + (_glowReveal.value * 0.03),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 232,
                      height: 232,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.white.withValues(alpha: glowOpacity),
                            blurRadius: 96,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: Transform.translate(
                        offset: Offset(0, _logoLift.value),
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Image.asset(
                            'assets/branding/spargo_splashscreen.png',
                            width: logoWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.74),
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: Container(
                        width: 42 + (_glowReveal.value * 22),
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: exitOpacity,
                        child: Center(
                          child: Transform.scale(
                            scale: exitScale,
                            child: Container(
                              width: 168,
                              height: 168,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SplashCircle extends StatelessWidget {
  const _SplashCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
