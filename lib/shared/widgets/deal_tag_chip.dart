import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../domain/models/deal_models.dart';

class DealTagChip extends StatelessWidget {
  const DealTagChip({super.key, required this.tag});

  final OfferTag tag;

  @override
  Widget build(BuildContext context) {
    final color = switch (tag) {
      OfferTag.exclusive => Theme.of(context).colorScheme.primary,
      OfferTag.fresh => Theme.of(context).colorScheme.tertiary,
      OfferTag.popular => Theme.of(context).colorScheme.secondary,
      OfferTag.today => Theme.of(context).colorScheme.error,
      OfferTag.almostGone => Theme.of(context).colorScheme.error,
      OfferTag.hiddenGem => Theme.of(context).colorScheme.tertiary,
      OfferTag.topRated => Theme.of(context).colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, 0.88),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: Color.lerp(color, Colors.white, 0.76) ?? color,
        ),
      ),
      child: Text(
        tag.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF1C1C1E),
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
