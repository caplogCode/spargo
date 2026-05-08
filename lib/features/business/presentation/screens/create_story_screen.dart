import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/widgets/adaptive_scroll_body.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../theme/app_colors.dart';

class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _ctaLabelController = TextEditingController(text: 'Mehr dazu');
  final _imageUrlController = TextEditingController();

  StoryType _storyType = StoryType.behindTheScenes;
  String? _linkedDealId;
  Uint8List? _selectedImageBytes;
  String _selectedImageName = '';
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _bodyController.dispose();
    _ctaLabelController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = ref.watch(ownedBusinessCanPublishProvider);
    final business = ref.watch(ownedBusinessProvider);
    final deals = ref.watch(businessDealsProvider(business.id));
    final linkableDeals = deals.where((deal) => !deal.isThirdParty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Story erstellen')),
      body: AdaptiveScrollBody(
        child: Column(
          children: <Widget>[
            if (!canPublish) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4F6),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: const Text(
                  'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor Stories live gehen.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _StoryMediaCard(
              imageBytes: _selectedImageBytes,
              imageName: _selectedImageName,
              imageUrl: _imageUrlController.text.trim(),
              controller: _imageUrlController,
              onPickImage: _pickImage,
              onClearImage: () {
                setState(() {
                  _selectedImageBytes = null;
                  _selectedImageName = '';
                  _imageUrlController.clear();
                });
              },
              onUrlChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<StoryType>(
              value: _storyType,
              decoration: InputDecoration(labelText: context.t('Story Typ')),
              items: StoryType.values
                  .map((type) {
                    return DropdownMenuItem<StoryType>(
                      value: type,
                      child: Text(type.label),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _storyType = value;
                  if (_storyType != StoryType.deal) {
                    _linkedDealId = null;
                    if (_ctaLabelController.text.trim().isEmpty ||
                        _ctaLabelController.text.trim() == 'Zum Deal') {
                      _ctaLabelController.text = 'Mehr dazu';
                    }
                  } else {
                    _ctaLabelController.text = 'Zum Deal';
                  }
                });
              },
            ),
            if (_storyType == StoryType.deal) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                value: _linkedDealId,
                decoration: InputDecoration(
                  labelText: context.t('Verknüpfter Gutschein'),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Keinen Gutschein wählen'),
                  ),
                  ...linkableDeals.map((deal) {
                    return DropdownMenuItem<String?>(
                      value: deal.id,
                      child: Text(deal.title, overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: (value) => setState(() => _linkedDealId = value),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: context.t('Headline')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _subtitleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: context.t('Subline')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _bodyController,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.t('Story Text'),
                hintText: context.t('Was sollen Nutzer direkt verstehen?'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _ctaLabelController,
              decoration: InputDecoration(
                labelText: context.t('CTA'),
                hintText: context.t('Mehr dazu oder Zum Deal'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AnimatedCtaButton(
              label: _submitting
                  ? 'Wird veröffentlicht...'
                  : 'Story veröffentlichen',
              expanded: true,
              onPressed: _submitting || !canPublish ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    if (file.bytes == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Das Bild konnte nicht gelesen werden.')),
      );
      return;
    }
    setState(() {
      _selectedImageBytes = file.bytes;
      _selectedImageName = file.name;
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final body = _bodyController.text.trim();
    final ctaLabel = _ctaLabelController.text.trim();
    if (title.isEmpty || subtitle.isEmpty || body.isEmpty || ctaLabel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte Headline, Subline, Story-Text und CTA ausfüllen.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(repositoryProvider)
          .createStory(
            user: ref.read(currentUserProvider),
            business: ref.read(ownedBusinessProvider),
            type: _storyType,
            title: title,
            subtitle: subtitle,
            body: body,
            ctaLabel: ctaLabel,
            imageBytes: _selectedImageBytes,
            imageUrl: _imageUrlController.text.trim(),
            dealId: _storyType == StoryType.deal ? _linkedDealId : null,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Story konnte nicht gespeichert werden: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _StoryMediaCard extends StatelessWidget {
  const _StoryMediaCard({
    required this.imageBytes,
    required this.imageName,
    required this.imageUrl,
    required this.controller,
    required this.onPickImage,
    required this.onClearImage,
    required this.onUrlChanged,
  });

  final Uint8List? imageBytes;
  final String imageName;
  final String imageUrl;
  final TextEditingController controller;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final ValueChanged<String> onUrlChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPreview = imageBytes != null || imageUrl.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Story Bild',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Wird im Story-Kreis, im Viewer und im Business-Profil angezeigt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 188,
              width: double.infinity,
              color: const Color(0xFFFFF1F4),
              child: hasPreview
                  ? Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (imageBytes != null)
                          Image.memory(imageBytes!, fit: BoxFit.cover)
                        else
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (context, error, stackTrace) {
                              return const _StoryMediaPlaceholder(
                                label: 'Vorschau konnte nicht geladen werden',
                              );
                            },
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.28),
                              ],
                            ),
                          ),
                        ),
                        if (imageName.isNotEmpty)
                          Positioned(
                            left: AppSpacing.md,
                            right: AppSpacing.md,
                            bottom: AppSpacing.md,
                            child: Text(
                              imageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    )
                  : const _StoryMediaPlaceholder(
                      label: 'Noch kein Story-Bild ausgewählt',
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Bild auswählen'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasPreview ? onClearImage : null,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Zurücksetzen'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            onChanged: onUrlChanged,
            decoration: InputDecoration(
              labelText: context.t('Bild-URL alternativ'),
              hintText: context.t('https://...'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryMediaPlaceholder extends StatelessWidget {
  const _StoryMediaPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.auto_stories_rounded,
            size: 30,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
