import 'package:flutter/material.dart';

import '../constants/app_tokens.dart';

class AdaptiveScrollBody extends StatelessWidget {
  const AdaptiveScrollBody({
    super.key,
    required this.child,
    this.padding = AppInsets.screen,
    this.topSafeArea = false,
    this.bottomSafeArea = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool topSafeArea;
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: topSafeArea,
      bottom: bottomSafeArea,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > bottomInset
              ? constraints.maxHeight - bottomInset
              : 0.0;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: padding.add(EdgeInsets.only(bottom: bottomInset)),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: IntrinsicHeight(child: child),
            ),
          );
        },
      ),
    );
  }
}
