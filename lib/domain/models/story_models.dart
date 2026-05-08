import 'package:flutter/foundation.dart';

enum StoryType { deal, event, newOpening, limitedOffer, behindTheScenes }

extension StoryTypeX on StoryType {
  String get label => switch (this) {
    StoryType.deal => 'Deal Story',
    StoryType.event => 'Event',
    StoryType.newOpening => 'Neu',
    StoryType.limitedOffer => 'Limitiert',
    StoryType.behindTheScenes => 'Behind the Scenes',
  };
}

@immutable
class StoryItem {
  const StoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.ctaLabel,
    required this.palette,
    required this.duration,
    this.imageUrl = '',
    this.dealId,
  });

  final String id;
  final StoryType type;
  final String title;
  final String subtitle;
  final String body;
  final String ctaLabel;
  final List<int> palette;
  final Duration duration;
  final String imageUrl;
  final String? dealId;
}

@immutable
class Story {
  const Story({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.city,
    required this.label,
    required this.previewPalette,
    required this.items,
    required this.timeLabel,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String city;
  final String label;
  final List<int> previewPalette;
  final List<StoryItem> items;
  final String timeLabel;
}
