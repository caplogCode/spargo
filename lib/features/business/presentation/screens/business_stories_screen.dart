import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';

class BusinessStoriesScreen extends ConsumerWidget {
  const BusinessStoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(ownedBusinessProvider);
    final canPublish = ref.watch(ownedBusinessCanPublishProvider);
    final stories = ref
        .watch(storiesProvider)
        .where((story) => story.businessId == business.id)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stories verwalten'),
        actions: <Widget>[
          IconButton(
            onPressed: canPublish
                ? () => Navigator.of(context).pushNamed(AppRoutes.createStory)
                : () => _showVerificationBlocked(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          if (!canPublish) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F6),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Text(
                business.verificationStatus ==
                        BusinessVerificationStatus.rejected
                    ? 'Dein Business wurde abgelehnt. Bitte korrigiere die Angaben und reiche es erneut ein.'
                    : 'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor neue Stories live gehen.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (stories.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Text(
                'Noch keine Story ver\u00f6ffentlicht. Poste Highlights, Events oder Deal-Updates direkt aus dem Dashboard.',
              ),
            ),
          ...List<Widget>.generate(stories.length, (index) {
            final story = stories[index];
            final previewImageUrl = story.items.isNotEmpty
                ? story.items.first.imageUrl.trim()
                : '';
            final storyTypeLabel = story.items.isNotEmpty
                ? story.items.first.type.label
                : 'Story';

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == stories.length - 1 ? 0 : AppSpacing.md,
              ),
              child: ListTile(
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.storyViewer,
                  arguments: StoryViewerArgs(storyId: story.id),
                ),
                contentPadding: const EdgeInsets.all(AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                tileColor: Theme.of(context).colorScheme.surface,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: previewImageUrl.isEmpty
                        ? Container(
                            color: const Color(0xFFFFEEF2),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.auto_stories_rounded,
                              color: AppColors.primary,
                            ),
                          )
                        : Image.network(
                            previewImageUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: const Color(0xFFFFEEF2),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.auto_stories_rounded,
                                  color: AppColors.primary,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                title: Text(
                  story.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '$storyTypeLabel \u00b7 ${story.items.length} '
                  'Slide${story.items.length == 1 ? '' : 's'} \u00b7 ${story.timeLabel}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'open') {
                      Navigator.of(context).pushNamed(
                        AppRoutes.storyViewer,
                        arguments: StoryViewerArgs(storyId: story.id),
                      );
                      return;
                    }
                    if (value == 'delete') {
                      _confirmDeleteStory(context, ref, business, story);
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'open', child: Text('Ansehen')),
                    PopupMenuItem(value: 'delete', child: Text('Löschen')),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showVerificationBlocked(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor neue Stories live gehen.',
        ),
      ),
    );
  }

  Future<void> _confirmDeleteStory(
    BuildContext context,
    WidgetRef ref,
    Business business,
    Story story,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Story löschen?'),
        content: Text(
          '"${story.label}" wird sofort aus dem lokalen Feed entfernt.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(repositoryProvider)
          .deleteBusinessStory(business: business, storyId: story.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Story wurde gelöscht.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Story konnte nicht gelöscht werden: $error')),
      );
    }
  }
}
