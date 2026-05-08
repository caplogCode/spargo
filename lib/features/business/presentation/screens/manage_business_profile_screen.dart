import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/address_suggestion_field.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../data/services/address_suggestion_service.dart';

class ManageBusinessProfileScreen extends ConsumerStatefulWidget {
  const ManageBusinessProfileScreen({super.key});

  @override
  ConsumerState<ManageBusinessProfileScreen> createState() =>
      _ManageBusinessProfileScreenState();
}

class _ManageBusinessProfileScreenState
    extends ConsumerState<ManageBusinessProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _taglineController;
  late final TextEditingController _shortDescriptionController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;
  late final TextEditingController _addressController;
  late final TextEditingController _websiteController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _legalNameController;
  late final TextEditingController _imprintController;
  late final TextEditingController _logoUrlController;
  late final TextEditingController _claimedByNameController;
  late final TextEditingController _claimedByRoleController;
  Uint8List? _selectedLogoBytes;
  String? _selectedLogoName;
  late DealCategory _selectedCategory;
  double? _selectedLatitude;
  double? _selectedLongitude;
  bool _ownershipConfirmed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final business = ref.read(ownedBusinessProvider);
    final source =
        ref.read(ownedBusinessDraftProvider) ??
        OwnedBusinessDraft.fromBusiness(business);

    _nameController = TextEditingController(text: source.name);
    _taglineController = TextEditingController(text: source.tagline);
    _shortDescriptionController = TextEditingController(
      text: source.shortDescription,
    );
    _descriptionController = TextEditingController(text: source.description);
    _cityController = TextEditingController(text: source.city);
    _districtController = TextEditingController(text: source.district);
    _addressController = TextEditingController(text: source.address);
    _websiteController = TextEditingController(text: source.website);
    _phoneController = TextEditingController(text: source.phone);
    _emailController = TextEditingController(text: source.contactEmail);
    _legalNameController = TextEditingController(text: source.legalEntityName);
    _imprintController = TextEditingController(text: source.imprintInfo);
    _logoUrlController = TextEditingController(text: business.imageUrl);
    _claimedByNameController = TextEditingController(
      text: source.claimedByName,
    );
    _claimedByRoleController = TextEditingController(
      text: source.claimedByRole,
    );
    _selectedCategory = source.category;
    _selectedLatitude = business.branches.isEmpty
        ? null
        : business.primaryBranch.latitude;
    _selectedLongitude = business.branches.isEmpty
        ? null
        : business.primaryBranch.longitude;
    _ownershipConfirmed = source.ownershipConfirmed;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _shortDescriptionController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _legalNameController.dispose();
    _imprintController.dispose();
    _logoUrlController.dispose();
    _claimedByNameController.dispose();
    _claimedByRoleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(ownedBusinessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business Profil')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _VerificationStatusCard(business: business),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(title: 'Auftritt'),
              _BusinessLogoFieldCard(
                imageUrl: _logoUrlController.text.trim(),
                logoBytes: _selectedLogoBytes,
                logoName: _selectedLogoName,
                onPick: _pickLogo,
                onClear: () {
                  setState(() {
                    _selectedLogoBytes = null;
                    _selectedLogoName = null;
                    _logoUrlController.clear();
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _logoUrlController,
                decoration: InputDecoration(
                  labelText: context.t('Logo URL (optional)'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: context.t('Name')),
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
              TextField(
                controller: _taglineController,
                decoration: InputDecoration(labelText: context.t('Tagline')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _shortDescriptionController,
                decoration: InputDecoration(
                  labelText: context.t('Kurzbeschreibung'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: context.t('Beschreibung'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(title: 'Standort'),
              TextField(
                controller: _cityController,
                decoration: InputDecoration(labelText: context.t('Stadt')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _districtController,
                decoration: InputDecoration(labelText: context.t('Stadtteil')),
              ),
              const SizedBox(height: AppSpacing.md),
              AddressSuggestionField(
                addressController: _addressController,
                cityController: _cityController,
                districtController: _districtController,
                onSelected: (AddressSuggestion suggestion) {
                  _selectedLatitude = suggestion.latitude;
                  _selectedLongitude = suggestion.longitude;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(title: 'Kontakt'),
              TextField(
                controller: _websiteController,
                decoration: InputDecoration(labelText: context.t('Website')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(labelText: context.t('Telefon')),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: context.t('Business-E-Mail'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(title: 'Impressum'),
              TextField(
                controller: _legalNameController,
                decoration: InputDecoration(
                  labelText: context.t('Rechtlicher Unternehmensname'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _imprintController,
                minLines: 4,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: context.t('Impressum / rechtliche Hinweise'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(title: 'Verantwortliche Person'),
              TextField(
                controller: _claimedByNameController,
                decoration: InputDecoration(
                  labelText: context.t('Vor- und Nachname'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _claimedByRoleController,
                decoration: InputDecoration(
                  labelText: context.t('Rolle im Unternehmen'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                value: _ownershipConfirmed,
                onChanged: (value) {
                  setState(() => _ownershipConfirmed = value ?? false);
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Ich bestätige weiterhin, dass ich dieses Unternehmen vertreten darf.',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedCtaButton(
                label: _submitting ? 'Wird gespeichert...' : 'Profil speichern',
                expanded: true,
                onPressed: _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final business = ref.read(ownedBusinessProvider);
    final user = ref.read(currentUserProvider);
    ref
        .read(ownedBusinessDraftProvider.notifier)
        .save(
          business: business,
          category: _selectedCategory,
          name: _nameController.text,
          tagline: _taglineController.text,
          description: _descriptionController.text,
          shortDescription: _shortDescriptionController.text,
          website: _websiteController.text,
          phone: _phoneController.text,
          contactEmail: _emailController.text,
          legalEntityName: _legalNameController.text,
          imprintInfo: _imprintController.text,
          address: _addressController.text,
          city: _cityController.text,
          district: _districtController.text,
          claimedByName: _claimedByNameController.text,
          claimedByRole: _claimedByRoleController.text,
          ownershipConfirmed: _ownershipConfirmed,
        );

    setState(() => _submitting = true);
    try {
      final businessId = await ref
          .read(repositoryProvider)
          .saveBusinessProfile(
            user: user,
            baseBusiness: business,
            businessId: business.id,
            category: _selectedCategory,
            name: _nameController.text,
            tagline: _taglineController.text,
            description: _descriptionController.text,
            shortDescription: _shortDescriptionController.text,
            website: _websiteController.text,
            phone: _phoneController.text,
            contactEmail: _emailController.text,
            legalEntityName: _legalNameController.text,
            imprintInfo: _imprintController.text,
            address: _addressController.text,
            city: _cityController.text,
            district: _districtController.text,
            claimedByName: _claimedByNameController.text,
            claimedByRole: _claimedByRoleController.text,
            ownershipConfirmed: _ownershipConfirmed,
            latitude: _selectedLatitude,
            longitude: _selectedLongitude,
            imageBytes: _selectedLogoBytes,
            imageUrl: _logoUrlController.text,
          );
      ref
          .read(sessionControllerProvider.notifier)
          .finishBusinessOnboarding(businessId: businessId);
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
          content: Text(
            'Business-Profil konnte nicht gespeichert werden: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    if (file.bytes == null) {
      return;
    }
    setState(() {
      _selectedLogoBytes = file.bytes;
      _selectedLogoName = file.name;
    });
  }
}

class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (business.verificationStatus) {
      BusinessVerificationStatus.verified => const Color(0xFF1F8B4D),
      BusinessVerificationStatus.pending => const Color(0xFFDB2149),
      BusinessVerificationStatus.rejected => const Color(0xFFC56A00),
      BusinessVerificationStatus.draft => const Color(0xFF6B7280),
    };
    final message = switch (business.verificationStatus) {
      BusinessVerificationStatus.verified =>
        'Dein Business ist automatisch verifiziert und kann live posten.',
      BusinessVerificationStatus.pending =>
        'Bitte bestätige deine Business-E-Mail und speichere das Profil erneut. Danach wird das Business automatisch verifiziert.',
      BusinessVerificationStatus.rejected =>
        'Deine Angaben passen noch nicht sauber zusammen. Prüfe Business-E-Mail, Website und Impressum und speichere erneut.',
      BusinessVerificationStatus.draft =>
        'Dein Business wurde noch nicht automatisch verifiziert.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            business.verificationStatus.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BusinessLogoFieldCard extends StatelessWidget {
  const _BusinessLogoFieldCard({
    required this.imageUrl,
    required this.logoBytes,
    required this.logoName,
    required this.onPick,
    required this.onClear,
  });

  final String imageUrl;
  final Uint8List? logoBytes;
  final String? logoName;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = logoBytes != null || imageUrl.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: logoBytes != null
                ? Image.memory(logoBytes!, fit: BoxFit.cover)
                : imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.storefront_rounded, size: 32);
                    },
                  )
                : const Icon(Icons.storefront_rounded, size: 32),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Firmenlogo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  logoName ??
                      (imageUrl.isNotEmpty
                          ? 'Aktuelles Logo wird verwendet'
                          : 'Noch kein Logo hinterlegt'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onPick,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Logo wählen'),
                    ),
                    if (hasImage)
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Entfernen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
