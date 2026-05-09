import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';
import '../widgets/category_grid_card.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(categoryCountsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: <Widget>[
          const _CategoryBackground(),
          SafeArea(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Ionicons.arrow_back_outline),
                          style: IconButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurface,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Kategorien',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  sliver: SliverGrid.builder(
                    itemCount: DealCategory.values.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisSpacing: AppSpacing.lg,
                          crossAxisSpacing: AppSpacing.lg,
                          childAspectRatio: 0.98,
                        ),
                    itemBuilder: (context, index) {
                      final category = DealCategory.values[index];
                      return CategoryGridCard(
                        category: category,
                        activeDeals: counts[category] ?? 0,
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.categoryFeed,
                          arguments: CategoryFeedArgs(category),
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxxl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBackground extends StatelessWidget {
  const _CategoryBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Theme.of(context).colorScheme.surface,
            AppColors.background,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
