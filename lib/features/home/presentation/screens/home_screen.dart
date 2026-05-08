import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/web_image_proxy.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/compact_deal_card.dart';
import '../../../../shared/widgets/hero_deal_card.dart';
import '../../../../shared/widgets/horizontal_business_card.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../../shared/widgets/showcase_coupon_card.dart';
import '../../../../shared/widgets/story_bubble.dart';
import '../../../../theme/app_colors.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final ScrollController _scrollController = ScrollController();

  Future<void> _refresh() async {
    ref
        .read(publicCouponRefreshControllerProvider.notifier)
        .scheduleRefresh(force: true);
    ref.invalidate(homeFeedSectionsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = ref.watch(currentUserProvider);
    final level = ref.watch(userLevelProvider);
    final nextLevelTarget = ref.watch(nextLevelTargetProvider);
    final unreadNotifications = ref.watch(unreadNotificationCountProvider);
    final allDeals = ref.watch(dealsProvider);
    final deals = ref.watch(feedDealsProvider);
    final visiblePublicDeals = ref.watch(visiblePublicCouponDealsProvider);
    final recommendedDeals = ref.watch(recommendedDealsProvider);
    final influencerDeals = ref.watch(influencerDealsProvider);
    final stories = ref.watch(storiesProvider);
    final seenStories = ref.watch(storySeenProvider);
    final publicCouponStatus = ref.watch(publicCouponCacheStatusProvider);
    final savedDealIds = ref.watch(savedDealsProvider);

    final visiblePublicDealIds = visiblePublicDeals
        .map((deal) => deal.id)
        .toSet();
    final publicDeals = visiblePublicDealIds.isEmpty
        ? const <Deal>[]
        : allDeals
              .where((deal) => visiblePublicDealIds.contains(deal.id))
              .toList(growable: false);
    final nativePriorityDeals = <Deal>[
      ...recommendedDeals.where((deal) => !deal.isThirdParty),
      ...deals.where((deal) => !deal.isThirdParty),
      ...allDeals.where((deal) => !deal.isThirdParty),
    ];
    final publicPriorityDeals = <Deal>[
      ...visiblePublicDeals,
      ...publicDeals,
      ...recommendedDeals.where((deal) => deal.isThirdParty),
      ...deals.where((deal) => deal.isThirdParty),
      ...allDeals.where((deal) => deal.isThirdParty),
    ];
    final topCouponSeed = <Deal>[
      ...nativePriorityDeals,
      ...publicPriorityDeals,
    ];
    final seenTopCouponIds = <String>{};
    final topCoupons = topCouponSeed
        .where((deal) => seenTopCouponIds.add(deal.id))
        .take(8)
        .toList(growable: false);
    final now = DateTime.now();
    final todayDealCount = topCoupons
        .where(
          (deal) =>
              deal.validUntil.isAfter(now) &&
              deal.validUntil.difference(now).inHours <= 24,
        )
        .length;
    final nearbyDealCount = topCoupons
        .where((deal) => deal.distanceKm <= 5)
        .length;
    final previewStories = _storyRepresentativesForBusinesses(
      stories,
      seenStories,
      limit: 7,
    );
    final currentLevelFloor = (level - 1) * 250;
    final levelProgress =
        ((user.points - currentLevelFloor) /
                (nextLevelTarget - currentLevelFloor))
            .clamp(0.0, 1.0);

    const pinnedHeaderHeight = 160.0;
    final scrollContent = RefreshIndicator.adaptive(
      color: colorScheme.secondary,
      backgroundColor: colorScheme.surface,
      displacement: 28,
      edgeOffset: pinnedHeaderHeight,
      strokeWidth: 3,
      onRefresh: _refresh,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedSearchHeaderDelegate(
                height: pinnedHeaderHeight,
                backgroundColor: const Color(0xFFFFFAFC),
                borderColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    10,
                    AppSpacing.lg,
                    18,
                  ),
                  child: Column(
                    children: <Widget>[
                      _HomeHeaderTopBar(
                        level: level,
                        progress: levelProgress,
                        badgeCount: unreadNotifications,
                        onNotificationTap: () => Navigator.of(
                          context,
                        ).pushNamed(AppRoutes.notifications),
                      ),
                      const SizedBox(height: 10),
                      _HomeHeaderSearchBar(
                        onTap: () =>
                            Navigator.of(context).pushNamed(AppRoutes.search),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _HomeCategoryRail(
                onCategoryTap: (category) => Navigator.of(context).pushNamed(
                  AppRoutes.categoryFeed,
                  arguments: CategoryFeedArgs(category),
                ),
                onMoreTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.categories),
              ),
            ),
            SliverToBoxAdapter(
              child: _HomeStoriesSection(
                stories: stories,
                previewStories: previewStories,
                seenStories: seenStories,
                onSpargoTap: () => _showSpargoStoryPlaceholder(context),
                onSeeAllTap: previewStories.isEmpty
                    ? () => _showSpargoStoryPlaceholder(context)
                    : () {
                        final firstStory = _storyLaunchTarget(
                          stories,
                          previewStories.first,
                          seenStories,
                        );
                        Navigator.of(context).pushNamed(
                          AppRoutes.storyViewer,
                          arguments: StoryViewerArgs(storyId: firstStory.id),
                        );
                      },
                onStoryTap: (story) {
                  final targetStory = _storyLaunchTarget(
                    stories,
                    story,
                    seenStories,
                  );
                  Navigator.of(context).pushNamed(
                    AppRoutes.storyViewer,
                    arguments: StoryViewerArgs(storyId: targetStory.id),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _HomeTopDealsSection(
                deals: topCoupons,
                status: publicCouponStatus,
                businessForDeal: (deal) =>
                    ref.read(businessByIdProvider(deal.businessId)),
                onDealTap: (deal) => Navigator.of(context).pushNamed(
                  AppRoutes.dealDetail,
                  arguments: DealRouteArgs(deal.id),
                ),
                onEmptyTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.search),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _InviteFriendsCard(
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.inviteFriends),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                child: _HomeSmartCollectionsSection(
                  todayCount: todayDealCount,
                  nearbyCount: nearbyDealCount,
                  savedCount: savedDealIds.length,
                  verifiedCount: topCoupons.length,
                  onTodayTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.search),
                  onNearbyTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.discover),
                  onSavedTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.saved),
                  onVerifiedTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.categories),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[const _HomeAmbientGlow(), scrollContent],
    );

    if (widget.embedded) {
      return Material(color: const Color(0xFFFFFAFC), child: content);
    }

    return Scaffold(backgroundColor: const Color(0xFFFFFAFC), body: content);
  }
}

void _showSpargoStoryPlaceholder(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sparGO Story schließen',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _SpargoStoryPreviewOverlay();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _HomeAmbientGlow extends StatelessWidget {
  const _HomeAmbientGlow();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: -124,
      right: -118,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            width: 320,
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    Color(0x33FF2D63),
                    Color(0x18FFB6CB),
                    Color(0x00FFFFFF),
                  ],
                  stops: <double>[0, 0.42, 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpargoStoryPreviewOverlay extends StatefulWidget {
  const _SpargoStoryPreviewOverlay();

  @override
  State<_SpargoStoryPreviewOverlay> createState() =>
      _SpargoStoryPreviewOverlayState();
}

class _SpargoStoryPreviewOverlayState
    extends State<_SpargoStoryPreviewOverlay> {
  late final PageController _controller = PageController();
  int _index = 0;

  static const _pages = <_SpargoStoryPageData>[
    _SpargoStoryPageData(
      icon: Ionicons.sparkles_outline,
      title: 'Neue Aktionen',
      body:
          'Hier landen kurze Updates von lokalen Businesses: Tagesdeals, neue Drops und kleine Highlights.',
    ),
    _SpargoStoryPageData(
      icon: Ionicons.storefront_outline,
      title: 'Echte Einblicke',
      body:
          'Du siehst, was gerade vor Ort passiert: frische Ware, freie Termine, Events oder besondere Momente.',
    ),
    _SpargoStoryPageData(
      icon: Ionicons.ticket_outline,
      title: 'Direkt sichern',
      body:
          'Wenn dir etwas gefällt, merkst du es dir, aktivierst den Deal und löst ihn ruhig im Laden ein.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_index >= _pages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 430,
              maxHeight: size.height - 48,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFFF0F5)],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    const Positioned(
                      right: -80,
                      top: -80,
                      child: _StoryGlowOrb(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Row(
                                  children: List<Widget>.generate(
                                    _pages.length,
                                    (index) => Expanded(
                                      child: AnimatedContainer(
                                        duration: AppDurations.fast,
                                        height: 4,
                                        margin: EdgeInsets.only(
                                          right: index == _pages.length - 1
                                              ? 0
                                              : 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: index <= _index
                                              ? AppColors.primary
                                              : const Color(0xFFECE5EA),
                                          borderRadius: BorderRadius.circular(
                                            AppRadii.pill,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              IconButton.filled(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.ink,
                                  shadowColor: Colors.black.withValues(
                                    alpha: 0.12,
                                  ),
                                  elevation: 8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Expanded(
                            child: PageView.builder(
                              controller: _controller,
                              itemCount: _pages.length,
                              onPageChanged: (value) =>
                                  setState(() => _index = value),
                              itemBuilder: (context, index) {
                                final page = _pages[index];
                                return _SpargoStoryPage(page: page);
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: _goNext,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    _index == _pages.length - 1
                                        ? 'Verstanden'
                                        : 'Weiter',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Ionicons.arrow_forward_outline),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryGlowOrb extends StatelessWidget {
  const _StoryGlowOrb();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: 220,
        height: 220,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              Color(0x44FF2D63),
              Color(0x22FFA9C0),
              Color(0x00FFFFFF),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpargoStoryPageData {
  const _SpargoStoryPageData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _SpargoStoryPage extends StatelessWidget {
  const _SpargoStoryPage({required this.page});

  final _SpargoStoryPageData page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 122,
          height: 122,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(page.icon, color: AppColors.primary, size: 48),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.02,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF746A70),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HomeCategoryRail extends StatelessWidget {
  const _HomeCategoryRail({
    required this.onCategoryTap,
    required this.onMoreTap,
  });

  final ValueChanged<DealCategory> onCategoryTap;
  final VoidCallback onMoreTap;

  static const _items = <_HomeCategoryItemData>[
    _HomeCategoryItemData(
      label: 'Essen',
      category: DealCategory.food,
      icon: Ionicons.fast_food_outline,
    ),
    _HomeCategoryItemData(
      label: 'Cafés',
      category: DealCategory.cafe,
      icon: Ionicons.cafe_outline,
    ),
    _HomeCategoryItemData(
      label: 'Shopping',
      category: DealCategory.shopping,
      icon: Ionicons.bag_handle_outline,
    ),
    _HomeCategoryItemData(
      label: 'Beauty',
      category: DealCategory.beauty,
      icon: Ionicons.leaf_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          for (var index = 0; index < _items.length; index++) ...<Widget>[
            Expanded(
              child: _HomeCategoryTile(
                label: _items[index].label,
                icon: _items[index].icon,
                selected: index == 0,
                onTap: () => onCategoryTap(_items[index].category),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _HomeCategoryTile(
              label: 'Mehr',
              icon: Ionicons.grid_outline,
              selected: false,
              onTap: onMoreTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCategoryItemData {
  const _HomeCategoryItemData({
    required this.label,
    required this.category,
    required this.icon,
  });

  final String label;
  final DealCategory category;
  final IconData icon;
}

class _HomeCategoryTile extends StatelessWidget {
  const _HomeCategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? AppColors.primary : const Color(0xFF2A2427);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFE8EF) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.7,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStoriesSection extends StatelessWidget {
  const _HomeStoriesSection({
    required this.stories,
    required this.previewStories,
    required this.seenStories,
    required this.onSpargoTap,
    required this.onSeeAllTap,
    required this.onStoryTap,
  });

  final List<Story> stories;
  final List<Story> previewStories;
  final Set<String> seenStories;
  final VoidCallback onSpargoTap;
  final VoidCallback onSeeAllTap;
  final ValueChanged<Story> onStoryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        0,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Stories',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(
                    'Ansehen',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 116,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              children: <Widget>[
                _SpargoStoryBubble(onTap: onSpargoTap),
                ...previewStories.map((story) {
                  return StoryBubble(
                    story: story,
                    isSeen: _businessStoriesSeen(
                      stories,
                      story.businessId,
                      seenStories,
                    ),
                    onTap: () => onStoryTap(story),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpargoStoryBubble extends StatelessWidget {
  const _SpargoStoryBubble({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(44),
        child: SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.22),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFFFFB3C4,
                            ).withValues(alpha: 0.18),
                            blurRadius: 34,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFFFFB3C4), AppColors.primary],
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[
                                AppColors.primary,
                                Color(0xFFFF4D78),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'sparGO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'sparGO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTopDealsSection extends StatelessWidget {
  const _HomeTopDealsSection({
    required this.deals,
    required this.status,
    required this.businessForDeal,
    required this.onDealTap,
    required this.onEmptyTap,
  });

  final List<Deal> deals;
  final PublicCouponCacheStatus status;
  final Business Function(Deal deal) businessForDeal;
  final ValueChanged<Deal> onDealTap;
  final VoidCallback onEmptyTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Top Deals für dich',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEF3),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Heute in deiner Nähe',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (deals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _HomeEmptyDealsCard(status: status, onTap: onEmptyTap),
            )
          else
            SizedBox(
              height: 248,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: deals.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, index) {
                  final deal = deals[index];
                  return _HomeTopDealCard(
                    deal: deal,
                    business: businessForDeal(deal),
                    onTap: () => onDealTap(deal),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeTopDealCard extends ConsumerWidget {
  const _HomeTopDealCard({
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
    final width = (MediaQuery.sizeOf(context).width * 0.43)
        .clamp(166.0, 196.0)
        .toDouble();
    final imageUrlAsync = ref.watch(
      dealPresentationImageUrlProvider((
        businessId: business.id,
        dealId: deal.id,
      )),
    );
    final rawImageUrl =
        imageUrlAsync.valueOrNull ??
        (deal.imageUrl.trim().isNotEmpty
            ? deal.imageUrl.trim()
            : business.imageUrl.trim());
    final imageUrl = webSafeImageUrl(rawImageUrl);
    final isSaved = ref.watch(savedDealsProvider).contains(deal.id);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.055),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: 130,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (imageUrl != null)
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (context, error, stackTrace) =>
                                _DealImageFallback(category: deal.category),
                          )
                        else
                          _DealImageFallback(category: deal.category),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _DealBadge(label: _dealBadgeText(deal)),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: InkWell(
                            onTap: () => ref
                                .read(savedDealsProvider.notifier)
                                .toggle(deal.id),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isSaved
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        business.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${_categoryLabel(deal.category)} · ${deal.distanceKm.toStringAsFixed(1)} km',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7B7176),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEF3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                deal.savingsHighlightLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _DealPriceText(deal: deal),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DealPriceText extends StatelessWidget {
  const _DealPriceText({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDiscountPrice = deal.discountedPrice > 0;
    final hasOriginalPrice =
        deal.originalPrice > 0 && deal.originalPrice > deal.discountedPrice;

    if (!hasDiscountPrice) {
      return Text(
        deal.priceHint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: theme.textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (hasOriginalPrice) ...<Widget>[
          Flexible(
            child: Text(
              _formatEuro(deal.originalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF9C9297),
                decoration: TextDecoration.lineThrough,
                decorationThickness: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            _formatEuro(deal.discountedPrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _DealBadge extends StatelessWidget {
  const _DealBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _DealImageFallback extends StatelessWidget {
  const _DealImageFallback({required this.category});

  final DealCategory category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFE6EE), Color(0xFFF7F0FF)],
        ),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(category),
          size: 44,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _HomeEmptyDealsCard extends StatelessWidget {
  const _HomeEmptyDealsCard({required this.status, required this.onTap});

  final PublicCouponCacheStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF3),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.local_offer_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Noch keine passenden Deals',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status.nativeScanInProgress
                        ? 'Öffentliche Quellen werden im Hintergrund aktualisiert.'
                        : 'Ziehe nach unten zum Aktualisieren oder öffne die Suche.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7B7176),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _InviteFriendsCard extends StatelessWidget {
  const _InviteFriendsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 370;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.045),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: compact ? 64 : 76,
                    height: compact ? 64 : 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: <Color>[Color(0xFFFFEDF3), Color(0xFFFFD5E1)],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Ionicons.gift,
                      color: AppColors.primary,
                      size: compact ? 34 : 40,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Einladungs-Bonus',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lade Freunde ein und sichert euch 10% EXTRA!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    height: compact ? 46 : 52,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 16 : 22,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(19),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.20),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      compact ? 'Einladen' : 'Freunde einladen',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeSmartCollectionsSection extends StatelessWidget {
  const _HomeSmartCollectionsSection({
    required this.todayCount,
    required this.nearbyCount,
    required this.savedCount,
    required this.verifiedCount,
    required this.onTodayTap,
    required this.onNearbyTap,
    required this.onSavedTap,
    required this.onVerifiedTap,
  });

  final int todayCount;
  final int nearbyCount;
  final int savedCount;
  final int verifiedCount;
  final VoidCallback onTodayTap;
  final VoidCallback onNearbyTap;
  final VoidCallback onSavedTap;
  final VoidCallback onVerifiedTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_HomeSmartCollectionData>[
      _HomeSmartCollectionData(
        title: 'Nur heute',
        subtitle: todayCount == 1 ? '1 Deal läuft aus' : '$todayCount Deals',
        icon: Ionicons.flash_outline,
        onTap: onTodayTap,
      ),
      _HomeSmartCollectionData(
        title: 'In deiner Nähe',
        subtitle: nearbyCount == 1
            ? '1 Treffer bis 5 km'
            : '$nearbyCount Treffer',
        icon: Ionicons.location_outline,
        onTap: onNearbyTap,
      ),
      _HomeSmartCollectionData(
        title: 'Gemerkt',
        subtitle: savedCount == 1
            ? '1 Deal gespeichert'
            : '$savedCount gespeichert',
        icon: Ionicons.heart_outline,
        onTap: onSavedTap,
      ),
      _HomeSmartCollectionData(
        title: 'Geprüfte Deals',
        subtitle: verifiedCount == 1
            ? '1 Vorteil bereit'
            : '$verifiedCount Vorteile',
        icon: Ionicons.ribbon_outline,
        onTap: onVerifiedTap,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Schnell finden',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.72,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _HomeSmartCollectionTile(data: items[index]);
          },
        ),
      ],
    );
  }
}

class _HomeSmartCollectionData {
  const _HomeSmartCollectionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _HomeSmartCollectionTile extends StatelessWidget {
  const _HomeSmartCollectionTile({required this.data});

  final _HomeSmartCollectionData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF3E9EE)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.032),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEF3),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(data.icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF7B7176),
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderTopBar extends StatelessWidget {
  const _HomeHeaderTopBar({
    required this.level,
    required this.progress,
    required this.badgeCount,
    required this.onNotificationTap,
  });

  final int level;
  final double progress;
  final int badgeCount;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: <Widget>[
          const Expanded(child: _HomeHeaderBrandLockup()),
          const SizedBox(width: AppSpacing.md),
          _HomeHeaderActionTray(
            level: level,
            progress: progress,
            badgeCount: badgeCount,
            onNotificationTap: onNotificationTap,
          ),
        ],
      ),
    );
  }
}

class _HomeHeaderFlexibleSpace extends StatelessWidget {
  const _HomeHeaderFlexibleSpace({
    required this.level,
    required this.progress,
    required this.badgeCount,
    required this.onNotificationTap,
  });

  final int level;
  final double progress;
  final int badgeCount;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentHeight = constraints.biggest.height;
        final progressValue = ((currentHeight - 86.0 - topPadding) / 60.0)
            .clamp(0.0, 1.0)
            .toDouble();
        final eased = Curves.easeOutCubic.transform(progressValue);

        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              topPadding + 10 - ((1 - eased) * 8),
              AppSpacing.lg,
              86,
            ),
            child: IgnorePointer(
              ignoring: eased < 0.05,
              child: Opacity(
                opacity: eased,
                child: Transform.translate(
                  offset: Offset(0, (1 - eased) * -18),
                  child: _HomeHeaderTopBar(
                    level: level,
                    progress: progress,
                    badgeCount: badgeCount,
                    onNotificationTap: onNotificationTap,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PinnedSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedSearchHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
    required this.borderColor,
  });

  final Widget child;
  final double height;
  final Color backgroundColor;
  final Color borderColor;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(bottom: BorderSide(color: borderColor)),
          boxShadow: overlapsContent
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: SizedBox(height: height, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.child != child;
  }
}

class _HomeHeaderSearchBar extends StatelessWidget {
  const _HomeHeaderSearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
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
          child: Row(
            children: <Widget>[
              Icon(
                Ionicons.search_outline,
                color: colorScheme.onSurfaceVariant,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Suchen',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              Icon(
                Ionicons.arrow_forward_outline,
                size: 26,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderBrandLockup extends StatelessWidget {
  const _HomeHeaderBrandLockup();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: _SpargoHeaderWordmark(),
    );
  }
}

class _SpargoHeaderWordmark extends StatelessWidget {
  const _SpargoHeaderWordmark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: 132,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/branding/spargo_onboarding_logo.png',
          width: 120,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _HomeHeaderActionTray extends StatelessWidget {
  const _HomeHeaderActionTray({
    required this.level,
    required this.progress,
    required this.badgeCount,
    required this.onNotificationTap,
  });

  final int level;
  final double progress;
  final int badgeCount;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LevelProgressPill(level: level, progress: progress, embedded: true),
        const SizedBox(width: 8),
        _HeaderActionButton(
          icon: Ionicons.notifications_outline,
          badgeCount: badgeCount,
          onTap: onNotificationTap,
          embedded: true,
        ),
      ],
    );
  }
}

class _LevelProgressPill extends StatelessWidget {
  const _LevelProgressPill({
    required this.level,
    required this.progress,
    this.embedded = false,
  });

  final int level;
  final double progress;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Row(
      children: <Widget>[
        Container(
          width: embedded ? 18 : 16,
          height: embedded ? 18 : 16,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(embedded ? 6 : 5),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.workspace_premium_rounded,
            size: embedded ? 11 : 10,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'L$level',
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w800,
            fontSize: embedded ? 11.5 : 11,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              minHeight: embedded ? 5 : 4,
              value: progress,
              backgroundColor: embedded
                  ? const Color(0xFFFFE8EE)
                  : Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.secondary,
              ),
            ),
          ),
        ),
      ],
    );

    if (embedded) {
      return Container(
        width: 108,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6DBDF)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.018),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: content,
      );
    }

    return Container(
      width: 82,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFDCE4)),
      ),
      child: content,
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.badgeCount,
    required this.onTap,
    this.embedded = false,
  });

  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: embedded ? 44 : 40,
          height: embedded ? 44 : 40,
          decoration: BoxDecoration(
            color: embedded
                ? Colors.white
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: embedded ? const Color(0xFFE6DBDF) : theme.dividerColor,
            ),
            boxShadow: embedded
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.018),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Center(
                child: Icon(
                  icon,
                  size: embedded ? 19 : 20,
                  color: theme.colorScheme.secondary,
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
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

class _InlineWalletEmptyCard extends StatelessWidget {
  const _InlineWalletEmptyCard({required this.onTap, required this.status});

  final VoidCallback onTap;
  final PublicCouponCacheStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = status.cacheBlocked
        ? Icons.refresh_rounded
        : status.nativeScanInProgress && !status.hasVisibleCoupons
        ? Icons.sync_rounded
        : status.hasVisibleCoupons
        ? Icons.check_circle_rounded
        : Icons.public_rounded;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE8ED),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.local_offer_rounded,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Noch keine passenden Deals',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Sobald neue Coupons da sind, liegen sie hier direkt ganz oben bereit.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F6),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFFFDCE4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(statusIcon, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _cleanCouponStatusText(status.headline),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _cleanCouponStatusText(status.detail),
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.42,
                            color: const Color(0xFF6B5C61),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicCouponStatusStrip extends StatelessWidget {
  const _PublicCouponStatusStrip({
    required this.status,
    required this.areaLabel,
    required this.radiusKm,
    required this.compact,
    required this.onRefresh,
  });

  final PublicCouponCacheStatus status;
  final String areaLabel;
  final double radiusKm;
  final bool compact;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = status.cacheBlocked
        ? Icons.refresh_rounded
        : status.nativeScanInProgress
        ? Icons.sync_rounded
        : status.hasVisibleCoupons
        ? Icons.check_circle_rounded
        : Icons.public_rounded;
    final progress = status.syncProgress.clamp(0.0, 1.0).toDouble();
    final showPercent =
        status.nativeScanInProgress || status.hasMeasuredProgress;
    final titleText = status.cacheBlocked
        ? 'Öffentliche Quellen werden neu verbunden'
        : status.nativeScanInProgress
        ? status.hasVisibleCoupons
              ? '${status.visibleDealCount} Coupons sichtbar, weitere laden nach'
              : 'Öffentliche Coupons werden gerade geladen'
        : '${status.visibleDealCount} Öffentliche Coupons zusätzlich sichtbar';
    final areaText =
        '${_cleanCouponStatusText(areaLabel)} · ${radiusKm.round()} km';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFDCE4)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFF3),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(statusIcon, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: showPercent ? progress : null,
                          backgroundColor: const Color(0xFFFFE6EC),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      showPercent
                          ? '${status.syncProgressPercent}%'
                          : status.nativeScanInProgress
                          ? 'läuft'
                          : 'bereit',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    areaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    areaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!status.nativeScanInProgress) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: onRefresh,
              tooltip: context.t('Quellen aktualisieren'),
              style: IconButton.styleFrom(
                minimumSize: const Size(34, 34),
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicCouponCategorySection extends StatelessWidget {
  const _PublicCouponCategorySection({
    required this.deals,
    required this.onSearchTap,
  });

  final List<Deal> deals;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    final groupedEntries = _groupPublicDealsByCategory(deals);
    final visibleEntries = groupedEntries.take(4).toList(growable: false);
    final hiddenCategoryCount = groupedEntries.length - visibleEntries.length;

    return Column(
      children: <Widget>[
        SectionHeader(
          title: 'Öffentliche Coupons',
          subtitle:
              '${deals.length} zusätzliche Treffer, kompakt nach Kategorie sortiert.',
          actionLabel: 'Suche',
          onActionTap: onSearchTap,
        ),
        ...visibleEntries.map(
          (entry) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _PublicCouponCategoryTile(
              category: entry.key,
              deals: entry.value,
            ),
          ),
        ),
        if (hiddenCategoryCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TextButton(
              onPressed: onSearchTap,
              child: Text('$hiddenCategoryCount weitere Kategorien ansehen'),
            ),
          ),
      ],
    );
  }
}

class _PublicCouponCategoryTile extends ConsumerWidget {
  const _PublicCouponCategoryTile({
    required this.category,
    required this.deals,
  });

  final DealCategory category;
  final List<Deal> deals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final previewDeals = deals.take(2).toList(growable: false);
    final hiddenDeals = deals.length - previewDeals.length;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFDCE4)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFF3),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.local_offer_rounded, color: AppColors.primary),
          ),
          title: Text(
            category.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '${deals.length} Öffentliche Coupons',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: <Widget>[
            ...previewDeals.map((deal) {
              final business = ref.read(businessByIdProvider(deal.businessId));
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: CompactDealCard(
                  deal: deal,
                  business: business,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.dealDetail,
                    arguments: DealRouteArgs(deal.id),
                  ),
                ),
              );
            }),
            if (hiddenDeals > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.categoryFeed,
                    arguments: CategoryFeedArgs(category),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text('$hiddenDeals weitere in ${category.label}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<MapEntry<DealCategory, List<Deal>>> _groupPublicDealsByCategory(
  List<Deal> deals,
) {
  final grouped = <DealCategory, List<Deal>>{};
  final seenDealIds = <String>{};

  for (final deal in deals) {
    if (!seenDealIds.add(deal.id)) {
      continue;
    }
    grouped.putIfAbsent(deal.category, () => <Deal>[]).add(deal);
  }

  final entries = grouped.entries.toList(growable: false);
  entries.sort((a, b) {
    final countOrder = b.value.length.compareTo(a.value.length);
    if (countOrder != 0) {
      return countOrder;
    }
    final distanceA = a.value.isEmpty ? 9999.0 : a.value.first.distanceKm;
    final distanceB = b.value.isEmpty ? 9999.0 : b.value.first.distanceKm;
    return distanceA.compareTo(distanceB);
  });
  return entries;
}

class _StatusMetaChip extends StatelessWidget {
  const _StatusMetaChip({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFEFF3) : const Color(0xFFF9F4F6),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFFFD2DB)
              : const Color(0xFFFFE5EB),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: highlighted ? AppColors.primary : const Color(0xFF72565E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _cleanCouponStatusText(String value) {
  try {
    final repaired = utf8.decode(latin1.encode(value), allowMalformed: true);
    return repaired.contains('ï¿½') ? value : repaired;
  } on FormatException {
    return value;
  } on ArgumentError {
    return value;
  }
}

class _QuickCouponAccessCard extends StatelessWidget {
  const _QuickCouponAccessCard({
    required this.activeCount,
    required this.savedCount,
    required this.flashCount,
    required this.onWalletTap,
    required this.onSavedTap,
    required this.onLiveTap,
  });

  final int activeCount;
  final int savedCount;
  final int flashCount;
  final VoidCallback onWalletTap;
  final VoidCallback onSavedTap;
  final VoidCallback onLiveTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 370;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _QuickAccessButton(
                      icon: Icons.wallet_rounded,
                      label: 'Wallet',
                      value: '$activeCount aktiv',
                      onTap: onWalletTap,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _QuickAccessButton(
                      icon: Icons.bookmark_rounded,
                      label: 'Merken',
                      value: '$savedCount gespeichert',
                      onTap: onSavedTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuickAccessButton(
                icon: Icons.bolt_rounded,
                label: 'Live Deals',
                value: '$flashCount heute',
                onTap: onLiveTap,
                highlighted: true,
              ),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(
              child: _QuickAccessButton(
                icon: Icons.wallet_rounded,
                label: 'Wallet',
                value: '$activeCount aktiv',
                onTap: onWalletTap,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _QuickAccessButton(
                icon: Icons.bookmark_rounded,
                label: 'Merken',
                value: '$savedCount gespeichert',
                onTap: onSavedTap,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _QuickAccessButton(
                icon: Icons.bolt_rounded,
                label: 'Live',
                value: '$flashCount heute',
                onTap: onLiveTap,
                highlighted: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickCouponSummaryCard extends StatelessWidget {
  const _QuickCouponSummaryCard({
    required this.district,
    required this.activeCount,
    required this.savedCount,
    required this.flashCount,
    required this.onWalletTap,
    required this.onSavedTap,
    required this.onLiveTap,
  });

  final String district;
  final int activeCount;
  final int savedCount;
  final int flashCount;
  final VoidCallback onWalletTap;
  final VoidCallback onSavedTap;
  final VoidCallback onLiveTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            Color.lerp(theme.colorScheme.primary, AppColors.accent, 0.65) ??
                theme.colorScheme.primary,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                district,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Heute schnell bei deinen Coupons.',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Wallet, Merkliste und Live-Deals ohne Umwege.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _SummaryMetric(label: 'Aktiv', value: '$activeCount'),
                _SummaryMetric(label: 'Gemerkt', value: '$savedCount'),
                _SummaryMetric(label: 'Live', value: '$flashCount'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: onWalletTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: theme.colorScheme.primary,
                    ),
                    child: const Text('Wallet'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSavedTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                    ),
                    child: const Text('Merken'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onLiveTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                    ),
                    child: const Text('Live'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessButton extends StatelessWidget {
  const _QuickAccessButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highlighted
                ? const Color(0xFFFFEEF2)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: highlighted ? const Color(0xFFFFD4DD) : theme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: highlighted
                      ? AppColors.secondary
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 16,
                  color: highlighted
                      ? Colors.white
                      : theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Story> _storiesForBusiness(List<Story> stories, String businessId) {
  return stories
      .where((story) => story.businessId == businessId)
      .toList(growable: false);
}

bool _businessStoriesSeen(
  List<Story> stories,
  String businessId,
  Set<String> seenStoryIds,
) {
  final businessStories = _storiesForBusiness(stories, businessId);
  return businessStories.isNotEmpty &&
      businessStories.every((story) => seenStoryIds.contains(story.id));
}

Story _storyLaunchTarget(
  List<Story> stories,
  Story representative,
  Set<String> seenStoryIds,
) {
  final businessStories = _storiesForBusiness(
    stories,
    representative.businessId,
  );
  for (final story in businessStories) {
    if (!seenStoryIds.contains(story.id)) {
      return story;
    }
  }
  return businessStories.isNotEmpty ? businessStories.first : representative;
}

List<Story> _storyRepresentativesForBusinesses(
  List<Story> stories,
  Set<String> seenStoryIds, {
  int? limit,
}) {
  final groupedStories = <String, List<Story>>{};
  final orderedBusinessIds = <String>[];

  for (final story in stories) {
    final bucket = groupedStories.putIfAbsent(story.businessId, () {
      orderedBusinessIds.add(story.businessId);
      return <Story>[];
    });
    bucket.add(story);
  }

  final representatives = <Story>[];
  for (final businessId in orderedBusinessIds) {
    final businessStories = groupedStories[businessId]!;
    representatives.add(
      _storyLaunchTarget(businessStories, businessStories.first, seenStoryIds),
    );
  }

  if (limit == null) {
    return representatives;
  }
  return representatives.take(limit).toList(growable: false);
}

class _ForYouCouponCard extends ConsumerWidget {
  const _ForYouCouponCard({
    required this.deal,
    required this.business,
    required this.onTap,
  });

  final Deal deal;
  final Business business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardWidth = (MediaQuery.sizeOf(context).width - (AppSpacing.lg * 2))
        .clamp(292.0, 352.0)
        .toDouble();
    final tags = <String>[
      deal.category.label,
      deal.isThirdParty
          ? 'öffentlich'
          : (deal.openNow ? 'Jetzt offen' : 'Heute'),
    ];
    final imageUrlAsync = ref.watch(
      dealPresentationImageUrlProvider((
        businessId: business.id,
        dealId: deal.id,
      )),
    );
    final imageUrl =
        imageUrlAsync.valueOrNull ??
        (deal.imageUrl.trim().isNotEmpty
            ? deal.imageUrl.trim()
            : (business.imageUrl.trim().isNotEmpty
                  ? business.imageUrl.trim()
                  : null));

    return SizedBox(
      width: cardWidth,
      child: ShowcaseCouponCard(
        title: deal.title,
        subtitle: deal.subtitle,
        businessName: business.name,
        imageUrl: imageUrl,
        highlightLabel: deal.savingsHighlightLabel,
        topBadges: tags,
        metrics: <ShowcaseCouponCardMetric>[
          ShowcaseCouponCardMetric(
            icon: Icons.location_on_rounded,
            label: '${deal.distanceKm.toStringAsFixed(1)} km',
          ),
          ShowcaseCouponCardMetric(
            icon: Icons.star_rounded,
            label: deal.ratingLabel,
          ),
          ShowcaseCouponCardMetric(
            icon: Icons.schedule_rounded,
            label: deal.availabilityLabel,
            maxWidth: 136,
          ),
        ],
        primaryActionLabel: 'Zum Deal',
        onTap: onTap,
        heroHeight: 132,
      ),
    );
  }
}

class _CouponSideCutout extends StatelessWidget {
  const _CouponSideCutout();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE9E0E4)),
      ),
    );
  }
}

class _CouponTypeCard extends StatelessWidget {
  const _CouponTypeCard({
    required this.type,
    required this.count,
    required this.onTap,
  });

  final DealType type;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 138,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: theme.dividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8ED),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForType(type),
                  color: theme.colorScheme.secondary,
                ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                type.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

String _expiryLabel(Redemption redemption) {
  final now = DateTime.now();
  final difference = redemption.expiresAt.difference(now).inDays;
  if (difference <= 0) {
    return 'Läuft heute aus';
  }
  if (difference == 1) {
    return 'Endet morgen';
  }
  return '$difference Tage Rest';
}

IconData _iconForType(DealType type) => switch (type) {
  DealType.percentage => Icons.percent_rounded,
  DealType.exclusive => Icons.workspace_premium_rounded,
  DealType.limitedTime => Icons.schedule_rounded,
  DealType.twoForOne => Icons.people_alt_rounded,
  DealType.happyHour => Icons.wb_twilight_rounded,
  DealType.event => Icons.celebration_rounded,
  DealType.newcomer => Icons.auto_awesome_rounded,
};

IconData _categoryIcon(DealCategory category) => switch (category) {
  DealCategory.food => Icons.restaurant_rounded,
  DealCategory.cafe => Icons.local_cafe_rounded,
  DealCategory.breakfast => Icons.breakfast_dining_rounded,
  DealCategory.drinks => Icons.local_bar_rounded,
  DealCategory.beauty => Icons.spa_rounded,
  DealCategory.shopping => Icons.shopping_bag_outlined,
  DealCategory.online => Icons.language_rounded,
  DealCategory.leisure => Icons.directions_bike_rounded,
  DealCategory.experiences => Icons.auto_awesome_rounded,
  DealCategory.parks => Icons.park_rounded,
  DealCategory.fitness => Icons.fitness_center_rounded,
  DealCategory.nightlife => Icons.nightlife_rounded,
  DealCategory.wellness => Icons.self_improvement_rounded,
  DealCategory.health => Icons.local_hospital_rounded,
  DealCategory.family => Icons.family_restroom_rounded,
  DealCategory.travel => Icons.flight_takeoff_rounded,
  DealCategory.pets => Icons.pets_rounded,
  DealCategory.home => Icons.home_work_rounded,
  DealCategory.automotive => Icons.directions_car_rounded,
  DealCategory.services => Icons.handyman_rounded,
  DealCategory.culture => Icons.theater_comedy_rounded,
};

String _categoryLabel(DealCategory category) => switch (category) {
  DealCategory.food => 'Essen',
  DealCategory.cafe => 'Cafés',
  DealCategory.breakfast => 'Frühstück',
  DealCategory.drinks => 'Drinks',
  DealCategory.beauty => 'Beauty',
  DealCategory.shopping => 'Shopping',
  DealCategory.online => 'Online',
  DealCategory.leisure => 'Freizeit',
  DealCategory.experiences => 'Erlebnisse',
  DealCategory.parks => 'Parks',
  DealCategory.fitness => 'Fitness',
  DealCategory.nightlife => 'Nachtleben',
  DealCategory.wellness => 'Wellness',
  DealCategory.health => 'Gesundheit',
  DealCategory.family => 'Familie',
  DealCategory.travel => 'Reisen',
  DealCategory.pets => 'Haustiere',
  DealCategory.home => 'Zuhause',
  DealCategory.automotive => 'Auto',
  DealCategory.services => 'Service',
  DealCategory.culture => 'Kultur',
};

String _formatEuro(double value) {
  return '${value.toStringAsFixed(2).replaceAll('.', ',')} \u20ac';
}

String _dealBadgeText(Deal deal) {
  if (deal.type == DealType.twoForOne) {
    return '2 für 1';
  }
  if (deal.hasMeasuredSavings) {
    return '-${deal.savingsPercent}%';
  }
  return 'Deal';
}

class _FlashDealCard extends StatelessWidget {
  const _FlashDealCard({
    required this.deal,
    required this.business,
    required this.onTap,
  });

  final Deal deal;
  final Business business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = deal.palette.map(Color.new).toList();
    final start = colors.isEmpty ? theme.colorScheme.primary : colors.first;
    final end = colors.isEmpty ? theme.colorScheme.secondary : colors.last;

    return SizedBox(
      width: 244,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.lerp(start, Colors.white, 0.12) ?? start,
                end,
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: start.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  deal.availabilityLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                deal.savingsBadgeLabel,
                style: theme.textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                deal.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                business.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
