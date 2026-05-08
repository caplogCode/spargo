import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/icon_resolver.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';

class BusinessHeader extends StatelessWidget {
  const BusinessHeader({
    super.key,
    required this.business,
    required this.isFollowing,
    required this.onFollowToggle,
  });

  final Business business;
  final bool isFollowing;
  final VoidCallback onFollowToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: business.coverPalette.map(Color.new).toList(),
                ),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Icon(
                iconForCategory(business.category),
                color: Colors.white,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    business.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${business.category.label} - ${business.city}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    business.shortDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (isCompact) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: onFollowToggle,
                        child: Text(isFollowing ? 'Folge ich' : 'Folgen'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCompact) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: onFollowToggle,
                child: Text(isFollowing ? 'Folge ich' : 'Folgen'),
              ),
            ],
          ],
        );
      },
    );
  }
}
