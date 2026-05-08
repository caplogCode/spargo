import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../constants/app_tokens.dart';
import '../utils/web_image_proxy.dart';

class ImmersiveCover extends StatelessWidget {
  const ImmersiveCover({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.showIcon = true,
    this.showBadge = true,
    this.borderRadius = AppRadii.xl,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.height = 220,
    this.alignment = Alignment.bottomLeft,
    this.imageUrl,
  });

  final List<int> palette;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final bool showIcon;
  final bool showBadge;
  final double borderRadius;
  final EdgeInsets padding;
  final double height;
  final Alignment alignment;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = palette.map(Color.new).toList();
    final start = colors.isEmpty ? theme.colorScheme.primary : colors.first;
    final middle = colors.length > 1 ? colors[1] : start;
    final end = colors.isEmpty ? theme.colorScheme.secondary : colors.last;
    final resolvedImageUrl = webSafeImageUrl(imageUrl);
    final hasImage = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;

    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(start, Colors.white, 0.08) ?? start,
            middle,
            end,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: start.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 240 || constraints.maxHeight < 148;
          final micro =
              constraints.maxWidth < 140 || constraints.maxHeight < 92;
          final inset = micro
              ? 10.0
              : compact
              ? 14.0
              : padding.horizontal / 2;
          final canShowBadge =
              showBadge &&
              badge != null &&
              constraints.maxWidth >= 150 &&
              constraints.maxHeight >= 94;
          final canShowIcon =
              showIcon &&
              constraints.maxWidth >= 92 &&
              constraints.maxHeight >= 92;
          final showSubtitle =
              subtitle.isNotEmpty && !micro && constraints.maxHeight >= 104;
          final titleStyle =
              (micro
                      ? theme.textTheme.titleSmall
                      : compact
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  );
          final subtitleStyle =
              (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.2,
                  );

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (hasImage)
                Positioned.fill(
                  child: Image.network(
                    resolvedImageUrl!,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        hasImage
                            ? Colors.black.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.14),
                        hasImage
                            ? Colors.black.withValues(alpha: 0.10)
                            : Colors.transparent,
                        hasImage
                            ? Colors.black.withValues(alpha: 0.48)
                            : Colors.black.withValues(alpha: 0.28),
                      ],
                      stops: const <double>[0, 0.40, 1],
                    ),
                  ),
                ),
              ),
              if (!hasImage)
                Positioned(
                  right: -constraints.maxWidth * 0.15,
                  top: -constraints.maxHeight * 0.18,
                  child: Container(
                    width: constraints.maxWidth * (micro ? 0.44 : 0.64),
                    height: constraints.maxWidth * (micro ? 0.44 : 0.64),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[
                          Colors.white.withValues(alpha: 0.22),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              if (canShowBadge)
                Positioned(
                  left: inset,
                  top: inset,
                  child: _CoverPill(label: badge!),
                ),
              if (canShowIcon)
                Positioned(
                  right: inset,
                  top: inset,
                  child: _CoverIconBadge(icon: icon, compact: compact),
                ),
              Align(
                alignment: alignment,
                child: Padding(
                  padding: EdgeInsets.all(inset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: micro ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (showSubtitle) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CoverPill extends StatelessWidget {
  const _CoverPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white, height: 1),
      ),
    );
  }
}

class _CoverIconBadge extends StatelessWidget {
  const _CoverIconBadge({required this.icon, required this.compact});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 38.0 : 44.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: compact ? 18 : 20, color: Colors.white),
    );
  }
}
