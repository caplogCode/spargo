import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/business_stats_card.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_shadows.dart';

enum _CampaignFilter { live, flash, paused }

enum _DashboardMenuAction {
  manageProfile,
  deals,
  stories,
  redemptions,
  signOut,
}

extension on _CampaignFilter {
  String get label => switch (this) {
    _CampaignFilter.live => 'Live',
    _CampaignFilter.flash => 'Kurzfristig',
    _CampaignFilter.paused => 'Pausiert',
  };
}

class BusinessDashboardScreen extends ConsumerStatefulWidget {
  const BusinessDashboardScreen({super.key});

  @override
  ConsumerState<BusinessDashboardScreen> createState() =>
      _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState
    extends ConsumerState<BusinessDashboardScreen> {
  _CampaignFilter _filter = _CampaignFilter.live;
  bool _composeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = ref.watch(authUserProvider);
    final session = ref.watch(sessionControllerProvider);
    if (session.isBusinessAccount &&
        authUser != null &&
        !authUser.isAnonymous &&
        !authUser.emailVerified) {
      return _BusinessEmailVerificationGate(
        email: authUser.email ?? '',
        onRefresh: () async {
          await authUser.reload();
          ref.invalidate(authUserProvider);
        },
        onSignOut: _signOut,
      );
    }

    final compactDashboardGrid =
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.16;
    final business = ref.watch(ownedBusinessProvider);
    final canPublish = ref.watch(ownedBusinessCanPublishProvider);
    final deals = ref.watch(businessDealsProvider(business.id));
    final stories = ref
        .watch(storiesProvider)
        .where((story) => story.businessId == business.id)
        .toList(growable: false);
    final redemptions =
        ref.watch(businessRedemptionsProvider).toList(growable: true)
          ..sort((a, b) => b.activatedAt.compareTo(a.activatedAt));
    final pausedIds = ref.watch(repositoryProvider).pausedDealIds;
    final liveDeals = deals
        .where((deal) => !pausedIds.contains(deal.id))
        .toList(growable: false);
    final flashDeals = liveDeals
        .where(
          (deal) =>
              deal.isExpiringSoon ||
              deal.tags.contains(OfferTag.today) ||
              deal.type == DealType.limitedTime,
        )
        .toList(growable: false);
    final pausedDeals = deals
        .where((deal) => pausedIds.contains(deal.id))
        .toList(growable: false);
    final activeRedemptions = redemptions
        .where((entry) => entry.status == RedemptionStatus.active)
        .toList(growable: false);
    final redeemedRedemptions = redemptions
        .where((entry) => entry.status == RedemptionStatus.redeemed)
        .toList(growable: false);

    final visibleDeals = switch (_filter) {
      _CampaignFilter.live => liveDeals,
      _CampaignFilter.flash => flashDeals,
      _CampaignFilter.paused => pausedDeals,
    };

    final totalViews = _maxOf(
      business.analytics.views,
      deals.fold<int>(0, (sum, deal) => sum + deal.stats.views),
    );
    final totalSaves = _maxOf(
      business.analytics.saves,
      deals.fold<int>(0, (sum, deal) => sum + deal.stats.saves),
    );
    final totalActivations = _maxOf(
      business.analytics.activations,
      deals.fold<int>(0, (sum, deal) => sum + deal.stats.activations),
    );
    final totalRedemptions = _maxOf(
      business.analytics.redemptions,
      _maxOf(
        redeemedRedemptions.length,
        deals.fold<int>(0, (sum, deal) => sum + deal.stats.redemptions),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Studio'),
        actions: <Widget>[
          IconButton(
            tooltip: context.t('Insights'),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.analytics),
            icon: const Icon(Icons.insights_outlined),
          ),
          PopupMenuButton<_DashboardMenuAction>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) =>
                const <PopupMenuEntry<_DashboardMenuAction>>[
                  PopupMenuItem(
                    value: _DashboardMenuAction.manageProfile,
                    child: Text('Business-Profil'),
                  ),
                  PopupMenuItem(
                    value: _DashboardMenuAction.deals,
                    child: Text('Gutscheine verwalten'),
                  ),
                  PopupMenuItem(
                    value: _DashboardMenuAction.stories,
                    child: Text('Stories verwalten'),
                  ),
                  PopupMenuItem(
                    value: _DashboardMenuAction.redemptions,
                    child: Text('Einlösungen'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _DashboardMenuAction.signOut,
                    child: Text('Abmelden'),
                  ),
                ],
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? _DashboardComposeFab(
              expanded: _composeExpanded,
              onToggle: () {
                setState(() => _composeExpanded = !_composeExpanded);
              },
              onCreateStory: () {
                setState(() => _composeExpanded = false);
                Navigator.of(context).pushNamed(AppRoutes.createStory);
              },
              onCreateDeal: () {
                setState(() => _composeExpanded = false);
                Navigator.of(context).pushNamed(AppRoutes.createDeal);
              },
            )
          : null,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _DashboardHero(
                business: business,
                canPublish: canPublish,
                liveCount: liveDeals.length,
                storyCount: stories.length,
                activePassCount: activeRedemptions.length,
              ),
            ),
          ),
          if (!canPublish)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _VerificationGateCard(
                  label: business.verificationStatus.label,
                  note: business.verificationNote,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: _QuickActionGrid(
                canPublish: canPublish,
                liveDeals: liveDeals.length,
                storyCount: stories.length,
                redemptionCount: redemptions.length,
                onCreateDeal: canPublish
                    ? () =>
                          Navigator.of(context).pushNamed(AppRoutes.createDeal)
                    : _showVerificationBlocked,
                onManageDeals: () =>
                    Navigator.of(context).pushNamed(AppRoutes.businessDeals),
                onCreateStory: canPublish
                    ? () =>
                          Navigator.of(context).pushNamed(AppRoutes.createStory)
                    : _showVerificationBlocked,
                onManageStories: () =>
                    Navigator.of(context).pushNamed(AppRoutes.businessStories),
                onRedemptions: () =>
                    Navigator.of(context).pushNamed(AppRoutes.redemptions),
                onProfile: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.manageBusinessProfile),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _ResponsiveDashboardGrid(
                compact: compactDashboardGrid,
                children: <Widget>[
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
                    delta: liveDeals.isNotEmpty
                        ? '${liveDeals.length} aktiv im Feed'
                        : 'Noch kein aktiver Gutschein',
                    icon: Icons.bookmark_outline_rounded,
                  ),
                  BusinessStatsCard(
                    label: 'Aktivierungen',
                    value: '$totalActivations',
                    delta: activeRedemptions.isNotEmpty
                        ? '${activeRedemptions.length} offene Pässe'
                        : 'Noch kein offener Pass',
                    icon: Icons.bolt_rounded,
                  ),
                  BusinessStatsCard(
                    label: 'Einlösungen',
                    value: '$totalRedemptions',
                    delta: redeemedRedemptions.isNotEmpty
                        ? '${redeemedRedemptions.length} bereits bestätigt'
                        : 'Noch keine Einlösung',
                    icon: Icons.qr_code_scanner_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (redemptions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _SectionBlock(
                  title: 'Aktuelle Einlösungen',
                  subtitle:
                      'Coupon-ID, Code und QR sind direkt für dein Team sichtbar.',
                  actionLabel: 'Alle ansehen',
                  onAction: () =>
                      Navigator.of(context).pushNamed(AppRoutes.redemptions),
                  child: Column(
                    children: redemptions
                        .take(3)
                        .map((redemption) {
                          final deal = ref.read(
                            dealByIdProvider(redemption.dealId),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _DashboardRedemptionRow(
                              redemption: redemption,
                              deal: deal,
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.redemptions),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          if (stories.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _SectionBlock(
                  title: 'Storys',
                  subtitle:
                      'Live-Formate für Deals, Events und schnelle Updates.',
                  actionLabel: 'Verwalten',
                  onAction: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.businessStories),
                  child: Column(
                    children: stories
                        .take(3)
                        .map((story) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _StoryRow(story: story),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Gutscheine im Feed',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _CampaignFilterBar(
                current: _filter,
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
          ),
          if (visibleDeals.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    _filter == _CampaignFilter.paused
                        ? 'Gerade ist kein Gutschein pausiert.'
                        : 'Für diesen Bereich ist gerade kein Gutschein sichtbar.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: visibleDeals.length,
              itemBuilder: (context, index) {
                final deal = visibleDeals[index];
                final isPaused = pausedIds.contains(deal.id);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: _CampaignControlCard(
                    deal: deal,
                    isPaused: isPaused,
                    onTogglePause: () => _togglePause(
                      business: business,
                      dealId: deal.id,
                      paused: !isPaused,
                    ),
                    onEdit: () => Navigator.of(context).pushNamed(
                      AppRoutes.editDeal,
                      arguments: BusinessDealEditorArgs(dealId: deal.id),
                    ),
                    onStory: () => canPublish
                        ? Navigator.of(context).pushNamed(AppRoutes.createStory)
                        : _showVerificationBlocked(),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              child: Container(
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
                      'Einlösung im Alltag',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'sparGO erzeugt Coupon-ID, Code und QR automatisch. Dein Team muss beim Kassieren nur den gezeigten Pass prüfen und bei Bedarf im Bereich Einlösungen bestätigen.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _maxOf(int left, int right) => left > right ? left : right;

  Future<void> _togglePause({
    required Business business,
    required String dealId,
    required bool paused,
  }) async {
    try {
      await ref
          .read(repositoryProvider)
          .setDealPaused(business: business, dealId: dealId, paused: paused);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status konnte nicht aktualisiert werden: $error'),
        ),
      );
    }
  }

  Future<void> _handleMenuAction(_DashboardMenuAction action) async {
    switch (action) {
      case _DashboardMenuAction.manageProfile:
        Navigator.of(context).pushNamed(AppRoutes.manageBusinessProfile);
        return;
      case _DashboardMenuAction.deals:
        Navigator.of(context).pushNamed(AppRoutes.businessDeals);
        return;
      case _DashboardMenuAction.stories:
        Navigator.of(context).pushNamed(AppRoutes.businessStories);
        return;
      case _DashboardMenuAction.redemptions:
        Navigator.of(context).pushNamed(AppRoutes.redemptions);
        return;
      case _DashboardMenuAction.signOut:
        await _signOut();
        return;
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } finally {
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
    }
  }

  void _showVerificationBlocked() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor Stories und Gutscheine live gehen.',
        ),
      ),
    );
  }
}

class _BusinessEmailVerificationGate extends StatelessWidget {
  const _BusinessEmailVerificationGate({
    required this.email,
    required this.onRefresh,
    required this.onSignOut,
  });

  final String email;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8EF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Business-Mail bestätigen',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Dein Business-Konto ist angemeldet, aber die E-Mail ist noch nicht bestätigt. Sobald die Mail bestätigt ist und dein Business verifiziert zugeordnet wurde, öffnet sich hier die mobile Studio-Version für Stories, Gutscheine, Einlösungen und Profilpflege.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (email.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4F6),
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                        child: Text(
                          email,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton(
                            onPressed: onRefresh,
                            child: const Text('Status aktualisieren'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton.outlined(
                          tooltip: 'Abmelden',
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ],
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

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.business,
    required this.canPublish,
    required this.liveCount,
    required this.storyCount,
    required this.activePassCount,
  });

  final Business business;
  final bool canPublish;
  final int liveCount;
  final int storyCount;
  final int activePassCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(32),
        boxShadow: <BoxShadow>[
          ...AppShadows.floating,
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 42,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.16),
            blurRadius: 64,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: canPublish ? 0.18 : 0.14,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      canPublish
                          ? 'Freigeschaltet'
                          : business.verificationStatus.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _BusinessLogoBadge(
                imageUrl: business.imageUrl.trim(),
                businessName: business.name,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            business.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (business.tagline.trim().isNotEmpty)
            Text(
              business.tagline,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Gutscheine steuern, Storys posten, aktive Pässe sauber im Blick behalten.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _HeroMetric(label: 'Live', value: '$liveCount'),
              _HeroMetric(label: 'Storys', value: '$storyCount'),
              _HeroMetric(label: 'Offene Pässe', value: '$activePassCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessLogoBadge extends StatelessWidget {
  const _BusinessLogoBadge({
    required this.imageUrl,
    required this.businessName,
  });

  final String imageUrl;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    final initials = businessName
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.trim()[0])
        .join()
        .toUpperCase();

    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (context, error, stackTrace) {
                return _BusinessLogoFallback(initials: initials);
              },
            )
          : _BusinessLogoFallback(initials: initials),
    );
  }
}

class _BusinessLogoFallback extends StatelessWidget {
  const _BusinessLogoFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DashboardComposeFab extends StatelessWidget {
  const _DashboardComposeFab({
    required this.expanded,
    required this.onToggle,
    required this.onCreateStory,
    required this.onCreateDeal,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCreateStory;
  final VoidCallback onCreateDeal;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        AnimatedSlide(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          offset: expanded ? Offset.zero : const Offset(0, 0.18),
          child: AnimatedOpacity(
            duration: AppDurations.fast,
            opacity: expanded ? 1 : 0,
            child: IgnorePointer(
              ignoring: !expanded,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ComposeFabAction(
                  icon: Icons.auto_stories_rounded,
                  label: 'Story',
                  onTap: onCreateStory,
                ),
              ),
            ),
          ),
        ),
        AnimatedSlide(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          offset: expanded ? Offset.zero : const Offset(0, 0.12),
          child: AnimatedOpacity(
            duration: AppDurations.fast,
            opacity: expanded ? 1 : 0,
            child: IgnorePointer(
              ignoring: !expanded,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ComposeFabAction(
                  icon: Icons.local_offer_rounded,
                  label: 'Gutschein',
                  onTap: onCreateDeal,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: FloatingActionButton(
            heroTag: 'business-dashboard-compose',
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            onPressed: onToggle,
            child: AnimatedRotation(
              duration: AppDurations.fast,
              turns: expanded ? 0.125 : 0,
              child: Icon(expanded ? Icons.close_rounded : Icons.add_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposeFabAction extends StatelessWidget {
  const _ComposeFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: const Color(0xFFFFDCE4)),
            boxShadow: <BoxShadow>[
              ...AppShadows.floating,
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.10),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
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

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({
    required this.canPublish,
    required this.liveDeals,
    required this.storyCount,
    required this.redemptionCount,
    required this.onCreateDeal,
    required this.onManageDeals,
    required this.onCreateStory,
    required this.onManageStories,
    required this.onRedemptions,
    required this.onProfile,
  });

  final bool canPublish;
  final int liveDeals;
  final int storyCount;
  final int redemptionCount;
  final VoidCallback onCreateDeal;
  final VoidCallback onManageDeals;
  final VoidCallback onCreateStory;
  final VoidCallback onManageStories;
  final VoidCallback onRedemptions;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactGrid =
        MediaQuery.sizeOf(context).width < 390 || textScale > 1.16;

    return _ResponsiveDashboardGrid(
      compact: compactGrid,
      children: <Widget>[
        _QuickActionCard(
          title: 'Gutscheine',
          subtitle: canPublish
              ? '$liveDeals aktiv im Feed'
              : 'Freigabe vervollständigen',
          icon: Icons.local_offer_rounded,
          primaryLabel: 'Neu',
          secondaryLabel: 'Verwalten',
          onPrimary: onCreateDeal,
          onSecondary: onManageDeals,
        ),
        _QuickActionCard(
          title: 'Storys',
          subtitle: '$storyCount live oder zuletzt gepostet',
          icon: Icons.auto_stories_rounded,
          primaryLabel: 'Posten',
          secondaryLabel: 'Verwalten',
          onPrimary: onCreateStory,
          onSecondary: onManageStories,
        ),
        _QuickActionCard(
          title: 'Einlösungen',
          subtitle: '$redemptionCount Pässe für dein Team sichtbar',
          icon: Icons.qr_code_scanner_rounded,
          primaryLabel: 'öffnen',
          onPrimary: onRedemptions,
        ),
        _QuickActionCard(
          title: 'Profil',
          subtitle: 'Adresse, Kontakt und rechtliche Daten pflegen',
          icon: Icons.store_mall_directory_rounded,
          primaryLabel: 'Bearbeiten',
          onPrimary: onProfile,
        ),
      ],
    );
  }
}

class _ResponsiveDashboardGrid extends StatelessWidget {
  const _ResponsiveDashboardGrid({
    required this.children,
    required this.compact,
  });

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.md;
        final itemWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryLabel,
    this.secondaryLabel,
    required this.onPrimary,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEF2),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onPrimary,
                  child: Text(
                    primaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (secondaryLabel != null && onSecondary != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(
                      secondaryLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _DashboardRedemptionRow extends StatelessWidget {
  const _DashboardRedemptionRow({
    required this.redemption,
    required this.deal,
    required this.onTap,
  });

  final Redemption redemption;
  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFFF6F8),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${redemption.couponId} · ${redemption.code}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                redemption.status.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
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

class _StoryRow extends StatelessWidget {
  const _StoryRow({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewImageUrl = story.items.isEmpty
        ? ''
        : story.items.first.imageUrl.trim();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 52,
              height: 52,
              child: previewImageUrl.isEmpty
                  ? Container(
                      color: const Color(0xFFFFE8ED),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        color: AppColors.primary,
                      ),
                    )
                  : Image.network(
                      previewImageUrl,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: const Color(0xFFFFE8ED),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: AppColors.primary,
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  story.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${story.items.length} Slide${story.items.length == 1 ? '' : 's'} · ${story.timeLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _VerificationGateCard extends StatelessWidget {
  const _VerificationGateCard({required this.label, required this.note});

  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Business-Verifizierung: $label',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            note.isEmpty
                ? 'Sobald deine Business-Zuordnung vollständig ist, kannst du Stories und Gutscheine live schalten.'
                : note,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$value $label',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _CampaignFilterBar extends StatelessWidget {
  const _CampaignFilterBar({required this.current, required this.onChanged});

  final _CampaignFilter current;
  final ValueChanged<_CampaignFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: _CampaignFilter.values
            .map((filter) {
              final selected = current == filter;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onChanged(filter),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      child: Center(
                        child: Text(
                          filter.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _CampaignControlCard extends StatelessWidget {
  const _CampaignControlCard({
    required this.deal,
    required this.isPaused,
    required this.onTogglePause,
    required this.onEdit,
    required this.onStory,
  });

  final Deal deal;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onEdit;
  final VoidCallback onStory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flash = deal.isExpiringSoon || deal.tags.contains(OfferTag.today);
    final useStackedActions =
        MediaQuery.textScalerOf(context).scale(1) > 1.08 ||
        MediaQuery.sizeOf(context).width < 430;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.dividerColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: deal.imageUrl.trim().isEmpty
                      ? Container(
                          color: const Color(0xFFFFEEF2),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.local_offer_rounded,
                            color: Color(0xFFDB2149),
                            size: 26,
                          ),
                        )
                      : Image.network(
                          deal.imageUrl,
                          fit: BoxFit.cover,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.fallback,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: const Color(0xFFFFEEF2),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.local_offer_rounded,
                                color: Color(0xFFDB2149),
                                size: 26,
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deal.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(deal.priceHint, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(
                label: isPaused
                    ? 'Pausiert'
                    : flash
                    ? 'Kurzfristig'
                    : 'Live',
                tone: isPaused
                    ? theme.colorScheme.surfaceContainerHighest
                    : flash
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.tertiaryContainer,
                textColor: isPaused
                    ? theme.colorScheme.onSurfaceVariant
                    : flash
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.tertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _MiniMetric(
                icon: Icons.visibility_outlined,
                label: '${deal.stats.views} Aufrufe',
              ),
              _MiniMetric(
                icon: Icons.bookmark_outline_rounded,
                label: '${deal.stats.saves} Saves',
              ),
              _MiniMetric(
                icon: Icons.bolt_rounded,
                label: '${deal.stats.activations} Aktivierungen',
              ),
              _MiniMetric(
                icon: Icons.qr_code_scanner_rounded,
                label: '${deal.stats.redemptions} Einlösungen',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (useStackedActions)
            Column(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: onTogglePause,
                    child: Text(isPaused ? 'Reaktivieren' : 'Pausieren'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Bearbeiten'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onStory,
                    child: const Text('Story posten'),
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onTogglePause,
                    child: Text(isPaused ? 'Reaktivieren' : 'Pausieren'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Bearbeiten'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onStory,
                    child: const Text('Story posten'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.tone,
    required this.textColor,
  });

  final String label;
  final Color tone;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: textColor),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
