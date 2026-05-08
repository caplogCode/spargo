import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CoverActionButton extends StatelessWidget {
  const CoverActionButton({
    super.key,
    required this.onTap,
    this.icon,
    this.child,
    this.size = 42,
  }) : assert(icon != null || child != null);

  final VoidCallback onTap;
  final IconData? icon;
  final Widget? child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.56)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child:
                child ??
                Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          ),
        ).animate().fadeIn(duration: 220.ms),
      ),
    );
  }
}
