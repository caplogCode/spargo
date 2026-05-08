import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/web_image_proxy.dart';
import '../../domain/models/story_models.dart';
import '../providers/app_providers.dart';
import '../../theme/app_colors.dart';

class StoryBubble extends ConsumerWidget {
  const StoryBubble({
    super.key,
    required this.story,
    required this.isSeen,
    required this.onTap,
  });

  final Story story;
  final bool isSeen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final business = ref.watch(businessByIdProvider(story.businessId));
    final logoImageUrl = business.imageUrl.trim();
    final storyPreviewImageUrl = story.items
        .map((item) => item.imageUrl.trim())
        .firstWhere((url) => url.isNotEmpty, orElse: () => '');
    final resolvedImageUrl = webSafeImageUrl(
      logoImageUrl.isNotEmpty ? logoImageUrl : storyPreviewImageUrl,
    );
    final initials = story.businessName
        .split(' ')
        .take(2)
        .map((part) => part.isNotEmpty ? part[0] : '')
        .join()
        .toUpperCase();
    final palette = story.previewPalette.map(Color.new).toList(growable: false);
    final primaryGlow = palette.isNotEmpty ? palette.first : AppColors.primary;
    final secondaryGlow = palette.length > 1
        ? palette[1]
        : AppColors.highlightMid;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(44),
          child: SizedBox(
            width: 88,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 82,
                  height: 82,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: primaryGlow.withValues(
                                alpha: isSeen ? 0.10 : 0.22,
                              ),
                              blurRadius: isSeen ? 14 : 28,
                              spreadRadius: isSeen ? 0 : 2,
                            ),
                            BoxShadow(
                              color: secondaryGlow.withValues(
                                alpha: isSeen ? 0.08 : 0.18,
                              ),
                              blurRadius: isSeen ? 18 : 34,
                              spreadRadius: isSeen ? 0 : 3,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 78,
                        height: 78,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isSeen
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    primaryGlow.withValues(alpha: 0.28),
                                    secondaryGlow.withValues(alpha: 0.22),
                                  ],
                                )
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[primaryGlow, secondaryGlow],
                                ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: ClipOval(
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: <Color>[
                                        primaryGlow,
                                        secondaryGlow,
                                      ],
                                    ),
                                  ),
                                ),
                                if (resolvedImageUrl != null)
                                  Image.network(
                                    resolvedImageUrl,
                                    fit: BoxFit.cover,
                                    webHtmlElementStrategy:
                                        WebHtmlElementStrategy.fallback,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          initials,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: resolvedImageUrl == null
                                        ? Colors.transparent
                                        : Colors.black.withValues(alpha: 0.05),
                                  ),
                                ),
                                if (resolvedImageUrl == null)
                                  Center(
                                    child: Text(
                                      initials,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  story.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
