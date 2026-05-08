import 'package:flutter/foundation.dart';

enum FeedFilter {
  forYou,
  nearby,
  trending,
  food,
  beauty,
  shopping,
  leisure,
  fresh,
  today,
}

extension FeedFilterX on FeedFilter {
  String get label => switch (this) {
    FeedFilter.forYou => 'Für dich',
    FeedFilter.nearby => 'In deiner Nähe',
    FeedFilter.trending => 'Trending',
    FeedFilter.food => 'Essen',
    FeedFilter.beauty => 'Beauty',
    FeedFilter.shopping => 'Shopping',
    FeedFilter.leisure => 'Freizeit',
    FeedFilter.fresh => 'Neu',
    FeedFilter.today => 'Heute',
  };
}

enum FeedSectionType {
  hero,
  trending,
  carousel,
  nearby,
  featuredBusiness,
  friendActivity,
  collection,
}

enum FeedItemType {
  heroDeal,
  standardDeal,
  nearbyDeal,
  trendingDeal,
  eventDeal,
  hiddenGem,
  friendActivity,
  collection,
  featuredBusiness,
}

@immutable
class FeedItem {
  const FeedItem({
    required this.id,
    required this.type,
    this.dealId,
    this.businessId,
    required this.headline,
    required this.supportingText,
    required this.badge,
  });

  final String id;
  final FeedItemType type;
  final String? dealId;
  final String? businessId;
  final String headline;
  final String supportingText;
  final String badge;
}

@immutable
class FeedSection {
  const FeedSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.items,
  });

  final String id;
  final String title;
  final String subtitle;
  final FeedSectionType type;
  final List<FeedItem> items;
}
