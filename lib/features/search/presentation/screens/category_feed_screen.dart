import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/compact_deal_card.dart';
import '../../../../theme/app_colors.dart';

class CategoryFeedScreen extends ConsumerWidget {
  const CategoryFeedScreen({super.key, required this.category});

  final DealCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref
        .watch(dealsProvider)
        .where((deal) => deal.category == category)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: deals.isEmpty
          ? _CategoryEmptyState(category: category)
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: deals.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final deal = deals[index];
                final business = ref.read(
                  businessByIdProvider(deal.businessId),
                );
                return CompactDealCard(
                  deal: deal,
                  business: business,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.dealDetail,
                    arguments: DealRouteArgs(deal.id),
                  ),
                );
              },
            ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({required this.category});

  final DealCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: <Widget>[
        const _EmptyBackground(),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFFDCE4)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            AppColors.primary.withValues(alpha: 0.10),
                            AppColors.primary.withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                      child: const Icon(
                        Ionicons.search_outline,
                        color: AppColors.primary,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Noch nichts in ${category.label}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sobald sparGO passende Deals in dieser Kategorie findet, erscheinen sie hier automatisch.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.45,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.search),
                      icon: const Icon(Ionicons.search_outline),
                      label: const Text('Zur Suche'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyBackground extends StatelessWidget {
  const _EmptyBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.background,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
