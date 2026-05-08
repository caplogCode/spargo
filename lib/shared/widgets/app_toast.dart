import 'dart:ui';

import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../theme/app_colors.dart';

enum AppToastType { error, success, info }

void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.error,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null || message.trim().isEmpty) {
    return;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: _AppToastContent(message: message.trim(), type: type),
        duration: Duration(
          milliseconds: type == AppToastType.error ? 4200 : 2800,
        ),
        margin: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
        ),
        padding: EdgeInsets.zero,
      ),
    );
}

class _AppToastContent extends StatelessWidget {
  const _AppToastContent({required this.message, required this.type});

  final String message;
  final AppToastType type;

  Color get _accent {
    return switch (type) {
      AppToastType.error => AppColors.primary,
      AppToastType.success => const Color(0xFF19B66A),
      AppToastType.info => const Color(0xFF5C73F2),
    };
  }

  IconData get _icon {
    return switch (type) {
      AppToastType.error => Icons.error_outline_rounded,
      AppToastType.success => Icons.check_circle_outline_rounded,
      AppToastType.info => Icons.info_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 30,
                spreadRadius: -8,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                spreadRadius: -8,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        accent.withValues(alpha: 0.95),
                        const Color(0xFFFF86A0).withValues(
                          alpha: type == AppToastType.error ? 0.95 : 0.35,
                        ),
                      ],
                    ),
                  ),
                  child: Icon(_icon, color: Colors.white, size: 19),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
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
