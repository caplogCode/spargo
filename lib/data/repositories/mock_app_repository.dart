import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../domain/models/feed_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/models/story_models.dart';
import '../../domain/models/user_models.dart';
import '../mock/mock_businesses.dart';
import '../mock/mock_deals.dart';
import '../mock/mock_stories.dart';
import '../mock/mock_user_data.dart';

class MockAppRepository {
  List<Business> get businesses => List<Business>.unmodifiable(mockBusinesses);
  List<Deal> get deals => List<Deal>.unmodifiable(mockDeals);
  List<Story> get stories => List<Story>.unmodifiable(mockStories);
  List<NotificationItem> get notifications =>
      List<NotificationItem>.unmodifiable(mockNotifications);
  List<Redemption> get redemptions =>
      List<Redemption>.unmodifiable(mockRedemptions);
  List<SavedDeal> get savedDeals =>
      List<SavedDeal>.unmodifiable(mockSavedDeals);
  User get currentUser => mockUser;

  Business businessById(String id) =>
      businesses.firstWhere((business) => business.id == id);

  Deal dealById(String id) => deals.firstWhere((deal) => deal.id == id);

  Story storyById(String id) => stories.firstWhere((story) => story.id == id);

  List<Deal> dealsForBusiness(String businessId) =>
      deals.where((deal) => deal.businessId == businessId).toList();

  List<Story> storiesForBusiness(String businessId) =>
      stories.where((story) => story.businessId == businessId).toList();

  List<Deal> similarDeals(String dealId) {
    final current = dealById(dealId);
    return deals
        .where(
          (deal) =>
              deal.id != dealId &&
              (deal.category == current.category || deal.city == current.city),
        )
        .take(6)
        .toList();
  }

  List<Business> featuredBusinesses(User user) {
    return businesses
        .where(
          (business) =>
              user.followingBusinessIds.contains(business.id) ||
              business.isTrending ||
              business.city == user.city,
        )
        .take(6)
        .toList();
  }

  Map<DealCategory, int> categoryCounts() {
    return <DealCategory, int>{
      for (final category in DealCategory.values)
        category: deals.where((deal) => deal.category == category).length,
    };
  }

