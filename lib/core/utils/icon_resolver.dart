import 'package:flutter/material.dart';

import '../../domain/models/deal_models.dart';
import '../../domain/models/notification_models.dart';

IconData iconForCategory(DealCategory category) {
  return switch (category) {
    DealCategory.food => Icons.restaurant_rounded,
    DealCategory.cafe => Icons.local_cafe_rounded,
    DealCategory.breakfast => Icons.breakfast_dining_rounded,
    DealCategory.drinks => Icons.local_bar_rounded,
    DealCategory.beauty => Icons.spa_rounded,
    DealCategory.shopping => Icons.shopping_bag_rounded,
    DealCategory.online => Icons.language_rounded,
    DealCategory.leisure => Icons.movie_creation_outlined,
    DealCategory.experiences => Icons.celebration_rounded,
    DealCategory.parks => Icons.park_rounded,
    DealCategory.fitness => Icons.fitness_center_rounded,
    DealCategory.nightlife => Icons.nightlife_rounded,
    DealCategory.wellness => Icons.self_improvement_rounded,
    DealCategory.health => Icons.local_hospital_rounded,
    DealCategory.family => Icons.family_restroom_rounded,
    DealCategory.travel => Icons.luggage_rounded,
    DealCategory.pets => Icons.pets_rounded,
    DealCategory.home => Icons.chair_rounded,
    DealCategory.automotive => Icons.directions_car_filled_rounded,
    DealCategory.services => Icons.miscellaneous_services_rounded,
    DealCategory.culture => Icons.museum_rounded,
  };
}

IconData iconForNotification(NotificationType type) {
  return switch (type) {
    NotificationType.trending => Icons.local_fire_department_rounded,
    NotificationType.expiring => Icons.timer_outlined,
    NotificationType.friendActivity => Icons.people_alt_outlined,
    NotificationType.newOpening => Icons.auto_awesome_outlined,
    NotificationType.loyalty => Icons.workspace_premium_outlined,
    NotificationType.liveDeal => Icons.bolt_rounded,
    NotificationType.followingBusiness => Icons.notifications_active_outlined,
    NotificationType.referral => Icons.card_giftcard_rounded,
    NotificationType.review => Icons.reviews_outlined,
    NotificationType.businessPerformance => Icons.show_chart_rounded,
  };
}
