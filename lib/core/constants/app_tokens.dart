import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
}

abstract final class AppRadii {
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

abstract final class AppDurations {
  static const micro = Duration(milliseconds: 140);
  static const fast = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 360);
  static const slow = Duration(milliseconds: 620);
  static const storySnap = Duration(milliseconds: 180);
}

abstract final class AppInsets {
  static const screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );
  static const card = EdgeInsets.all(AppSpacing.md);
  static const chip = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xs,
  );
}