  List<Deal> dealsForFilter(FeedFilter filter, {required User user}) {
    final preferred = user.preferences.interests;

    List<Deal> filtered = switch (filter) {
      FeedFilter.forYou =>
        deals
            .where((deal) => preferred.contains(deal.category))
            .followedBy(
              deals.where((deal) => !preferred.contains(deal.category)),
            )
            .toList(),
      FeedFilter.nearby => deals.toList()..sort(_sortByDistance),
      FeedFilter.trending =>
        deals.toList()..sort(
          (a, b) =>
              b.stats.todayRedemptions.compareTo(a.stats.todayRedemptions),
        ),
      FeedFilter.food =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.food ||
                  deal.category == DealCategory.cafe ||
                  deal.category == DealCategory.breakfast ||
                  deal.category == DealCategory.drinks,
            )
            .toList(),
      FeedFilter.beauty =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.beauty ||
                  deal.category == DealCategory.wellness ||
                  deal.category == DealCategory.health,
            )
            .toList(),
      FeedFilter.shopping =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.shopping ||
                  deal.category == DealCategory.online ||
                  deal.category == DealCategory.home ||
                  deal.category == DealCategory.services,
            )
            .toList(),
      FeedFilter.leisure =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.leisure ||
                  deal.category == DealCategory.experiences ||
                  deal.category == DealCategory.parks ||
                  deal.category == DealCategory.nightlife ||
                  deal.category == DealCategory.wellness ||
                  deal.category == DealCategory.culture ||
                  deal.category == DealCategory.family ||
                  deal.category == DealCategory.travel,
            )
            .toList(),
      FeedFilter.fresh =>
        deals.where((deal) => deal.tags.contains(OfferTag.fresh)).toList(),
      FeedFilter.today =>
        deals
            .where(
              (deal) =>
                  deal.tags.contains(OfferTag.today) || deal.isExpiringSoon,
            )
            .toList(),
    };

    if (filtered.isEmpty) {
      filtered = deals.toList();
    }

    return filtered;
  }

  List<FeedSection> buildFeedSections(FeedFilter filter, {required User user}) {
    final source = dealsForFilter(filter, user: user);
    final heroDeal = source.first;
    final trending = dealsForFilter(FeedFilter.trending, user: user).take(4);
    final nearby = dealsForFilter(FeedFilter.nearby, user: user).take(4);
    final hidden = deals
        .where((deal) => deal.tags.contains(OfferTag.hiddenGem))
        .followedBy(deals.where((deal) => businessById(deal.businessId).isNew))
        .take(4);
    final social = deals
        .where(
          (deal) =>
              user.followingBusinessIds.contains(deal.businessId) ||
              deal.stats.friendCount > 2,
        )
        .take(4);

    return <FeedSection>[
      FeedSection(
        id: 'hero',
        title: 'Heute für dich',
        subtitle: 'Stark gespeichert, nah dran, schnell aktivierbar.',
        type: FeedSectionType.hero,
        items: <FeedItem>[
          FeedItem(
            id: heroDeal.id,
            type: FeedItemType.heroDeal,
            dealId: heroDeal.id,
            businessId: heroDeal.businessId,
            headline: heroDeal.title,
            supportingText: heroDeal.socialProof,
            badge: heroDeal.tags.first.label,
          ),
        ],
      ),
      FeedSection(
        id: 'trending',
        title: 'Heute beliebt',
        subtitle: 'Was gerade in deiner Nähe zieht.',
        type: FeedSectionType.trending,
        items: trending
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.trendingDeal,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.stats.todayRedemptions}x heute eingelöst',
                badge: 'Trend',
              ),
            )
            .toList(),
      ),
      FeedSection(
        id: 'nearby',
        title: 'Gerade in deiner Nähe',
        subtitle: 'Kurzer Weg, schneller Mehrwert.',
        type: FeedSectionType.nearby,
        items: nearby
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.nearbyDeal,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.distanceKm.toStringAsFixed(1)} km entfernt',
                badge: 'Nearby',
              ),
            )
            .toList(),
      ),
      FeedSection(
        id: 'social',
        title: 'Freunde nutzen das',
        subtitle: 'Deals mit sichtbar gutem Social Proof.',
        type: FeedSectionType.friendActivity,
        items: social
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.friendActivity,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.stats.friendCount} Freunde folgen diesem Laden',
                badge: 'Social',
              ),
            )
            .toList(),
      ),
      FeedSection(
        id: 'hidden',
        title: 'Geheimtipps',
        subtitle: 'Kleine Orte mit großer Wahrscheinlichkeit auf Save.',
        type: FeedSectionType.collection,
        items: hidden
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.hiddenGem,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText: businessById(deal.businessId).tagline,
                badge: 'Geheimtipp',
              ),
            )
            .toList(),
      ),
    ];
  }

  List<Deal> searchDeals({
    String query = '',
    DealCategory? category,
    bool onlyToday = false,
    bool onlyExclusive = false,
    bool openNowOnly = false,
    bool popularOnly = false,
    bool freshOnly = false,
    double maxDistanceKm = 30,
    double minRating = 0,
  }) {
    final normalized = query.trim().toLowerCase();

    return deals.where((deal) {
      final business = businessById(deal.businessId);
      final matchesQuery =
          normalized.isEmpty ||
          deal.title.toLowerCase().contains(normalized) ||
          deal.subtitle.toLowerCase().contains(normalized) ||
          business.name.toLowerCase().contains(normalized) ||
          business.city.toLowerCase().contains(normalized) ||
          business.district.toLowerCase().contains(normalized) ||
          deal.category.label.toLowerCase().contains(normalized) ||
          deal.type.label.toLowerCase().contains(normalized);

      final matchesCategory = category == null || deal.category == category;
      final matchesToday =
          !onlyToday ||
          deal.tags.contains(OfferTag.today) ||
          deal.isExpiringSoon;
      final matchesExclusive =
          !onlyExclusive || deal.tags.contains(OfferTag.exclusive);
      final matchesOpen = !openNowOnly || deal.openNow;
      final matchesPopular =
          !popularOnly || deal.tags.contains(OfferTag.popular);
      final matchesFresh = !freshOnly || deal.tags.contains(OfferTag.fresh);
      final matchesDistance = deal.distanceKm <= maxDistanceKm;
      final matchesRating = deal.stats.rating >= minRating;

      return matchesQuery &&
          matchesCategory &&
          matchesToday &&
          matchesExclusive &&
          matchesOpen &&
          matchesPopular &&
          matchesFresh &&
          matchesDistance &&
          matchesRating;
    }).toList()..sort((a, b) => _sortByDistance(a, b));
  }

  int _sortByDistance(Deal a, Deal b) => a.distanceKm.compareTo(b.distanceKm);
}
