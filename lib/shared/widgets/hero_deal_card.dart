import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/icon_resolver.dart';
import '../../core/widgets/immersive_cover.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../shared/providers/app_providers.dart';
import 'deal_tag_chip.dart';
import 'metric_badge.dart';
import 'save_button.dart';

class HeroDealCard extends ConsumerWidget {
  const HeroDealCard({
    super.key,
    required this.deal,
    required this.business,
    required this.onTap,
  });

  final Deal deal;
  final Business business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final imageUrl = ref
        .watch(
          dealPresentationImageUrlProvider((
            businessId: business.id,
            dealId: deal.id,
          )),
        )
        .valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(34),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCFD),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFF0E3E8)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.055),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  blurRadius: 34,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxHeight < 470 || constraints.maxWidth < 340;
                final extraCompact =
                    constraints.maxHeight < 410 || constraints.maxWidth < 320;
                final coverHeight = extraCompact
                    ? 148.0
                    : (compact ? 170.0 : 220.0);
                final bodyPadding = extraCompact
                    ? AppSpacing.md
                    : (compact ? AppSpacing.lg : AppSpacing.xl);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Stack(
                      children: <Widget>[
                        Hero(
                          tag: 'deal-${deal.id}',
                          child: ImmersiveCover(
                            palette: deal.palette,
                            title: deal.title,
                            subtitle: business.name,
                            icon: iconForCategory(deal.category),
                            badge: deal.availabilityLabel,
                            showIcon: false,
                            height: coverHeight,
                            borderRadius: 30,
                            imageUrl: imageUrl,
                          ),
                        ),
                        Positioned(
                          top: AppSpacing.lg,
                          right: AppSpacing.lg,
                          child: SaveButton(dealId: deal.id),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(bodyPadding),
                        child: LayoutBuilder(
                          builder: (context, bodyConstraints) {
                            final tightBody =
                                extraCompact || bodyConstraints.maxHeight < 196;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            business.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs,
                                          ),
                                          Text(
                                            deal.title,
                                            maxLines: tightBody ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                (tightBody
                                                        ? theme
                                                              .textTheme
                                                              .titleLarge
                                                        : compact
                                                        ? theme
                                                              .textTheme
                                                              .titleLarge
                                                        : theme
                                                              .textTheme
                                                              .headlineSmall)
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: tightBody
                                            ? AppSpacing.sm
                                            : AppSpacing.md,
                                        vertical: tightBody
                                            ? AppSpacing.xs
                                            : AppSpacing.sm,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: <Color>[
                                            Color(0xFFFFEEF2),
                                            Colors.white,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.pill,
                                        ),
                                        border: Border.all(
                                          color: const Color(0xFFFFD7E1),
                                        ),
                                      ),
                                      child: Text(
                                        deal.savingsBadgeLabel,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.secondary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: tightBody
                                      ? AppSpacing.xs
                                      : AppSpacing.sm,
                                ),
                                Text(
                                  deal.priceHint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                if (!tightBody) ...<Widget>[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    deal.socialProof,
                                    maxLines: compact ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                                if (!tightBody) ...<Widget>[
                                  SizedBox(
                                    height: compact
                                        ? AppSpacing.sm
                                        : AppSpacing.md,
                                  ),
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    runSpacing: AppSpacing.xs,
                                    children: deal.tags
                                        .take(compact ? 1 : 3)
                                        .map((tag) => DealTagChip(tag: tag))
                                        .toList(),
                                  ),
                                ],
                                const Spacer(),
                                Wrap(
                                  spacing: AppSpacing.xs,
                                  runSpacing: AppSpacing.xs,
                                  children: <Widget>[
                                    MetricBadge(
                                      icon: Icons.place_outlined,
                                      label:
                                          '${deal.distanceKm.toStringAsFixed(1)} km',
                                    ),
                                    MetricBadge(
                                      icon: Icons.star_rounded,
                                      label: deal.ratingLabel,
                                    ),
                                    if (!tightBody && !compact)
                                      MetricBadge(
                                        icon: Icons.bookmark_outline_rounded,
                                        label: '${deal.stats.saves} Saves',
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
