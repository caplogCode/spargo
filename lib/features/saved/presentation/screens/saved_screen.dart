import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/web_image_proxy.dart';
import '../../../../core/widgets/empty_state_card.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  DealCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = ref.watch(savedDealListProvider);
    final filterCategories = <DealCategory>{
      for (final deal in saved) deal.category,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));
    final visibleDeals = _selectedCategory == null
        ? saved
        : saved.where((deal) => deal.category == _selectedCategory).toList();

    final content = CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  if (!widget.embedded)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _HeaderCircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.embedded ? 'Merken' : 'Meine Merkliste',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${saved.length} gespeicherte Deals',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  _HeaderCircleButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _BookmarkFilterChip(
                  label: 'Alle',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                ...filterCategories.map((category) {
                  return _BookmarkFilterChip(
                    label: category.label,
                    selected: _selectedCategory == category,
                    onTap: () => setState(() => _selectedCategory = category),
                  );
                }),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (visibleDeals.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: EmptyStateCard(
                icon: Icons.bookmark_border_rounded,
                title: 'Noch nichts gespeichert',
                subtitle:
                    'Markiere ein paar gute Deals, dann wird deine Merkliste hier ganz ruhig und sauber aufgebaut.',
                action: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.search),
                  child: const Text('Deals finden'),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final deal = visibleDeals[index];
              final business = ref.read(businessByIdProvider(deal.businessId));

              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _BookmarkCard(
                  deal: deal,
                  business: business,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.dealDetail,
                    arguments: DealRouteArgs(deal.id),
                  ),
                ),
              );
            }, childCount: visibleDeals.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
      ],
    );

    if (widget.embedded) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFF2F2F7)),
        child: content,
      );
    }

    return Scaffold(backgroundColor: const Color(0xFFF2F2F7), body: content);
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      shadowColor: const Color(0x140F172A),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: const Color(0xFF171212), size: 20),
        ),
      ),
    );
  }
}

class _BookmarkFilterChip extends StatelessWidget {
  const _BookmarkFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.secondary : const Color(0xFFF6F6FA),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                color: selected ? AppColors.secondary : const Color(0xFFE5E5EC),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : AppColors.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookmarkCard extends ConsumerWidget {
  const _BookmarkCard({
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
    final accent = business.coverPalette.isEmpty
        ? theme.colorScheme.primary
        : Color(business.coverPalette.last);
    final imageUrlAsync = ref.watch(
      dealPresentationImageUrlProvider((
        businessId: business.id,
        dealId: deal.id,
      )),
    );
    final thumbnailUrl =
        imageUrlAsync.valueOrNull ??
        (business.imageUrl.trim().isNotEmpty
            ? business.imageUrl.trim()
            : deal.imageUrl.trim());

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x140F172A),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BookmarkThumbnail(
                imageUrl: thumbnailUrl,
                initials: _initials(business.name),
                palette: business.coverPalette,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF171212),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      business.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF6B6670),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      business.primaryBranch.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF918B86),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.place_rounded,
                          size: 14,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${deal.distanceKm.toStringAsFixed(1)} km',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF57524E),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(Icons.star_rounded, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          deal.stats.rating.toStringAsFixed(1),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF57524E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _BookmarkSaveButton(dealId: deal.id),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final parts = value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();
    return parts.isEmpty
        ? 'SP'
        : parts.map((part) => part.characters.first).join().toUpperCase();
  }
}

class _BookmarkThumbnail extends StatelessWidget {
  const _BookmarkThumbnail({
    required this.initials,
    required this.palette,
    this.imageUrl,
  });

  final String initials;
  final List<int> palette;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = palette.map(Color.new).toList();
    final start = colors.isEmpty ? const Color(0xFF40444F) : colors.first;
    final end = colors.length > 1 ? colors.last : start;
    final resolvedImageUrl = webSafeImageUrl(imageUrl);
    final hasLogo = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;

    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E6EC)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: hasLogo
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Image.network(
                resolvedImageUrl!,
                fit: BoxFit.contain,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, error, stackTrace) {
                  return _BookmarkThumbnailFallback(
                    initials: initials,
                    start: start,
                    end: end,
                  );
                },
              ),
            )
          : _BookmarkThumbnailFallback(
              initials: initials,
              start: start,
              end: end,
            ),
    );
  }
}

class _BookmarkThumbnailFallback extends StatelessWidget {
  const _BookmarkThumbnailFallback({
    required this.initials,
    required this.start,
    required this.end,
  });

  final String initials;
  final Color start;
  final Color end;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[start, Color.lerp(end, Colors.white, 0.16) ?? end],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BookmarkSaveButton extends ConsumerWidget {
  const _BookmarkSaveButton({required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedDealsProvider).contains(dealId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(savedDealsProvider.notifier).toggle(dealId),
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: AppColors.secondary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
