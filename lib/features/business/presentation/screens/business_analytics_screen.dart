import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/business_stats_card.dart';

class BusinessAnalyticsScreen extends ConsumerWidget {
  const BusinessAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final business = ref.watch(ownedBusinessProvider);
    final deals = ref.watch(businessDealsProvider(business.id));
    final stories = ref
        .watch(storiesProvider)
        .where((story) => story.businessId == business.id)
        .toList(growable: false);
    final redemptions = ref.watch(businessRedemptionsProvider);

    final totalViews = deals.fold<int>(
      business.analytics.views,
      (sum, deal) => sum + deal.stats.views,
    );
    final totalSaves = deals.fold<int>(
      business.analytics.saves,
      (sum, deal) => sum + deal.stats.saves,
    );
    final totalActivations = deals.fold<int>(
      business.analytics.activations,
      (sum, deal) => sum + deal.stats.activations,
    );
    final totalRedemptions = deals.fold<int>(
      business.analytics.redemptions,
      (sum, deal) => sum + deal.stats.redemptions,
    );
    final trend = business.analytics.trendPoints.isEmpty
        ? <int>[
            totalViews < 1 ? 6 : (totalViews ~/ 4).clamp(6, 48),
            totalSaves < 1 ? 8 : (totalSaves ~/ 3).clamp(8, 58),
            totalActivations < 1 ? 10 : (totalActivations ~/ 2).clamp(10, 72),
            totalRedemptions < 1 ? 12 : totalRedemptions.clamp(12, 92),
          ]
        : business.analytics.trendPoints;

    final statsCards = <Widget>[
      BusinessStatsCard(
        label: 'Reichweite',
        value: '$totalViews',
        delta: stories.isNotEmpty
            ? '${stories.length} Storys live'
            : 'Noch keine Story live',
        icon: Icons.visibility_outlined,
      ),
      BusinessStatsCard(
        label: 'Saves',
        value: '$totalSaves',
        delta: deals.isNotEmpty
            ? '${deals.length} Gutscheine insgesamt'
            : 'Noch keine Gutscheine',
        icon: Icons.bookmark_outline_rounded,
      ),
      BusinessStatsCard(
        label: 'Aktivierungen',
        value: '$totalActivations',
        delta: redemptions.isNotEmpty
            ? '${redemptions.length} P\u00e4sse insgesamt'
            : 'Noch kein Pass aktiv',
        icon: Icons.bolt_rounded,
      ),
      BusinessStatsCard(
        label: 'Einl\u00f6sungen',
        value: '$totalRedemptions',
        delta: totalRedemptions > 0
            ? 'Heute sauber erfasst'
            : 'Noch keine Einl\u00f6sung',
        icon: Icons.qr_code_scanner_rounded,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width < 520) {
                return Column(
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < statsCards.length;
                      index++
                    ) ...<Widget>[
                      statsCards[index],
                      if (index < statsCards.length - 1)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }

              final crossAxisCount = width >= 880 ? 4 : 2;
              final childAspectRatio = width >= 880 ? 1.35 : 1.18;

              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: childAspectRatio,
                children: statsCards,
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Trendverlauf',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Views, Saves, Aktivierungen und Einl\u00f6sungen im \u00dcberblick.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 180,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: trend
                        .map((point) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Container(
                                height: point
                                    .toDouble()
                                    .clamp(12, 160)
                                    .toDouble(),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.sm,
                                  ),
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
