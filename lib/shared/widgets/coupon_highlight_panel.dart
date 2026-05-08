import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';

class CouponHighlightPanel extends StatelessWidget {
  const CouponHighlightPanel({
    super.key,
    required this.value,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.compact = false,
  });

  final String value;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? theme.textTheme.labelLarge
                      : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? theme.textTheme.bodySmall
              : theme.textTheme.bodyMedium,
        ),
      ],
    );

    return DottedBorder(
      color: theme.dividerColor,
      strokeWidth: 1.2,
      dashPattern: const <double>[6, 4],
      radius: Radius.circular(compact ? AppRadii.lg : AppRadii.xl),
      borderType: BorderType.RRect,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(
            compact ? AppRadii.lg : AppRadii.xl,
          ),
        ),
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: compact
            ? content
            : LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      trailing != null && constraints.maxWidth < 340;

                  if (trailing == null) {
                    return content;
                  }

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        content,
                        const SizedBox(height: AppSpacing.md),
                        trailing!,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: content),
                      const SizedBox(width: AppSpacing.md),
                      trailing!,
                    ],
                  );
                },
              ),
      ),
    );
  }
}
