import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/icon_resolver.dart';
import '../../../../core/widgets/immersive_cover.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/engagement_models.dart';
import '../../../../domain/models/notification_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../shared/widgets/compact_deal_card.dart';
import '../../../../shared/widgets/coupon_highlight_panel.dart';
import '../../../../shared/widgets/cover_action_button.dart';
import '../../../../shared/widgets/deal_tag_chip.dart';
import '../../../../shared/widgets/map_preview_card.dart';
import '../../../../shared/widgets/metric_badge.dart';
import '../../../../shared/widgets/redeem_confirm_sheet.dart';
import '../../../../theme/app_colors.dart';

class DealDetailScreen extends ConsumerWidget {
  const DealDetailScreen({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final deal = ref.watch(dealByIdProvider(dealId));
    final business = ref.watch(businessByIdProvider(deal.businessId));
    final imageUrl = ref
        .watch(
          dealPresentationImageUrlProvider((
            businessId: business.id,
            dealId: deal.id,
          )),
        )
        .valueOrNull;
    final isFollowing = user.followingBusinessIds.contains(business.id);
    final similarDeals = ref
        .watch(similarDealsProvider(dealId))
        .take(3)
        .toList();
    final reviews = ref.watch(dealReviewsProvider(deal.id));
    AppReview? ownReview;
    for (final review in reviews) {
      if (review.isOwnedBy(user.id)) {
        ownReview = review;
        break;
      }
    }
    final recommendedDeals = ref
        .watch(recommendedDealsProvider)
        .where((entry) => entry.id != deal.id)
        .take(2)
        .toList();
    final influencerDeals = ref
        .watch(influencerDealsProvider)
        .where((entry) => entry.id != deal.id)
        .take(2)
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            automaticallyImplyLeading: false,
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: CoverActionButton(
                onTap: () => Navigator.of(context).maybePop(),
                icon: Icons.arrow_back_rounded,
              ),
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Consumer(
                  builder: (context, ref, child) {
                    final isSaved = ref
                        .watch(savedDealsProvider)
                        .contains(deal.id);
                    return CoverActionButton(
                      onTap: () =>
                          ref.read(savedDealsProvider.notifier).toggle(deal.id),
                      child: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                    );
                  },
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'deal-${deal.id}',
                child: ImmersiveCover(
                  palette: deal.palette,
                  title: deal.title,
                  subtitle: business.name,
                  icon: iconForCategory(deal.category),
                  showIcon: false,
                  showBadge: false,
                  height: 300,
                  alignment: Alignment.bottomLeft,
                  imageUrl: imageUrl,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CouponHighlightPanel(
                    value: deal.savingsHighlightLabel,
                    title: deal.priceHint,
                    subtitle: deal.socialProof,
                    trailing: MetricBadge(
                      icon: Icons.local_fire_department_rounded,
                      label: deal.tags.contains(OfferTag.popular)
                          ? 'Beliebt'
                          : 'Live',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (ref.watch(influencerDealsProvider).contains(deal))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEEF2),
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.campaign_rounded,
                              color: Color(0xFFDB2149),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Creator Pick mit starkem Social Proof und hoher Empfehlungsquote.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: deal.tags
                        .map((tag) => DealTagChip(tag: tag))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    deal.subtitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(deal.description, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      MetricBadge(
                        icon: Icons.place_outlined,
                        label: '${deal.distanceKm.toStringAsFixed(1)} km',
                      ),
                      MetricBadge(
                        icon: Icons.star_rounded,
                        label: deal.ratingLabel,
                      ),
                      MetricBadge(
                        icon: Icons.timer_outlined,
                        label: deal.availabilityLabel,
                      ),
                      MetricBadge(
                        icon: Icons.workspace_premium_rounded,
                        label: '${user.freeCouponCredits} freie Gutscheine',
                      ),
                    ],
                  ),
                  if (isFollowing) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.notifications_active_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Du folgst diesem Laden und bekommst neue Gutschein-Updates.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (deal.isThirdParty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.verified_outlined,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              deal.sourceLabel.isEmpty
                                  ? 'Öffentlicher Gutschein: sparGO zeigt nur den Fund. Aktivierung und Einlösung laufen beim Anbieter.'
                                  : 'Öffentlicher Gutschein von ${deal.sourceLabel}: sparGO zeigt nur den Fund. Aktivierung und Einlösung laufen beim Anbieter.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Highlights',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...deal.highlights.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text('- $item', style: theme.textTheme.bodyMedium),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Bedingungen',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...deal.conditions.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text('- $item', style: theme.textTheme.bodyMedium),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Business',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ListTile(
                    onTap: () => Navigator.of(context).pushNamed(
                      AppRoutes.businessProfile,
                      arguments: BusinessRouteArgs(business.id),
                    ),
                    contentPadding: EdgeInsets.zero,
                    title: Text(business.name),
                    subtitle: Text(
                      '${business.category.label} · ${business.city}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  MapPreviewCard(
                    title: business.primaryBranch.address,
                    subtitle: 'Tippen für Route in Karten',
                    onTap: () => _openMaps(context, business),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Öffnungszeiten',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (business.primaryBranch.hours.isEmpty)
                    Text(
                      'Für diesen Ort sind noch keine verlässlichen Öffnungszeiten hinterlegt.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    ...business.primaryBranch.hours.map(
                      (hours) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(width: 40, child: Text(hours.day)),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                hours.isClosed
                                    ? 'Geschlossen'
                                    : '${hours.opensAt} - ${hours.closesAt}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Bewertungen',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openReviewSheet(
                          context,
                          ref,
                          user: user,
                          deal: deal,
                          business: business,
                          review: ownReview,
                        ),
                        icon: const Icon(Icons.rate_review_outlined),
                        label: Text(
                          ownReview == null ? 'Bewerten' : 'Bearbeiten',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (reviews.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: const Text(
                        'Noch keine Bewertung vorhanden. Sei die erste Stimme für diesen Gutschein.',
                      ),
                    )
                  else
                    ...reviews
                        .take(4)
                        .map(
                          (review) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _DealReviewCard(
                              review: review,
                              onEdit: review.isOwnedBy(user.id)
                                  ? () => _openReviewSheet(
                                      context,
                                      ref,
                                      user: user,
                                      deal: deal,
                                      business: business,
                                      review: review,
                                    )
                                  : null,
                              onDelete: review.isOwnedBy(user.id)
                                  ? () => _deleteReview(
                                      context,
                                      ref,
                                      user: user,
                                      review: review,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                  if (recommendedDeals.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Empfohlen für dich',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...recommendedDeals.map((entry) {
                      final entryBusiness = ref.read(
                        businessByIdProvider(entry.businessId),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: CompactDealCard(
                          deal: entry,
                          business: entryBusiness,
                          onTap: () =>
                              Navigator.of(context).pushReplacementNamed(
                                AppRoutes.dealDetail,
                                arguments: DealRouteArgs(entry.id),
                              ),
                        ),
                      );
                    }),
                  ],
                  if (influencerDeals.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Influencer Deals',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...influencerDeals.map((entry) {
                      final entryBusiness = ref.read(
                        businessByIdProvider(entry.businessId),
                      );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.title),
                        subtitle: Text(entryBusiness.name),
                        trailing: Text(entry.savingsBadgeLabel),
                        onTap: () => Navigator.of(context).pushReplacementNamed(
                          AppRoutes.dealDetail,
                          arguments: DealRouteArgs(entry.id),
                        ),
                      );
                    }),
                  ],
                  if (similarDeals.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      '\u00c4hnliche Deals',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...similarDeals.map((similar) {
                      final similarBusiness = ref.read(
                        businessByIdProvider(similar.businessId),
                      );
                      return ListTile(
                        onTap: () => Navigator.of(context).pushReplacementNamed(
                          AppRoutes.dealDetail,
                          arguments: DealRouteArgs(similar.id),
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: Text(similar.title),
                        subtitle: Text(similarBusiness.name),
                        trailing: Text(similar.savingsBadgeLabel),
                      );
                    }),
                  ],
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;

            return Row(
              children: <Widget>[
                if (compact)
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => _shareDeal(context, deal, business),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Icon(Icons.share_outlined),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareDeal(context, deal, business),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Teilen'),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                if (compact)
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: isFollowing
                        ? FilledButton(
                            onPressed: () => _toggleFollow(
                              context,
                              ref,
                              business,
                              isFollowing,
                            ),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                            ),
                          )
                        : OutlinedButton(
                            onPressed: () => _toggleFollow(
                              context,
                              ref,
                              business,
                              isFollowing,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.add_reaction_outlined),
                          ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _toggleFollow(context, ref, business, isFollowing),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isFollowing
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : null,
                        side: BorderSide(
                          color: isFollowing
                              ? AppColors.primary
                              : Theme.of(context).dividerColor,
                        ),
                      ),
                      icon: Icon(
                        isFollowing
                            ? Icons.notifications_active_rounded
                            : Icons.add_reaction_outlined,
                        color: isFollowing ? AppColors.primary : null,
                      ),
                      label: Text(
                        isFollowing ? 'Gefolgt' : 'Folgen',
                        style: TextStyle(
                          color: isFollowing ? AppColors.primary : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: compact ? 1 : 2,
                  child: AnimatedCtaButton(
                    label: deal.isThirdParty
                        ? 'Zur Anbieter-Website'
                        : deal.ctaLabel,
                    expanded: true,
                    onPressed: () => deal.isThirdParty
                        ? _openSourceUrl(context, deal, business)
                        : _openRedeemConfirmation(context, ref, deal, business),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _shareDeal(
    BuildContext context,
    Deal deal,
    Business business,
  ) async {
    final shareText =
        'spargo://deal/${deal.id}\n\n${deal.title} bei ${business.name} · ${deal.savingsHighlightLabel}';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deal-Link wurde kopiert.')));
    }
  }

  Future<void> _openMaps(BuildContext context, Business business) async {
    final branch = business.primaryBranch;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${branch.latitude},${branch.longitude}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kartenlink konnte nicht geöffnet werden.'),
        ),
      );
    }
  }

  Future<void> _toggleFollow(
    BuildContext context,
    WidgetRef ref,
    Business business,
    bool isFollowing,
  ) async {
    await ref
        .read(sessionControllerProvider.notifier)
        .toggleFollowBusiness(business.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isFollowing
              ? '${business.name} wird nicht mehr verfolgt.'
              : '${business.name} wird jetzt verfolgt.',
        ),
      ),
    );
  }

  Future<void> _openRedeemConfirmation(
    BuildContext context,
    WidgetRef ref,
    Deal deal,
    Business business,
  ) async {
    if (deal.isThirdParty) {
      await _openSourceUrl(context, deal, business);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return RedeemConfirmSheet(
          dealTitle: deal.title,
          businessName: business.name,
          highlight: deal.savingsHighlightLabel,
          title: 'Gutschein aktivieren',
          message:
              'Nach der Bestätigung wird der Gutschein aktiviert und in deine Wallet gelegt.',
          confirmLabel: 'Gutschein aktivieren',
          onConfirm: () async {
            final wallet = ref.read(walletProvider.notifier);
            final redemption = await wallet.activate(deal);
            await ref
                .read(notificationsProvider.notifier)
                .add(
                  NotificationItem(
                    id: 'activated_live_${redemption.id}',
                    title: 'Gutschein aktiviert',
                    body:
                        '${deal.title} liegt jetzt in deiner Wallet. Gutschein-ID ${redemption.couponId}.',
                    timeLabel: 'Jetzt',
                    type: NotificationType.loyalty,
                    isRead: false,
                    dealId: deal.id,
                    businessId: business.id,
                  ),
                );
            if (!sheetContext.mounted || !context.mounted) {
              return;
            }
            Navigator.of(sheetContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Aktiviert: ${redemption.couponId} ist jetzt in deiner Wallet.',
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSourceUrl(
    BuildContext context,
    Deal deal,
    Business business,
  ) async {
    final rawUrl = deal.sourceUrl.trim().isNotEmpty
        ? deal.sourceUrl.trim()
        : business.website.trim();
    final normalized =
        rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
        ? rawUrl
        : 'https://$rawUrl';
    final uri = Uri.tryParse(normalized);
    if (uri == null || rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Für diesen öffentlichen Gutschein fehlt der Link.'),
        ),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anbieter-Website konnte nicht geöffnet werden.'),
        ),
      );
    }
  }

  Future<void> _openReviewSheet(
    BuildContext context,
    WidgetRef ref, {
    required User user,
    required Deal deal,
    required Business business,
    AppReview? review,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return _ReviewComposerSheet(
          title: review == null
              ? 'Bewertung schreiben'
              : 'Bewertung bearbeiten',
          submitLabel: review == null ? 'Speichern' : 'Aktualisieren',
          initialRating: review?.rating ?? 5,
          initialComment: review?.comment ?? '',
          onSubmit: (rating, comment) async {
            if (review == null) {
              await ref
                  .read(reviewsProvider.notifier)
                  .submit(
                    user: user,
                    rating: rating,
                    comment: comment,
                    dealId: deal.id,
                    businessId: business.id,
                  );
              await ref
                  .read(sessionControllerProvider.notifier)
                  .addRewardBonus(points: 20);
              await ref
                  .read(notificationsProvider.notifier)
                  .add(
                    const NotificationItem(
                      id: 'review_reward_runtime',
                      title: 'Danke für deine Bewertung',
                      body:
                          'Deine Bewertung wurde gespeichert und 20 Punkte wurden gutgeschrieben.',
                      timeLabel: 'Jetzt',
                      type: NotificationType.review,
                      isRead: false,
                    ),
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Deine Bewertung ist jetzt live.'),
                  ),
                );
              }
              return;
            }

            await ref
                .read(reviewsProvider.notifier)
                .updateReview(
                  user: user,
                  review: review,
                  rating: rating,
                  comment: comment,
                );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Deine Bewertung wurde aktualisiert.'),
                ),
              );
            }
          },
        );
      },
    );
  }

  Future<void> _deleteReview(
    BuildContext context,
    WidgetRef ref, {
    required User user,
    required AppReview review,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bewertung löschen?'),
          content: Text(
            review.canDelete
                ? 'Du kannst diese Bewertung noch innerhalb von 7 Tagen entfernen.'
                : 'Die Löschfrist für diese Bewertung ist bereits abgelaufen.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: review.canDelete
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(reviewsProvider.notifier)
          .deleteReview(user: user, review: review);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bewertung wurde gelöscht.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_reviewErrorText(error))));
    }
  }

  String _reviewErrorText(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '').trim();
    return message.isEmpty
        ? 'Die Bewertung konnte nicht verarbeitet werden.'
        : message;
  }
}

