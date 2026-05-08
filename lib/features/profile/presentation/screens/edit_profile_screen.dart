import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/icon_resolver.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../theme/app_colors.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;
  late Set<DealCategory> _selectedInterests;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameController = TextEditingController(text: user.name);
    _nicknameController = TextEditingController(
      text: user.handle.replaceFirst('@', ''),
    );
    _cityController = TextEditingController(text: user.city);
    _districtController = TextEditingController(text: user.district);
    _selectedInterests = <DealCategory>{
      ...user.favoriteCategories,
      ...user.preferences.interests,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Future<void> saveProfile() async {
      final user = ref.read(currentUserProvider);
      final nickname = _nicknameController.text.trim();
      final sessionController = ref.read(sessionControllerProvider.notifier);
      await sessionController.updateProfile(
        name: _nameController.text,
        handle: _buildHandle(
          nickname: nickname,
          name: _nameController.text,
          fallback: user.handle,
        ),
        city: _cityController.text,
        district: _districtController.text,
      );
      sessionController.selectInterests(
        _selectedInterests.toList(growable: false),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profil bearbeiten')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            120,
          ),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.t('Vor- und Nachname'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nicknameController,
                decoration: InputDecoration(labelText: context.t('Nickname')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _cityController,
                decoration: InputDecoration(labelText: context.t('Stadt')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _districtController,
                decoration: InputDecoration(labelText: context.t('Stadtteil')),
              ),
              const SizedBox(height: AppSpacing.xl),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Interessen',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Passe an, wofür sparGO dir künftig mehr Gutscheine zeigen soll.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: DealCategory.values
                    .map((category) {
                      final selected = _selectedInterests.contains(category);
                      return FilterChip(
                        selected: selected,
                        showCheckmark: false,
                        avatar: Icon(
                          iconForCategory(category),
                          size: 18,
                          color: selected
                              ? AppColors.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        label: Text(category.label),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.26)
                              : Theme.of(context).dividerColor,
                        ),
                        labelStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              color: selected
                                  ? AppColors.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                        onSelected: (enabled) {
                          setState(() {
                            if (enabled) {
                              _selectedInterests.add(category);
                            } else {
                              _selectedInterests.remove(category);
                            }
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedPadding(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AnimatedCtaButton(
            label: '\u00c4nderungen speichern',
            expanded: true,
            onPressed: saveProfile,
          ),
        ),
      ),
    );
  }

  String _buildHandle({
    required String nickname,
    required String name,
    required String fallback,
  }) {
    final seed = nickname.trim().isNotEmpty
        ? nickname.trim()
        : name.trim().isNotEmpty
        ? name.trim()
        : fallback.replaceFirst('@', '');
    final normalized = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${normalized.isEmpty ? 'spargo' : normalized}';
  }
}
