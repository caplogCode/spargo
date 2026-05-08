import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, required this.onTap, this.size = 46});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFEFE7EC)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF7B727B).withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.ink,
          size: 21,
        ),
      ),
    );
  }
}
