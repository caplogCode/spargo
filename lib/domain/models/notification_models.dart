import 'package:flutter/foundation.dart';

enum NotificationType {
  trending,
  expiring,
  friendActivity,
  newOpening,
  loyalty,
  liveDeal,
  followingBusiness,
  referral,
  review,
  businessPerformance,
}

@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.type,
    required this.isRead,
    this.dealId,
    this.businessId,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final NotificationType type;
  final bool isRead;
  final String? dealId;
  final String? businessId;

  NotificationItem copyWith({
    String? title,
    String? body,
    String? timeLabel,
    NotificationType? type,
    bool? isRead,
    String? dealId,
    String? businessId,
  }) {
    return NotificationItem(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      timeLabel: timeLabel ?? this.timeLabel,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      dealId: dealId ?? this.dealId,
      businessId: businessId ?? this.businessId,
    );
  }
}
