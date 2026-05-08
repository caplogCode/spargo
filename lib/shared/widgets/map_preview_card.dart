import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';

class MapPreviewCard extends StatelessWidget {
  const MapPreviewCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          height: 236,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: theme.dividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: CustomPaint(painter: _MapPainter(theme))),
              Positioned(
                left: AppSpacing.lg,
                top: AppSpacing.lg,
                right: AppSpacing.lg,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.lg,
                bottom: AppSpacing.lg,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    'Tippe für Route',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
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

class _MapPainter extends CustomPainter {
  const _MapPainter(this.theme);

  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = theme.colorScheme.surfaceContainerLow;
    final road = Paint()
      ..color = theme.colorScheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = theme.colorScheme.outlineVariant.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final pin = Paint()..color = theme.colorScheme.secondary;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      background,
    );

    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.42,
        size.width * 0.46,
        size.height * 0.52,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.66,
        size.width,
        size.height * 0.28,
      );
    canvas.drawPath(path, road);

    for (final multiplier in <double>[0.16, 0.34, 0.58, 0.82]) {
      final lane = Path()
        ..moveTo(size.width * multiplier, 0)
        ..quadraticBezierTo(
          size.width * (multiplier + 0.06),
          size.height * 0.4,
          size.width * (multiplier - 0.04),
          size.height,
        );
      canvas.drawPath(lane, minor);
    }

    for (final point in <Offset>[
      Offset(size.width * 0.24, size.height * 0.56),
      Offset(size.width * 0.52, size.height * 0.4),
      Offset(size.width * 0.78, size.height * 0.62),
    ]) {
      canvas.drawCircle(point, 8, pin);
      canvas.drawCircle(
        point.translate(0, -6),
        4,
        Paint()..color = Colors.white,
      );
    }

    final dotPaint = Paint()
      ..color = theme.colorScheme.secondary.withValues(alpha: 0.14);
    for (var i = 0; i < 18; i++) {
      final offset = Offset(
        (i * 31) % size.width,
        (math.sin(i.toDouble()) * 26 + size.height * 0.5).abs() % size.height,
      );
      canvas.drawCircle(offset, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}