class _DealReviewCard extends ConsumerWidget {
  const _DealReviewCard({required this.review, this.onEdit, this.onDelete});

  final AppReview review;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final isOwnReview = review.isOwnedBy(currentUser.id);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  review.authorInitials,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      review.authorName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${review.timeLabel} · ${review.city}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(
                  review.rating,
                  (index) => const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Color(0xFFFFB54A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(review.comment, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${review.helpfulCount} fanden das hilfreich',
            style: theme.textTheme.bodySmall,
          ),
          if (isOwnReview) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Bearbeiten'),
                ),
                if (review.canDelete)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Löschen'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xs,
                      top: 10,
                    ),
                    child: Text(
                      'Löschen nur bis 7 Tage nach dem Posten',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewComposerSheet extends StatefulWidget {
  const _ReviewComposerSheet({
    required this.onSubmit,
    required this.title,
    required this.submitLabel,
    this.initialRating = 5,
    this.initialComment = '',
  });

  final Future<void> Function(int rating, String comment) onSubmit;
  final String title;
  final String submitLabel;
  final int initialRating;
  final String initialComment;

  @override
  State<_ReviewComposerSheet> createState() => _ReviewComposerSheetState();
}

class _ReviewComposerSheetState extends State<_ReviewComposerSheet> {
  late final TextEditingController _controller;
  late int _rating;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment);
    _rating = widget.initialRating;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: List<Widget>.generate(5, (index) {
                final filled = index < _rating;
                return IconButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _rating = index + 1),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFFFB54A),
                  ),
                );
              }),
            ),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: context.t(
                  'Wie war das Einlösen, der Vorteil und das Erlebnis?',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting
                        ? null
                        : () async {
                            final comment = _controller.text.trim();
                            if (comment.isEmpty) {
                              return;
                            }
                            setState(() => _submitting = true);
                            try {
                              await widget.onSubmit(_rating, comment);
                              if (!mounted) {
                                return;
                              }
                              Navigator.of(context).pop();
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error.toString().replaceFirst(
                                      'Bad state: ',
                                      '',
                                    ),
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _submitting = false);
                              }
                            }
                          },
                    child: Text(widget.submitLabel),
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
