import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/icon_resolver.dart';
import '../../../../core/widgets/immersive_cover.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/engagement_models.dart';
import '../../../../domain/models/notification_models.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/business_header.dart';
import '../../../../shared/widgets/compact_deal_card.dart';
import '../../../../shared/widgets/cover_action_button.dart';
import '../../../../shared/widgets/map_preview_card.dart';
import '../../../../shared/widgets/story_bubble.dart';

class BusinessProfileScreen extends ConsumerWidget {
  const BusinessProfileScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessByIdProvider(businessId));
    final deals = ref.watch(businessDealsProvider(businessId));
    final stories = ref
        .watch(storiesProvider)
        .where((story) => story.businessId == businessId)
        .toList(growable: false);
    final seenStories = ref.watch(storySeenProvider);
    Story? launchStory;
    for (final story in stories) {
      if (!seenStories.contains(story.id)) {
        launchStory = story;
        break;
      }
    }
    launchStory ??= stories.isNotEmpty ? stories.first : null;
    final allStoriesSeen =
        stories.isNotEmpty &&
        stories.every((story) => seenStories.contains(story.id));
    final reviews = ref
        .watch(businessReviewsProvider(businessId))
        .take(4)
        .toList();
    final following = ref
        .watch(currentUserProvider)
        .followingBusinessIds
        .contains(businessId);

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            automaticallyImplyLeading: false,
            backgroundColor: Theme.of(context).colorScheme.surface,
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
            flexibleSpace: FlexibleSpaceBar(
              background: ImmersiveCover(
                palette: business.coverPalette,
                title: business.name,
                subtitle: business.tagline,
                icon: iconForCategory(business.category),
                showIcon: false,
                showBadge: false,
                height: 280,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BusinessHeader(
                    business: business,
                    isFollowing: following,
                    onFollowToggle: () {
                      ref
                          .read(sessionControllerProvider.notifier)
                          .toggleFollowBusiness(business.id);
                      if (!following) {
                        ref
                            .read(notificationsProvider.notifier)
                            .add(
                              NotificationItem(
                                id: 'follow_${business.id}',
                                title: 'Business wird jetzt verfolgt',
                                body:
                                    'Du bekommst Updates, sobald ${business.name} neue Gutscheine veröffentlicht.',
                                timeLabel: 'Jetzt',
                                type: NotificationType.followingBusiness,
                                isRead: false,
                                businessId: business.id,
                              ),
                            );
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: business.tags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                  if (stories.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Stories',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 112,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: <Widget>[
                          StoryBubble(
                            story: launchStory!,
                            isSeen: allStoriesSeen,
                            onTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.storyViewer,
                              arguments: StoryViewerArgs(
                                storyId: launchStory!.id,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Aktuelle Deals',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...deals.map(
                    (deal) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: CompactDealCard(
                        deal: deal,
                        business: business,
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.dealDetail,
                          arguments: DealRouteArgs(deal.id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Adresse',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MapPreviewCard(
                    title: business.primaryBranch.address,
                    subtitle:
                        '${business.city} · ${business.distanceKm.toStringAsFixed(1)} km entfernt',
                    onTap: () => _openMaps(context, business),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Kontakt & Impressum',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      children: <Widget>[
                        ListTile(
                          leading: const Icon(Icons.language_rounded),
                          title: const Text('Website'),
                          subtitle: Text(
                            business.website.isEmpty
                                ? 'Keine Website hinterlegt'
                                : business.website,
                          ),
                          onTap: business.website.isEmpty
                              ? null
                              : () => _openWebsite(context, business.website),
                        ),
                        ListTile(
                          leading: const Icon(Icons.call_outlined),
                          title: const Text('Telefon'),
                          subtitle: Text(
                            business.phone.isEmpty
                                ? 'Keine Telefonnummer hinterlegt'
                                : business.phone,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.mail_outline_rounded),
                          title: const Text('E-Mail'),
                          subtitle: Text(
                            business.contactEmail.isEmpty
                                ? 'Keine E-Mail hinterlegt'
                                : business.contactEmail,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.gavel_rounded),
                          title: const Text('Impressum'),
                          subtitle: Text(
                            business.imprintInfo.isEmpty
                                ? (business.legalEntityName.isEmpty
                                      ? 'Impressum über Website einsehbar'
                                      : business.legalEntityName)
                                : business.imprintInfo,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reviews.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Bewertungen',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...reviews.map(
                      (review) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _BusinessReviewTile(review: review),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _openWebsite(BuildContext context, String website) async {
    final normalized = website.startsWith('http')
        ? website
        : 'https://$website';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Website konnte nicht geöffnet werden.'),
          ),
        );
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website konnte nicht geöffnet werden.')),
      );
    }
  }
}

class _BusinessReviewTile extends StatelessWidget {
  const _BusinessReviewTile({required this.review});

  final AppReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    Text(review.timeLabel, style: theme.textTheme.bodySmall),
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
        ],
      ),
    );
  }
}
