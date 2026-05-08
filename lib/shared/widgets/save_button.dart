import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_tokens.dart';
import '../providers/app_providers.dart';

class SaveButton extends ConsumerWidget {
  const SaveButton({super.key, required this.dealId, this.compact = false});

  final String dealId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = ref.watch(savedDealsProvider).contains(dealId);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      onTap: () => ref.read(savedDealsProvider.notifier).toggle(dealId),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
          vertical: compact ? AppSpacing.xs : AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSaved
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Icon(
          isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: compact ? 18 : 20,
          color: isSaved
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
