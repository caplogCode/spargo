import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_tokens.dart';

class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const items = <IconData>[
      Ionicons.home_outline,
      Ionicons.compass_outline,
      Ionicons.heart_outline,
      Ionicons.wallet_outline,
      Ionicons.person_outline,
    ];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        6,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFF0E8EC)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: List<Widget>.generate(items.length, (index) {
            final icon = items[index];
            final selected = currentIndex == index;

            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(20),
                  child: Center(
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      curve: Curves.easeOutCubic,
                      width: selected ? 52 : 44,
                      height: selected ? 52 : 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedScale(
                        duration: AppDurations.fast,
                        scale: selected ? 1 : 0.96,
                        child: Icon(
                          icon,
                          size: selected ? 27 : 24,
                          color: selected
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
