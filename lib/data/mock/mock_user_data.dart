import '../../domain/models/deal_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/models/user_models.dart';

final _now = DateTime.now();

final mockNotifications = <NotificationItem>[
  const NotificationItem(
    id: 'notification_1',
    title: 'Heute beliebt in deiner Nähe',
    body: 'Pflastergolds Sharing Brunch Board wird gerade stark gespeichert.',
    timeLabel: 'Jetzt',
    type: NotificationType.trending,
    isRead: false,
    dealId: 'deal_pflastergold_brunch',
  ),
  const NotificationItem(
    id: 'notification_2',
    title: 'Fast abgelaufen',
    body: 'Golden Hour Table endet morgen Abend.',
    timeLabel: 'vor 18 min',
    type: NotificationType.expiring,
    isRead: false,
    dealId: 'deal_haus_sunset',
  ),
  const NotificationItem(
    id: 'notification_3',
    title: 'Neue Story von Nordlicht Atelier',
    body: 'Glow Week ist live.',
    timeLabel: 'vor 46 min',
    type: NotificationType.newOpening,
    isRead: true,
    businessId: 'nordlicht_atelier',
  ),
  const NotificationItem(
    id: 'notification_4',
    title: 'Freunde nutzen das',
    body: '3 Kontakte folgen Studio Marea.',
    timeLabel: 'vor 2 h',
    type: NotificationType.friendActivity,
    isRead: true,
    businessId: 'studio_marea',
  ),
  const NotificationItem(
    id: 'notification_5',
    title: 'Neue Reward-Stufe',
    body: 'Mit einem weiteren eingelösten Deal schaltest du City Gold frei.',
    timeLabel: 'Gestern',
    type: NotificationType.loyalty,
    isRead: true,
  ),
];

final mockSavedDeals = <SavedDeal>[
  SavedDeal(
    id: 'saved_1',
    dealId: 'deal_nordlicht_glow',
    savedAt: _now.subtract(const Duration(days: 2)),
    collectionName: 'Beauty',
  ),
  SavedDeal(
    id: 'saved_2',
    dealId: 'deal_dock_double',
    savedAt: _now.subtract(const Duration(hours: 6)),
    collectionName: 'Date Night',
  ),
  SavedDeal(
    id: 'saved_3',
    dealId: 'deal_kante_lamps',
    savedAt: _now.subtract(const Duration(days: 1)),
    collectionName: 'Zuhause',
  ),
];

final mockRedemptions = <Redemption>[
  Redemption(
    id: 'redemption_1',
    dealId: 'deal_ember_duo',
    code: 'SP-EMBER-22',
    couponId: 'CPN-EMBERDUO',
    qrPayload:
        'spargo://coupon/deal_ember_duo?coupon=CPN-EMBERDUO&code=SP-EMBER-22',
    activatedAt: _now.subtract(const Duration(hours: 3)),
    expiresAt: _now.add(const Duration(days: 2)),
    status: RedemptionStatus.active,
    offlineReady: true,
    instructions: 'Code beim Bestellen vorzeigen. Nur ein Deal pro Tisch.',
  ),
  Redemption(
    id: 'redemption_2',
    dealId: 'deal_wildgarten_afterwork',
    code: 'SP-STEAM-24',
    couponId: 'CPN-WILDGART',
    qrPayload:
        'spargo://coupon/deal_wildgarten_afterwork?coupon=CPN-WILDGART&code=SP-STEAM-24',
    activatedAt: _now.subtract(const Duration(days: 1)),
    expiresAt: _now.add(const Duration(days: 1)),
    status: RedemptionStatus.active,
    offlineReady: true,
    instructions: 'An der Rezeption scannen lassen. Einlass bis 19:30.',
  ),
  Redemption(
    id: 'redemption_3',
    dealId: 'deal_marea_reformer',
    code: 'SP-MAREA-21',
    couponId: 'CPN-MAREAREF',
    qrPayload:
        'spargo://coupon/deal_marea_reformer?coupon=CPN-MAREAREF&code=SP-MAREA-21',
    activatedAt: _now.subtract(const Duration(days: 7)),
    expiresAt: _now.subtract(const Duration(days: 1)),
    status: RedemptionStatus.redeemed,
    offlineReady: true,
    instructions: 'Beim Check-in nennen.',
    usedAt: _now.subtract(const Duration(days: 2)),
  ),
];

final mockUser = User(
  id: 'user_lena',
  accountType: AccountType.user,
  name: 'Lena Voigt',
  handle: '@lenavoigt',
  city: 'Deutschlandweit',
  district: 'Innenstadt',
  avatarInitials: 'LV',
  favoriteCategories: const <DealCategory>[
    DealCategory.food,
    DealCategory.beauty,
    DealCategory.leisure,
  ],
  savedDealIds: mockSavedDeals.map((saved) => saved.dealId).toList(),
  activeDealIds: mockRedemptions
      .where((redemption) => redemption.status == RedemptionStatus.active)
      .map((redemption) => redemption.dealId)
      .toList(),
  followingBusinessIds: const <String>[
    'pflastergold',
    'nordlicht_atelier',
    'studio_marea',
  ],
  rewards: const <Reward>[
    Reward(
      id: 'reward_1',
      title: 'City Silver',
      points: 320,
      tier: 'Silver',
      description: 'Früher Zugriff auf exklusive Wochenend-Drops.',
      unlocked: true,
    ),
    Reward(
      id: 'reward_2',
      title: 'City Gold',
      points: 500,
      tier: 'Gold',
      description: 'Mehr Save-Sammlungen und Partner-Perks.',
      unlocked: false,
    ),
  ],
  points: 320,
  freeCouponCredits: 2,
  inviteCode: 'SP-LENA-24',
  streakDays: 6,
  preferences: const UserPreferences(
    interests: <DealCategory>[
      DealCategory.food,
      DealCategory.beauty,
      DealCategory.leisure,
    ],
    city: 'Deutschlandweit',
    radiusKm: 8,
    notificationsEnabled: true,
    socialProofEnabled: true,
    openNowOnly: false,
  ),
);
