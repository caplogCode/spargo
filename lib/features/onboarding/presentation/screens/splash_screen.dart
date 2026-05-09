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
    duration: const Duration(milliseconds: 1320),
  )..forward();

  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.62, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _logoScale = Tween<double>(begin: 0.94, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.10, 0.76, curve: Curves.easeOutBack),
        ),
      );

  late final Animation<double> _logoLift = Tween<double>(begin: 22, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.04, 0.70, curve: Curves.easeOutCubic),
        ),
      );

  late final Animation<double> _glowReveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.04, 0.84, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _exitReveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.68, 1.0, curve: Curves.easeInOutCubic),
  );

  Timer? _timer;
  bool _minimumFinished = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1180), () {
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
      value: SystemUiOverlayStyle.dark,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openNext,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final size = MediaQuery.sizeOf(context);
              final exitOpacity = Tween<double>(
                begin: 0.0,
                end: 1.0,
              ).evaluate(_exitReveal);
              final exitScale = Tween<double>(
                begin: 0.48,
                end: 3.4,
              ).evaluate(_exitReveal);
              final wordmarkWidth = (size.width * 0.58)
                  .clamp(188.0, 264.0)
                  .toDouble();

              return Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Colors.white,
                            AppColors.background,
                            Color(0xFFFFEEF3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -58,
                    right: -92,
                    child: _SplashGlow(
                      size: 240,
                      color: AppColors.primary,
                      opacity: 0.11 + (_glowReveal.value * 0.11),
                    ),
                  ),
                  Positioned(
                    left: -86,
                    bottom: 82,
                    child: _SplashGlow(
                      size: 210,
                      color: const Color(0xFFFF9DB4),
                      opacity: 0.08 + (_glowReveal.value * 0.08),
                    ),
                  ),
                  Positioned(
                    top: size.height * 0.26,
                    left: size.width * 0.18,
                    child: _SplashSpark(
                      progress: _glowReveal.value,
                      size: 5,
                      delay: 0.08,
                    ),
                  ),
                  Positioned(
                    right: size.width * 0.20,
                    top: size.height * 0.31,
                    child: _SplashSpark(
                      progress: _glowReveal.value,
                      size: 7,
                      delay: 0.24,
                    ),
                  ),
                  Positioned(
                    right: size.width * 0.28,
                    bottom: size.height * 0.33,
                    child: _SplashSpark(
                      progress: _glowReveal.value,
                      size: 4,
                      delay: 0.44,
                    ),
                  ),
                  Center(
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: Transform.translate(
                        offset: Offset(0, _logoLift.value),
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: wordmarkWidth + 56,
                                height: wordmarkWidth * 0.58,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(36),
                                  color: Colors.white.withValues(alpha: 0.62),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.10,
                                      ),
                                      blurRadius: 42,
                                      offset: const Offset(0, 22),
                                    ),
                                  ],
                                ),
                                child: _AnimatedSpargoWordmark(
                                  progress: _controller.value,
                                  width: wordmarkWidth,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _SplashTagline(progress: _glowReveal.value),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.74),
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: _SplashProgressTrack(progress: _glowReveal.value),
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
                                color: Colors.white.withValues(alpha: 0.74),
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

class _AnimatedSpargoWordmark extends StatelessWidget {
  const _AnimatedSpargoWordmark({required this.progress, required this.width});

  final double progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final letters = <_SplashLetterData>[
      const _SplashLetterData('s', AppColors.ink),
      const _SplashLetterData('p', AppColors.ink),
      const _SplashLetterData('a', AppColors.ink),
      const _SplashLetterData('r', AppColors.ink),
      const _SplashLetterData('G', AppColors.primary, italic: true),
      const _SplashLetterData('O', AppColors.primary, italic: true),
    ];
    const fontSize = 64.0;

    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List<Widget>.generate(letters.length, (index) {
            final start = index * 0.055;
            final value = ((progress - start) / 0.42).clamp(0.0, 1.0);
            final eased = Curves.easeOutCubic.transform(value);
            final data = letters[index];
            return Opacity(
              opacity: eased,
              child: Transform.translate(
                offset: Offset(0, (1 - eased) * 18),
                child: Transform.scale(
                  scale: 0.86 + (eased * 0.14),
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == 3 ? 2 : 0,
                      left: index == 4 ? 2 : 0,
                    ),
                    child: Text(
                      data.letter,
                      style: TextStyle(
                        color: data.color,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        fontStyle: data.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        height: 0.94,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _SplashLetterData {
  const _SplashLetterData(this.letter, this.color, {this.italic = false});

  final String letter;
  final Color color;
  final bool italic;
}

class _SplashTagline extends StatelessWidget {
  const _SplashTagline({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final opacity = Curves.easeOutCubic.transform(
      ((progress - 0.32) / 0.68).clamp(0.0, 1.0),
    );

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 10),
        child: Text(
          'Deals in deiner Nähe',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _SplashProgressTrack extends StatelessWidget {
  const _SplashProgressTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 5,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: FractionallySizedBox(
        widthFactor: (0.22 + progress * 0.78).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashSpark extends StatelessWidget {
  const _SplashSpark({
    required this.progress,
    required this.size,
    required this.delay,
  });

  final double progress;
  final double size;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final value = ((progress - delay) / 0.72).clamp(0.0, 1.0);
    final opacity = Curves.easeOutCubic.transform(value);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: 0.5 + (opacity * 0.5),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 18,
                spreadRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashGlow extends StatelessWidget {
  const _SplashGlow({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: size * 0.42,
            spreadRadius: size * 0.12,
          ),
        ],
      ),
    );
  }
}
