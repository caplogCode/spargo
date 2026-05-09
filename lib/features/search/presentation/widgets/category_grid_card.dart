import 'package:flutter/material.dart' hide Text;
import 'package:ionicons/ionicons.dart';
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../theme/app_colors.dart';

class CategoryGridCard extends StatelessWidget {
  const CategoryGridCard({
    super.key,
    required this.category,
    required this.activeDeals,
    required this.onTap,
  });

  final DealCategory category;
  final int activeDeals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _visualFor(category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      visual.tint.withValues(alpha: 0.12),
                      visual.tint.withValues(alpha: 0.28),
                    ],
                  ),
                ),
                child: Icon(visual.icon, color: visual.tint, size: 28),
              ),
              const Spacer(),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '$activeDeals aktive Deals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Ionicons.caret_forward_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

_CategoryVisual _visualFor(DealCategory category) {
  return switch (category) {
    DealCategory.food => const _CategoryVisual(
      icon: Ionicons.restaurant,
      tint: Color(0xFFE34F7D),
    ),
    DealCategory.cafe => const _CategoryVisual(
      icon: Ionicons.cafe,
      tint: Color(0xFFC94FAE),
    ),
    DealCategory.breakfast => const _CategoryVisual(
      icon: Ionicons.fast_food,
      tint: Color(0xFFE99435),
    ),
    DealCategory.drinks => const _CategoryVisual(
      icon: Ionicons.wine,
      tint: Color(0xFFE25074),
    ),
    DealCategory.beauty => const _CategoryVisual(
      icon: Ionicons.flower,
      tint: Color(0xFFC455D6),
    ),
    DealCategory.shopping => const _CategoryVisual(
      icon: Ionicons.bag_handle,
      tint: Color(0xFFE84C78),
    ),
    DealCategory.online => const _CategoryVisual(
      icon: Ionicons.laptop,
      tint: Color(0xFFA660D4),
    ),
    DealCategory.leisure => const _CategoryVisual(
      icon: Ionicons.bicycle,
      tint: Color(0xFF8170E8),
    ),
    DealCategory.experiences => const _CategoryVisual(
      icon: Ionicons.ticket,
      tint: Color(0xFFFF6F61),
    ),
    DealCategory.parks => const _CategoryVisual(
      icon: Ionicons.leaf,
      tint: Color(0xFF55A34C),
    ),
    DealCategory.fitness => const _CategoryVisual(
      icon: Ionicons.barbell,
      tint: Color(0xFF3C9ACF),
    ),
    DealCategory.nightlife => const _CategoryVisual(
      icon: Ionicons.moon,
      tint: Color(0xFF725EE4),
    ),
    DealCategory.wellness => const _CategoryVisual(
      icon: Ionicons.flower,
      tint: Color(0xFFC455D6),
    ),
    DealCategory.health => const _CategoryVisual(
      icon: Ionicons.medical,
      tint: Color(0xFF2BAF89),
    ),
    DealCategory.family => const _CategoryVisual(
      icon: Ionicons.people,
      tint: Color(0xFFF06292),
    ),
    DealCategory.travel => const _CategoryVisual(
      icon: Ionicons.airplane,
      tint: Color(0xFF4B8FE8),
    ),
    DealCategory.pets => const _CategoryVisual(
      icon: Ionicons.paw,
      tint: Color(0xFFB7793D),
    ),
    DealCategory.home => const _CategoryVisual(
      icon: Ionicons.home,
      tint: Color(0xFF7E9B43),
    ),
    DealCategory.automotive => const _CategoryVisual(
      icon: Ionicons.car_sport,
      tint: Color(0xFF4E8BC4),
    ),
    DealCategory.services => const _CategoryVisual(
      icon: Ionicons.construct,
      tint: Color(0xFF6E7A8A),
    ),
    DealCategory.culture => const _CategoryVisual(
      icon: Ionicons.color_palette,
      tint: Color(0xFFB85DD7),
    ),
  };
}

class _CategoryVisual {
  const _CategoryVisual({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;
}
