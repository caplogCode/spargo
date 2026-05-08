import 'package:flutter/foundation.dart';

@immutable
class AppReview {
  const AppReview({
    required this.id,
    required this.authorName,
    required this.authorInitials,
    this.authorId = '',
    required this.rating,
    required this.comment,
    required this.timeLabel,
    required this.helpfulCount,
    required this.city,
    this.createdAt,
    this.updatedAt,
    this.dealId,
    this.businessId,
  });

  final String id;
  final String authorName;
  final String authorInitials;
  final String authorId;
  final int rating;
  final String comment;
  final String timeLabel;
  final int helpfulCount;
  final String city;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? dealId;
  final String? businessId;

  bool isOwnedBy(String userId) => authorId.isNotEmpty && authorId == userId;

  bool get canDelete =>
      createdAt != null &&
      DateTime.now().difference(createdAt!) <= const Duration(days: 7);

  AppReview copyWith({
    String? id,
    String? authorName,
    String? authorInitials,
    String? authorId,
    int? rating,
    String? comment,
    String? timeLabel,
    int? helpfulCount,
    String? city,
    Object? createdAt = _reviewFieldUnset,
    Object? updatedAt = _reviewFieldUnset,
    String? dealId,
    String? businessId,
  }) {
    return AppReview(
      id: id ?? this.id,
      authorName: authorName ?? this.authorName,
      authorInitials: authorInitials ?? this.authorInitials,
      authorId: authorId ?? this.authorId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      timeLabel: timeLabel ?? this.timeLabel,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      city: city ?? this.city,
      createdAt: identical(createdAt, _reviewFieldUnset)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _reviewFieldUnset)
          ? this.updatedAt
          : updatedAt as DateTime?,
      dealId: dealId ?? this.dealId,
      businessId: businessId ?? this.businessId,
    );
  }
}

const Object _reviewFieldUnset = Object();

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.id,
    required this.name,
    required this.city,
    required this.points,
    required this.rank,
    required this.freeCouponCredits,
    required this.isCurrentUser,
  });

  final String id;
  final String name;
  final String city;
  final int points;
  final int rank;
  final int freeCouponCredits;
  final bool isCurrentUser;

  LeaderboardEntry copyWith({
    String? id,
    String? name,
    String? city,
    int? points,
    int? rank,
    int? freeCouponCredits,
    bool? isCurrentUser,
  }) {
    return LeaderboardEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      points: points ?? this.points,
      rank: rank ?? this.rank,
      freeCouponCredits: freeCouponCredits ?? this.freeCouponCredits,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }
}
