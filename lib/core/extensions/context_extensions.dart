import 'package:flutter/material.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  Size get mediaQuerySize => MediaQuery.sizeOf(this);
  double get width => mediaQuerySize.width;
  double get height => mediaQuerySize.height;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
