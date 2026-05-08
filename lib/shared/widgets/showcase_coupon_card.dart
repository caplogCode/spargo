import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/web_image_proxy.dart';
import '../../theme/app_colors.dart';

class ShowcaseCouponCardMetric {
  const ShowcaseCouponCardMetric({
    required this.icon,
    required this.label,
    this.maxWidth,
  });

  final IconData icon;
  final String label;
  final double? maxWidth;
}

class ShowcaseCouponCard extends StatelessWidget {
  const ShowcaseCouponCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.businessName,
    required this.highlightLabel,
    required this.topBadges,
    required this.metrics,
    required this.primaryActionLabel,
    required this.onTap,
    this.imageUrl,
    this.onSecondaryTap,
    this.secondaryIcon,
    this.highlighted = false,
    this.heroHeight = 154,
    this.statusLabel,
    this.statusIcon,
    this.statusColor,
  });

  final String title;
  final String subtitle;
  final String businessName;
  final String highlightLabel;
  final List<String> topBadges;
  final List<ShowcaseCouponCardMetric> metrics;
  final String primaryActionLabel;
  final VoidCallback onTap;
  final String? imageUrl;
  final VoidCallback? onSecondaryTap;
  final IconData? secondaryIcon;
  final bool highlighted;
  final double heroHeight;
  final String? statusLabel;
  final IconData? statusIcon;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final resolvedImageUrl = webSafeImageUrl(imageUrl);
    final hasImage = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;
    final normalizedStatusLabel = statusLabel?.trim() ?? '';
    final hasStatus = normalizedStatusLabel.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight =
                constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

            Widget buildDetails() {
              if (hasBoundedHeight) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Flexible(
                        child: LayoutBuilder(
                          builder: (context, detailConstraints) {
                            final availableHeight = detailConstraints.maxHeight;
                            final showSubtitle =
                                subtitle.trim().isNotEmpty &&
                                availableHeight >= 54;
                            final showStatus =
                                hasStatus &&
                                availableHeight >= (showSubtitle ? 86 : 72);
                            final showMetrics =
                                metrics.isNotEmpty &&
                                availableHeight >= (showStatus ? 110 : 84);
                            final visibleMetrics = showMetrics
                                ? (availableHeight < 108
                                          ? metrics.take(2)
                                          : metrics)
                                      .toList(growable: false)
                                : const <ShowcaseCouponCardMetric>[];

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  maxLines: availableHeight < 46 ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.02,
                                  ),
                                ),
                                if (showSubtitle) ...<Widget>[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    subtitle,
                                    maxLines: textScale > 1.12 ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                if (showStatus) ...<Widget>[
                                  const SizedBox(height: AppSpacing.sm),
                                  _CouponStatusRow(
                                    icon: statusIcon ?? Icons.schedule_rounded,
                                    label: normalizedStatusLabel,
                                    color:
                                        statusColor ??
                                        theme.colorScheme.primary,
                                  ),
                                ],
                                if (visibleMetrics.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: AppSpacing.sm),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    runSpacing: AppSpacing.xs,
                                    children: visibleMetrics
                                        .map((metric) {
                                          return _CouponMetaPill(
                                            icon: metric.icon,
                                            label: metric.label,
                                            maxWidth: metric.maxWidth,
                                          );
                                        })
                                        .toList(growable: false),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: <Color>[
                                    Color(0xFFF45B7D),
                                    AppColors.primary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      primaryActionLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (onSecondaryTap != null &&
                              secondaryIcon != null) ...<Widget>[
                            const SizedBox(width: AppSpacing.sm),
                            Material(
                              color: const Color(0xFFF4F4F8),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: onSecondaryTap,
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: Icon(
                                    secondaryIcon,
                                    color: const Color(0xFF36343B),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: textScale > 1.18 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.02,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: textScale > 1.12 ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (hasStatus) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      _CouponStatusRow(
                        icon: statusIcon ?? Icons.schedule_rounded,
                        label: normalizedStatusLabel,
                        color: statusColor ?? theme.colorScheme.primary,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: metrics
                          .map((metric) {
                            return _CouponMetaPill(
                              icon: metric.icon,
                              label: metric.label,
                              maxWidth: metric.maxWidth,
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: <Color>[
                                  Color(0xFFF45B7D),
                                  AppColors.primary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.18,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    primaryActionLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (onSecondaryTap != null &&
                            secondaryIcon != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          Material(
                            color: const Color(0xFFF4F4F8),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: onSecondaryTap,
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: Icon(
                                  secondaryIcon,
                                  color: const Color(0xFF36343B),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ),
              );
            }

            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFE),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: highlighted
                      ? const Color(0xFFFFD3DE)
                      : const Color(0xFFE7E7ED),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0x1A0F172A),
                    blurRadius: highlighted ? 28 : 22,
                    offset: const Offset(0, 14),
                  ),
                  if (highlighted)
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.72),
                    blurRadius: 0,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: heroHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (hasImage)
                          Image.network(
                            resolvedImageUrl!,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (context, error, stackTrace) {
                              return _CouponHeroFallback(theme: theme);
                            },
                          )
                        else
                          _CouponHeroFallback(theme: theme),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.black.withValues(alpha: 0.06),
                                Colors.black.withValues(alpha: 0.38),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: AppSpacing.md,
                          right: AppSpacing.md,
                          top: AppSpacing.md,
                          child: Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: topBadges
                                .map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.pill,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.22,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                        Positioned(
                          left: AppSpacing.md,
                          right: AppSpacing.md,
                          bottom: AppSpacing.md,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  businessName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.10,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  highlightLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasBoundedHeight)
                    Expanded(child: buildDetails())
                  else
                    buildDetails(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CouponHeroFallback extends StatelessWidget {
  const _CouponHeroFallback({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF91203A),
            AppColors.primary.withValues(alpha: 0.96),
            const Color(0xFFF07B94),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -6,
            top: -10,
            child: Opacity(
              opacity: 0.16,
              child: Image.asset(
                'assets/branding/spargo_splashscreen.png',
                width: 142,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                'sparGO',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponMetaPill extends StatelessWidget {
  const _CouponMetaPill({
    required this.icon,
    required this.label,
    this.maxWidth,
  });

  final IconData icon;
  final String label;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F8),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: const Color(0xFFE7E7ED)),
        ),
        child: Row(
          mainAxisSize: maxWidth == null ? MainAxisSize.min : MainAxisSize.max,
          children: <Widget>[
            Icon(icon, size: 14, color: const Color(0xFF6A6872)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF17171C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponStatusRow extends StatelessWidget {
  const _CouponStatusRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tintedBackground = Color.lerp(color, Colors.white, 0.88) ?? color;
    final tintedBorder = Color.lerp(color, Colors.white, 0.72) ?? color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: tintedBackground,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: tintedBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF17171C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
