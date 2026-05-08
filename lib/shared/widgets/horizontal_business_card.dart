import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/icon_resolver.dart';
import '../../core/widgets/immersive_cover.dart';
import '../../domain/models/business_models.dart';
import 'metric_badge.dart';

class HorizontalBusinessCard extends StatelessWidget {
  const HorizontalBusinessCard({
    super.key,
    required this.business,
    required this.onTap,
    this.trailing,
  });

  final Business business;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 304,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ImmersiveCover(
                palette: business.coverPalette,
                title: business.name,
                subtitle: business.tagline,
                icon: iconForCategory(business.category),
                showBadge: false,
                height: 142,
                borderRadius: AppRadii.lg,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      business.shortDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  MetricBadge(
                    icon: Icons.star_rounded,
                    label: business.reviewCount > 0
                        ? business.rating.toStringAsFixed(1)
                        : 'Neu',
                    compact: true,
                  ),
                  MetricBadge(
                    icon: Icons.people_outline_rounded,
                    label: '${business.followerCount}',
                    compact: true,
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
