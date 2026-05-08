import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/web_image_proxy.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../shared/providers/app_providers.dart';
import 'deal_tag_chip.dart';
import 'metric_badge.dart';
import 'save_button.dart';

class CompactDealCard extends ConsumerWidget {
  const CompactDealCard({
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
    final colors = deal.palette.map(Color.new).toList();
    final start = colors.isEmpty ? theme.colorScheme.primary : colors.first;
    final end = colors.isEmpty ? theme.colorScheme.secondary : colors.last;
    final imageUrl = ref
        .watch(
          dealPresentationImageUrlProvider((
            businessId: business.id,
            dealId: deal.id,
          )),
        )
        .valueOrNull;
    final resolvedImageUrl = webSafeImageUrl(imageUrl);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCFD),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFF0E3E8)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 360;

              Widget buildOfferPanel({required bool stacked}) {
                return Container(
                  width: stacked ? double.infinity : 112,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color.lerp(start, Colors.white, 0.10) ?? start,
                        end,
                      ],
                    ),
                    image: resolvedImageUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(
                              resolvedImageUrl,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.fallback,
                            ),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: resolvedImageUrl == null
                            ? <Color>[Colors.transparent, Colors.transparent]
                            : <Color>[
                                Colors.black.withValues(alpha: 0.08),
                                Colors.black.withValues(alpha: 0.34),
                              ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.24),
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.20),
                              ),
                            ),
                            child: Text(
                              deal.tags.isEmpty
                                  ? 'Coupon'
                                  : deal.tags.first.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: stacked ? AppSpacing.lg : AppSpacing.xxl,
                          ),
                          Text(
                            deal.savingsBadgeLabel,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            deal.hasMeasuredSavings ? 'Vorteil' : 'Prüfen',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            deal.availabilityLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final details = Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                business.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                deal.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SaveButton(dealId: deal.id, compact: true),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      deal.priceHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      deal.socialProof,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: deal.tags.take(2).map((tag) {
                        return DealTagChip(tag: tag);
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        MetricBadge(
                          icon: Icons.place_outlined,
                          label: '${deal.distanceKm.toStringAsFixed(1)} km',
                          compact: true,
                        ),
                        MetricBadge(
                          icon: Icons.bookmark_outline_rounded,
                          label: '${deal.stats.saves} Saves',
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[buildOfferPanel(stacked: true), details],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    buildOfferPanel(stacked: false),
                    const _PerforationColumn(),
                    Expanded(child: details),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PerforationColumn extends StatelessWidget {
  const _PerforationColumn();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 18,
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(16, (index) {
          return Container(
            width: 2,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          );
        }),
      ),
    );
  }
}
