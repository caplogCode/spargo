import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../core/widgets/adaptive_scroll_body.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../theme/app_colors.dart';

class BusinessDealEditorScreen extends ConsumerStatefulWidget {
  const BusinessDealEditorScreen({super.key, this.dealId});

  final String? dealId;

  @override
  ConsumerState<BusinessDealEditorScreen> createState() =>
      _BusinessDealEditorScreenState();
}

class _BusinessDealEditorScreenState
    extends ConsumerState<BusinessDealEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _discountController;
  late final TextEditingController _imageUrlController;
  late DealCategory _selectedCategory;
  late int _availabilityDays;
  Uint8List? _selectedImageBytes;
  String _selectedImageName = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final deal = widget.dealId == null
        ? null
        : ref.read(dealByIdProvider(widget.dealId!));
    _titleController = TextEditingController(text: deal?.title ?? '');
    _descriptionController = TextEditingController(
      text: deal?.description ?? '',
    );
    _discountController = TextEditingController(
      text: deal == null ? '20' : '${deal.savingsPercent}',
    );
    _imageUrlController = TextEditingController(text: deal?.imageUrl ?? '');
    _selectedCategory =
        deal?.category ?? ref.read(ownedBusinessProvider).category;
    _availabilityDays = deal == null
        ? 7
        : (deal.validUntil.difference(DateTime.now()).inDays + 1)
              .clamp(1, 365)
              .toInt();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _discountController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = ref.watch(ownedBusinessCanPublishProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.dealId == null ? 'Deal erstellen' : 'Deal bearbeiten',
        ),
      ),
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
                  'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor Gutscheine live gehen.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _DealMediaCard(
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
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: context.t('Titel')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(labelText: context.t('Beschreibung')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.t('Vorteil in %')),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<DealCategory>(
              value: _selectedCategory,
              decoration: InputDecoration(labelText: context.t('Kategorie')),
              items: DealCategory.values
                  .map(
                    (category) => DropdownMenuItem<DealCategory>(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedCategory = value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int>(
              value: _availabilityDays,
              decoration: InputDecoration(
                labelText: context.t('Verfügbar für'),
              ),
              items: const <int>[1, 3, 7, 14, 30, 60, 90]
                  .map(
                    (days) => DropdownMenuItem<int>(
                      value: days,
                      child: Text(_availabilityLabel(days)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _availabilityDays = value);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            AnimatedCtaButton(
              label: _submitting
                  ? 'Wird gespeichert...'
                  : widget.dealId == null
                  ? 'Deal anlegen'
                  : 'Änderungen speichern',
              expanded: true,
              onPressed: _submitting || !canPublish ? null : _saveDeal,
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

  Future<void> _saveDeal() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final savingsPercent = int.tryParse(_discountController.text.trim());
    if (title.isEmpty || description.isEmpty || savingsPercent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte Titel, Beschreibung und Prozentwert korrekt ausfüllen.',
          ),
        ),
      );
      return;
    }
    if (savingsPercent < 1 || savingsPercent > 90) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte einen realen Vorteil zwischen 1% und 90% angeben.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final business = ref.read(ownedBusinessProvider);
      final user = ref.read(currentUserProvider);
      final existingDeal = widget.dealId == null
          ? null
          : ref.read(dealByIdProvider(widget.dealId!));

      await ref
          .read(repositoryProvider)
          .upsertDeal(
            user: user,
            business: business,
            existingDeal: existingDeal,
            category: _selectedCategory,
            availabilityDays: _availabilityDays,
            title: title,
            description: description,
            savingsPercent: savingsPercent,
            imageBytes: _selectedImageBytes,
            imageUrl: _imageUrlController.text.trim(),
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
        SnackBar(content: Text('Deal konnte nicht gespeichert werden: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  static String _availabilityLabel(int days) {
    return switch (days) {
      1 => 'Heute',
      3 => '3 Tage',
      7 => '1 Woche',
      14 => '2 Wochen',
      30 => '30 Tage',
      60 => '60 Tage',
      90 => '90 Tage',
      _ => '$days Tage',
    };
  }
}

class _DealMediaCard extends StatelessWidget {
  const _DealMediaCard({
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
            'Gutschein Bild',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Wird im Feed, im Nah-Tab und in der Detailansicht verwendet.',
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
                              return const _DealMediaPlaceholder(
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
                                Colors.black.withValues(alpha: 0.26),
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
                  : const _DealMediaPlaceholder(
                      label: 'Noch kein Gutschein-Bild ausgewählt',
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

class _DealMediaPlaceholder extends StatelessWidget {
  const _DealMediaPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.local_offer_rounded,
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
