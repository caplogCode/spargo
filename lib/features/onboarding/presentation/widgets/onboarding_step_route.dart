import 'package:flutter/material.dart';

Route<T> buildOnboardingStepRoute<T>(Widget child, {bool forward = true}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final beginOffset = forward
          ? const Offset(0.2, 0)
          : const Offset(-0.2, 0);

      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
            child: pageChild,
          ),
        ),
      );
    },
  );
}

Future<T?> replaceOnboardingStep<T>(
  BuildContext context,
  Widget child, {
  bool forward = true,
}) {
  return Navigator.of(
    context,
  ).pushReplacement<T, T>(buildOnboardingStepRoute<T>(child, forward: forward));
}
