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

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchControllerProvider).query,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(searchControllerProvider.notifier).updateQuery(_controller.text);
    Navigator.of(context).pushNamed(
      AppRoutes.searchResults,
      arguments: SearchResultsArgs(_controller.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(categoryCountsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: <Widget>[
          const _SearchBackground(),
          SafeArea(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _SearchHeader(
                      controller: _controller,
                      onSubmit: _submit,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xxl,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Kategorien',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xxl,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _QuickSearches(
                      onSelected: (term) {
                        _controller.text = term;
                        _submit();
                      },
                    ),
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

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
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
              'Suchen',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEDE6EA)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SizedBox(
            height: 56,
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: context.t('Business, Kategorie, Stadt oder Deal'),
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: Icon(
                  Ionicons.search_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 28,
                ),
                suffixIcon: IconButton(
                  onPressed: onSubmit,
                  icon: Icon(
                    Ionicons.arrow_forward_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 26,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.22),
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickSearches extends StatelessWidget {
  const _QuickSearches({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Schnelleinstiege',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children:
              <String>[
                'Nur heute',
                'Brunch',
                'Date Night',
                'Beauty',
                'Bremen',
              ].map((term) {
                return ActionChip(
                  label: Text(term),
                  onPressed: () => onSelected(term),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _SearchBackground extends StatelessWidget {
  const _SearchBackground();

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
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 80,
            right: -70,
            child: _Glow(size: 220, color: AppColors.primary),
          ),
          Positioned(
            top: 360,
            left: -80,
            child: _Glow(size: 180, color: const Color(0xFFEFA9C2)),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.14),
              blurRadius: size * 0.42,
              spreadRadius: size * 0.16,
            ),
          ],
        ),
      ),
    );
  }
}
