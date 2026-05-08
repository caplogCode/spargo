import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:typed_data';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/nearby_place_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../data/services/address_suggestion_service.dart';
import '../../../../shared/providers/app_language_provider.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/address_suggestion_field.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../theme/app_colors.dart';

class _VerificationProgressStep {
  const _VerificationProgressStep({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

class BusinessOnboardingScreen extends ConsumerStatefulWidget {
  const BusinessOnboardingScreen({super.key});

  @override
  ConsumerState<BusinessOnboardingScreen> createState() =>
      _BusinessOnboardingScreenState();
}

class _BusinessOnboardingScreenState
    extends ConsumerState<BusinessOnboardingScreen> {
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
  late final TextEditingController _claimedByNameController;
  late final TextEditingController _claimedByRoleController;

  bool _ownershipConfirmed = false;
  bool _submitting = false;
  bool _sendingVerification = false;
  bool _refreshingVerification = false;
  bool _connectingGoogleProfile = false;
  bool _verifyingDocumentEvidence = false;
  String _documentEvidenceName = '';
  String _verificationProgressTitle = '';
  String _verificationProgressSubtitle = '';
  List<_VerificationProgressStep> _verificationProgressSteps =
      const <_VerificationProgressStep>[];
  int _verificationProgressIndex = -1;
  late DealCategory _selectedCategory;
  double? _selectedLatitude;
  double? _selectedLongitude;
  late BusinessVerificationMethod _verificationMethod;
  late BusinessGoogleProfileLink _googleProfileLink;
  late String _verificationPlaceId;
  late String _verificationWebsite;
  Timer? _verificationProgressTimer;

  @override
  void initState() {
    super.initState();
    final business = ref.read(ownedBusinessProvider);
    final draft = ref.read(ownedBusinessDraftProvider);
    final user = ref.read(currentUserProvider);
    final authUser = ref.read(authUserProvider);
    final session = ref.read(sessionControllerProvider);
    final source = draft ?? OwnedBusinessDraft.fromBusiness(business);
    final fallbackCity = user.city == 'Deutschlandweit' ? '' : user.city.trim();
    final fallbackDistrict = user.district == 'Dein Viertel'
        ? ''
        : user.district.trim();

    _nameController = TextEditingController(text: source.name);
    _taglineController = TextEditingController(text: source.tagline);
    _shortDescriptionController = TextEditingController(
      text: source.shortDescription,
    );
    _descriptionController = TextEditingController(text: source.description);
    _cityController = TextEditingController(
      text: source.city.trim().isEmpty ? fallbackCity : source.city,
    );
    _districtController = TextEditingController(
      text: source.district.trim().isEmpty ? fallbackDistrict : source.district,
    );
    _addressController = TextEditingController(text: source.address);
    _websiteController = TextEditingController(text: source.website);
    _phoneController = TextEditingController(text: source.phone);
    _emailController = TextEditingController(
      text: source.contactEmail.isEmpty
          ? (authUser?.email ?? '')
          : source.contactEmail,
    );
    _legalNameController = TextEditingController(
      text: source.legalEntityName.isEmpty
          ? source.name
          : source.legalEntityName,
    );
    _imprintController = TextEditingController(text: source.imprintInfo);
    _claimedByNameController = TextEditingController(
      text: source.claimedByName.isEmpty ? user.name : source.claimedByName,
    );
    _claimedByRoleController = TextEditingController(
      text: source.claimedByRole.isEmpty
          ? 'Inhaberin / Inhaber'
          : source.claimedByRole,
    );
    _selectedCategory = source.category;
    _selectedLatitude = business.branches.isEmpty
        ? null
        : business.primaryBranch.latitude;
    _selectedLongitude = business.branches.isEmpty
        ? null
        : business.primaryBranch.longitude;
    _verificationMethod = source.verificationMethod;
    _googleProfileLink = source.googleProfileLink;
    _ownershipConfirmed = source.ownershipConfirmed;
    _verificationPlaceId = source.verificationPlaceId.trim().isNotEmpty
        ? source.verificationPlaceId.trim()
        : source.googleProfileLink.placeId.trim();
    _verificationWebsite = source.verificationWebsite.trim().isNotEmpty
        ? source.verificationWebsite.trim()
        : (source.googleProfileLink.website.trim().isNotEmpty
              ? source.googleProfileLink.website.trim()
              : source.website.trim());
    final lockedAuthEmail =
        authUser != null &&
            !authUser.isAnonymous &&
            session.isAuthenticated &&
            session.user.accountType == AccountType.business
        ? (authUser.email ?? '').trim()
        : '';
    if (lockedAuthEmail.isNotEmpty) {
      _emailController.text = lockedAuthEmail;
    }
    if (_verificationWebsite.isNotEmpty) {
      _websiteController.text = _verificationWebsite;
    }
    _syncPreferredVerificationMethod();
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
    _claimedByNameController.dispose();
    _claimedByRoleController.dispose();
    _verificationProgressTimer?.cancel();
    super.dispose();
  }

  void _startVerificationProgress({
    required String title,
    required String subtitle,
    required List<_VerificationProgressStep> steps,
  }) {
    _verificationProgressTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _verificationProgressTitle = title;
      _verificationProgressSubtitle = subtitle;
      _verificationProgressSteps = steps;
      _verificationProgressIndex = steps.isEmpty ? -1 : 0;
    });
    if (steps.length <= 1) {
      return;
    }
    _verificationProgressTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_verificationProgressIndex >= _verificationProgressSteps.length - 1) {
          timer.cancel();
          return;
        }
        _verificationProgressIndex += 1;
      });
    });
  }

  void _setVerificationProgressStage(int index, {String? subtitle}) {
    if (!mounted || _verificationProgressSteps.isEmpty) {
      return;
    }
    final clampedIndex = index < 0
        ? 0
        : (index >= _verificationProgressSteps.length
              ? _verificationProgressSteps.length - 1
              : index);
    setState(() {
      _verificationProgressIndex = clampedIndex;
      if (subtitle != null && subtitle.trim().isNotEmpty) {
        _verificationProgressSubtitle = subtitle;
      }
    });
  }

  void _clearVerificationProgress() {
    _verificationProgressTimer?.cancel();
    _verificationProgressTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _verificationProgressTitle = '';
      _verificationProgressSubtitle = '';
      _verificationProgressSteps = const <_VerificationProgressStep>[];
      _verificationProgressIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final authUser = ref.watch(authUserProvider);
    final hasConsumerSession =
        authUser != null &&
        !authUser.isAnonymous &&
        session.isAuthenticated &&
        session.user.accountType == AccountType.user;
    final trustedBusinessAuthEmail =
        authUser != null &&
            !authUser.isAnonymous &&
            session.isAuthenticated &&
            session.user.accountType == AccountType.business
        ? (authUser.email ?? '').trim()
        : '';
    final languageCode = ref.watch(appLanguageControllerProvider).languageCode;
    final verifiedEmail =
        trustedBusinessAuthEmail.isNotEmpty && (authUser?.emailVerified ?? false);
    final authEmail = trustedBusinessAuthEmail;
    if (authEmail.isNotEmpty && _emailController.text.trim() != authEmail) {
      _emailController.value = _emailController.value.copyWith(
        text: authEmail,
        selection: TextSelection.collapsed(offset: authEmail.length),
        composing: TextRange.empty,
      );
    }
    if (_verificationWebsite.trim().isNotEmpty &&
        _websiteController.text.trim() != _verificationWebsite.trim()) {
      _websiteController.value = _websiteController.value.copyWith(
        text: _verificationWebsite.trim(),
        selection: TextSelection.collapsed(
          offset: _verificationWebsite.trim().length,
        ),
        composing: TextRange.empty,
      );
    }
    final contactEmail = authEmail.isNotEmpty
        ? authEmail
        : _emailController.text.trim();
    const canUseEmailDomainVerification = false;
    final emailModeLocked = authEmail.isNotEmpty;
    final websiteModeLocked = _verificationWebsite.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F3F7),
        body: Stack(
          children: <Widget>[
            const _BusinessOnboardingBackdrop(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isPhone = constraints.maxWidth < 960;
                  final compactDesktop =
                      !isPhone &&
                      (constraints.maxHeight < 980 ||
                          constraints.maxWidth < 1480);
                  final horizontalPadding = isPhone
                      ? 16.0
                      : (compactDesktop ? 20.0 : 28.0);
                  final verticalPadding = isPhone
                      ? 12.0
                      : (compactDesktop ? 16.0 : 24.0);
                  final maxWidth = isPhone ? 620.0 : 1500.0;
                  final minHeight =
                      constraints.maxHeight - (verticalPadding * 2);

                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                      child: isPhone
                          ? SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxWidth,
                                    minHeight: minHeight < 0 ? 0 : minHeight,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      _buildOnboardingHeroPanel(
                                        theme,
                                        compact: true,
                                      ),
                                      const SizedBox(height: 16),
                                      _buildOnboardingEntryPanel(
                                        theme,
                                        authEmail: authEmail,
                                        verifiedEmail: verifiedEmail,
                                        hasConsumerSession: hasConsumerSession,
                                        canUseEmailDomainVerification:
                                            canUseEmailDomainVerification,
                                        effectiveContactEmail: contactEmail,
                                        emailModeLocked: emailModeLocked,
                                        websiteModeLocked: websiteModeLocked,
                                        languageCode: languageCode,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: maxWidth,
                                  minHeight: minHeight < 0 ? 0 : minHeight,
                                  maxHeight: minHeight < 0 ? 0 : minHeight,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Expanded(
                                      flex: 11,
                                      child: _buildOnboardingHeroPanel(
                                        theme,
                                        compact: compactDesktop,
                                      ),
                                    ),
                                    SizedBox(
                                      width: compactDesktop ? 18 : 24,
                                    ),
                                    Expanded(
                                      flex: 12,
                                      child: _buildOnboardingEntryPanel(
                                        theme,
                                        authEmail: authEmail,
                                        verifiedEmail: verifiedEmail,
                                        hasConsumerSession: hasConsumerSession,
                                        canUseEmailDomainVerification:
                                            canUseEmailDomainVerification,
                                        effectiveContactEmail: contactEmail,
                                        emailModeLocked: emailModeLocked,
                                        websiteModeLocked: websiteModeLocked,
                                        languageCode: languageCode,
                                        compact: compactDesktop,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(
      AppRoutes.businessRegister,
      (route) => false,
    );
  }

  Future<void> _openLanguageSheet() async {
    final selectedCode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BusinessOnboardingLanguageSheet(
        selectedCode: ref.read(appLanguageControllerProvider).languageCode,
      ),
    );
    if (!mounted || selectedCode == null) {
      return;
    }
    await ref
        .read(appLanguageControllerProvider.notifier)
        .setLanguageCode(selectedCode);
  }

  Widget _buildOnboardingHeroPanel(ThemeData theme, {required bool compact}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Image.asset(
                  'assets/branding/spargo_onboarding_logo.png',
                  width: compact ? 170 : 210,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                Chip(
                  avatar: const Icon(Icons.business_center_outlined, size: 18),
                  label: const Text('Business Studio'),
                ),
              ],
            ),
            SizedBox(height: compact ? 18 : 22),
            Text(
              'Business.',
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: compact ? 34 : 48,
                height: 0.98,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              'Sauber.',
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: compact ? 34 : 48,
                height: 0.98,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              'Live.',
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: compact ? 34 : 48,
                height: 0.98,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              'Verknüpfe dein Business sauber über Google oder offizielle Unterlagen und bring dein Studio danach direkt live.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5F6574),
                height: 1.4,
              ),
            ),
            SizedBox(height: compact ? 18 : 24),
            _BusinessOnboardingHeroFeature(
              icon: Icons.verified_user_outlined,
              title: 'Zugriff sauber absichern',
              subtitle:
                  'Nur bestätigte Google-Business-Zugriffe dürfen dieses Studio steuern.',
              compact: compact,
            ),
            SizedBox(height: compact ? 12 : 14),
            _BusinessOnboardingHeroFeature(
              icon: Icons.storefront_outlined,
              title: 'Standort sauber zuordnen',
              subtitle:
                  'Adresse, Website und Kontakt werden direkt an den echten Ort gebunden.',
              compact: compact,
            ),
            SizedBox(height: compact ? 12 : 14),
            _BusinessOnboardingHeroFeature(
              icon: Icons.trending_up_rounded,
              title: 'Studio sauber vorbereiten',
              subtitle:
                  'Danach sind Dashboard, Angebote und Stories an einem Ort bereit.',
              compact: compact,
            ),
            SizedBox(height: compact ? 18 : 24),
            const _BusinessOnboardingVerificationHint(),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingEntryPanel(
    ThemeData theme, {
    required String authEmail,
    required bool verifiedEmail,
    required bool hasConsumerSession,
    required bool canUseEmailDomainVerification,
    required String effectiveContactEmail,
    required bool emailModeLocked,
    required bool websiteModeLocked,
    required String languageCode,
    required bool compact,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 24,
          compact ? 18 : 24,
          compact ? 18 : 24,
          compact ? 16 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppBackButton(onTap: _handleBackNavigation),
                const Spacer(),
                _BusinessOnboardingLanguagePill(
                  languageCode: languageCode,
                  onTap: _openLanguageSheet,
                ),
              ],
            ),
            SizedBox(height: compact ? 14 : 18),
            Expanded(
              child: hasConsumerSession
                  ? _buildConsumerSessionBlockedCard(theme, compact: compact)
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Business einrichten',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Prüfe den Zugriff, vervollständige die Stammdaten und schalte dein Studio danach sauber frei.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SetupProgressRail(
                            verificationMethod: _verificationMethod,
                            canUseEmailDomainVerification:
                                canUseEmailDomainVerification,
                            verifiedEmail: verifiedEmail,
                            googleProfileLink: _googleProfileLink,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _VerificationMethodCard(
                            verificationMethod: _verificationMethod,
                            authEmail: authEmail,
                            verificationWebsite: _verificationWebsite,
                            canUseEmailDomainVerification:
                                canUseEmailDomainVerification,
                            googleProfileLink: _googleProfileLink,
                            connectingGoogleProfile: _connectingGoogleProfile,
                            verifyingDocumentEvidence:
                                _verifyingDocumentEvidence,
                            documentEvidenceName: _documentEvidenceName,
                            verificationProgressTitle:
                                _verificationProgressTitle,
                            verificationProgressSubtitle:
                                _verificationProgressSubtitle,
                            verificationProgressSteps:
                                _verificationProgressSteps,
                            verificationProgressIndex:
                                _verificationProgressIndex,
                            onConnectGoogle: _connectGoogleBusinessProfile,
                            onVerifyDocuments: _verifyBusinessEvidenceDocument,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const _SectionTitle(
                            title: 'Schnellstart',
                            subtitle:
                                'Nur das Nötige ausfüllen. sparGO ergänzt den Rest, sobald Google und deine Stammdaten sauber stehen.',
                          ),
                          _InputCard(
                            child: Column(
                              children: <Widget>[
                                TextField(
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: context.t('Business-Name (optional)'),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                DropdownButtonFormField<DealCategory>(
                                  value: _selectedCategory,
                                  decoration: InputDecoration(
                                    labelText: context.t('Kategorie'),
                                  ),
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
                                  controller: _websiteController,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                  readOnly: websiteModeLocked,
                                  onChanged: (_) =>
                                      setState(_syncPreferredVerificationMethod),
                                  decoration: InputDecoration(
                                    labelText: context.t('Website (optional)'),
                                    hintText: context.t('https://dein-business.de'),
                                    helperText: websiteModeLocked
                                        ? context.t(
                                            'Wird direkt vom ausgewählten Standort übernommen.',
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  readOnly: emailModeLocked,
                                  onChanged: (_) =>
                                      setState(_syncPreferredVerificationMethod),
                                  decoration: InputDecoration(
                                    labelText: context.t('Business-E-Mail'),
                                    hintText: context.t('kontakt@dein-business.de'),
                                    helperText: emailModeLocked
                                        ? context.t(
                                            'Wird direkt aus deinem verifizierten Login übernommen.',
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _googleProfileLink.grantsDashboardAccess
                                        ? 'Business-Identität bestätigt. Du kannst direkt weiterarbeiten.'
                                        : 'Bestätige zuerst die passende Business-Identität für genau diesen Standort, damit dieses Studio sicher freigeschaltet werden kann.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Theme(
                            data: theme.copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          'Mehr Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'Optional, wenn du dein Profil direkt vollständiger machen willst.',
                        ),
                        children: <Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          _InputCard(
                            child: Column(
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: TextField(
                                        controller: _cityController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: context.t('Stadt'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: TextField(
                                        controller: _districtController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: context.t('Stadtteil'),
                                        ),
                                      ),
                                    ),
                                  ],
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
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _taglineController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: context.t('Tagline'),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: context.t('Telefon'),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _legalNameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: context.t(
                                      'Rechtlicher Unternehmensname',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: TextField(
                                        controller: _claimedByNameController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: context.t(
                                            'Verantwortliche Person',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: TextField(
                                        controller: _claimedByRoleController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: context.t('Rolle'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _imprintController,
                                  minLines: 3,
                                  maxLines: 5,
                                  decoration: InputDecoration(
                                    labelText: context.t(
                                      'Impressum / rechtliche Hinweise',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _shortDescriptionController,
                                  minLines: 2,
                                  maxLines: 3,
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_submitting) ...<Widget>[
                      const LinearProgressIndicator(minHeight: 4),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedCtaButton(
              label: _submitting
                  ? 'Business wird angelegt...'
                  : 'Business jetzt anlegen',
              expanded: true,
              onPressed: _submitting || hasConsumerSession
                  ? null
                  : _saveBusinessProfile,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Du bleibst auf diesem Screen, bis dein Business sauber angelegt ist.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumerSessionBlockedCard(
    ThemeData theme, {
    required bool compact,
  }) {
    final authEmail = (ref.read(authUserProvider)?.email ?? '').trim();
    return Center(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 18 : 22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8DCE1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: compact ? 24 : 28,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.lock_person_rounded,
                color: AppColors.primary,
                size: compact ? 24 : 28,
              ),
            ),
            SizedBox(height: compact ? 14 : 16),
            Text(
              'Nutzerkonto erkannt',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              authEmail.isEmpty
                  ? 'Dieses sparGO-Nutzerkonto darf kein Business übernehmen oder anlegen. Bitte melde dich zuerst aus und starte danach mit einem separaten Business-Zugang neu.'
                  : 'Du bist gerade mit $authEmail als Nutzerkonto angemeldet. Dieses Konto darf kein Business übernehmen oder anlegen. Bitte melde dich zuerst aus und starte danach mit einem separaten Business-Zugang neu.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            SizedBox(height: compact ? 16 : 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _signOutConsumerSession,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Ausloggen und Business neu starten'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendVerification() async {
    setState(() => _sendingVerification = true);
    try {
      await ref.read(repositoryProvider).sendEmailVerification();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bestätigungslink wurde an deine Business-E-Mail gesendet.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-Mail konnte nicht gesendet werden: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingVerification = false);
      }
    }
  }

  Future<void> _refreshVerification() async {
    setState(() => _refreshingVerification = true);
    try {
      await ref.read(repositoryProvider).reloadCurrentAuthUser();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verifizierungsstatus wurde aktualisiert.'),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status konnte nicht aktualisiert werden: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingVerification = false);
      }
    }
  }

  Future<void> _connectGoogleBusinessProfile() async {
    if (_connectingGoogleProfile) {
      return;
    }
    if (!_ensureBusinessFlowAllowed()) {
      return;
    }

    final expectedPlaceId = _verificationPlaceId.trim();
    if (expectedPlaceId.isEmpty) {
      _showError(
        'Für diesen Schritt fehlt der vorher ausgewählte Google-Standort. Bitte starte die Business-Registrierung erneut über die Standortsuche.',
      );
      return;
    }

    final expectedPlace = NearbyPlace(
      id: expectedPlaceId,
      name: _googleProfileLink.locationDisplayName.trim().isNotEmpty
          ? _googleProfileLink.locationDisplayName.trim()
          : _nameController.text.trim(),
      address: _googleProfileLink.locationAddress.trim().isNotEmpty
          ? _googleProfileLink.locationAddress.trim()
          : _addressController.text.trim(),
      latitude: _selectedLatitude ?? 0,
      longitude: _selectedLongitude ?? 0,
      primaryType: '',
      types: const <String>[],
      rating: 0,
      userRatingCount: 0,
      websiteUrl: _googleProfileLink.website.trim().isNotEmpty
          ? _googleProfileLink.website.trim()
          : _verificationWebsite.trim(),
    );

    setState(() => _connectingGoogleProfile = true);
    _startVerificationProgress(
      title: 'Business-Identität wird geprüft',
      subtitle:
          'Bitte Fenster offen lassen. Wir prüfen Google-Zugriff und den exakten Standortabgleich.',
      steps: const <_VerificationProgressStep>[
        _VerificationProgressStep(
          title: 'Google-Konto absichern',
          subtitle: 'Die aktuelle Google-Identität wird bestätigt.',
        ),
        _VerificationProgressStep(
          title: 'Standorte mit Zugriff laden',
          subtitle: 'Wir laden nur Business-Standorte mit Verwaltungszugriff.',
        ),
        _VerificationProgressStep(
          title: 'Ausgewählten Ort exakt abgleichen',
          subtitle: 'Die Place-ID muss serverseitig exakt passen.',
        ),
        _VerificationProgressStep(
          title: 'Business-Zugang übernehmen',
          subtitle: 'Bei Erfolg wird die bestätigte Business-Identität gebunden.',
        ),
      ],
    );
    try {
      final service = ref.read(googleBusinessProfileServiceProvider);
      await service.authorizeGoogleBusinessIdentity();
      final links = await service.fetchMatchingOwnedOrManagedLocations(
        expectedPlace,
      );
      _setVerificationProgressStage(
        1,
        subtitle:
            'Google-Zugriff ist da. Jetzt gleichen wir mögliche Business-Standorte mit deiner Auswahl ab.',
      );
      if (!mounted) {
        return;
      }

      if (links.isEmpty) {
        throw Exception(
          'Dieses Google-Konto hat keinen bestätigten Google-Business-Zugriff auf den vorher ausgewählten Standort.',
        );
      }

      final selectedLink = links.length == 1
          ? links.first
          : await _pickGoogleProfileLink(links);
      if (selectedLink == null || !mounted) {
        _clearVerificationProgress();
        return;
      }

      _setVerificationProgressStage(
        2,
        subtitle:
            'Standort gewählt. Die exakte Place-ID wird jetzt serverseitig bestätigt.',
      );
      final verifiedLink = await service.verifySelectedLocationAccess(
        selectedLink,
      );
      if (!mounted) {
        return;
      }

      if (verifiedLink.placeId.trim() != expectedPlaceId) {
        throw Exception(
          'Der verknüpfte Google-Business-Standort passt nicht zum vorher ausgewählten Ort.',
        );
      }

      setState(() {
        _verificationMethod = BusinessVerificationMethod.googleBusinessProfile;
        _googleProfileLink = verifiedLink;
        _verificationPlaceId = verifiedLink.placeId.trim();
        if (verifiedLink.website.trim().isNotEmpty) {
          _verificationWebsite = verifiedLink.website.trim();
        }
      });
      _applyGoogleProfileLink(verifiedLink);
      _clearVerificationProgress();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_looksLikeGoogleBusinessLimit(error.toString())) {
        final canTryCompanyIdentity =
            expectedPlace.websiteUrl?.trim().isNotEmpty ?? false;
        if (canTryCompanyIdentity) {
          try {
            _setVerificationProgressStage(
              3,
              subtitle:
                  'Google ist ausgelastet. Wir prüfen jetzt sichere Unternehmenssignale für genau diesen Standort.',
            );
            final identityLink = await ref
                .read(googleBusinessProfileServiceProvider)
                .verifyCompanyIdentityForPlace(expectedPlace);
            if (!mounted) {
              return;
            }

            setState(() {
              _verificationMethod = BusinessVerificationMethod.googleBusinessProfile;
              _googleProfileLink = identityLink;
              _verificationPlaceId = identityLink.placeId.trim();
              if (identityLink.website.trim().isNotEmpty) {
                _verificationWebsite = identityLink.website.trim();
              }
            });
            _applyGoogleProfileLink(identityLink);
            _showError('Unternehmenszugang wurde automatisch bestätigt.');
            _clearVerificationProgress();
            return;
          } on Object catch (identityError) {
            if (!mounted) {
              return;
            }
            final identityMessage = _friendlyBusinessConnectError(
              identityError,
              fallback:
                  'Google Business ist gerade ausgelastet. Nutze jetzt die sichere Dokumentenprüfung mit offiziellen Unterlagen - ohne zusätzliches Google-Popup.',
            );
            setState(_syncPreferredVerificationMethod);
            _showError(identityMessage);
            _clearVerificationProgress();
            return;
          }
        }
        setState(_syncPreferredVerificationMethod);
        _showError(
          'Google Business ist gerade ausgelastet. Nutze jetzt die sichere Dokumentenprüfung mit offiziellen Unterlagen - ohne zusätzliches Google-Popup.',
        );
        _clearVerificationProgress();
        return;
      }
      final message = _friendlyBusinessConnectError(
        error,
        fallback:
            'Google Business konnte für diesen Standort gerade nicht bestätigt werden. Bitte versuche es erneut.',
      );
      setState(_syncPreferredVerificationMethod);
      _showError(message);
      _clearVerificationProgress();
    } finally {
      if (mounted) {
        setState(() => _connectingGoogleProfile = false);
      }
    }
  }

  Future<void> _verifyBusinessEvidenceDocument() async {
    if (_verifyingDocumentEvidence) {
      return;
    }
    if (!_ensureBusinessFlowAllowed()) {
      return;
    }

    final expectedPlaceId = _verificationPlaceId.trim();
    if (expectedPlaceId.isEmpty) {
      _showError(
        'Für diesen Schritt fehlt der vorher ausgewählte Google-Standort. Bitte starte die Business-Registrierung erneut über die Standortsuche.',
      );
      return;
    }

    final expectedPlace = NearbyPlace(
      id: expectedPlaceId,
      name: _googleProfileLink.locationDisplayName.trim().isNotEmpty
          ? _googleProfileLink.locationDisplayName.trim()
          : _nameController.text.trim(),
      address: _googleProfileLink.locationAddress.trim().isNotEmpty
          ? _googleProfileLink.locationAddress.trim()
          : _addressController.text.trim(),
      latitude: _selectedLatitude ?? 0,
      longitude: _selectedLongitude ?? 0,
      primaryType: '',
      types: const <String>[],
      rating: 0,
      userRatingCount: 0,
      websiteUrl: _verificationWebsite.trim(),
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showError('Das ausgewählte Dokument konnte nicht gelesen werden.');
      return;
    }

    setState(() {
      _verifyingDocumentEvidence = true;
      _documentEvidenceName = file.name;
    });
    _startVerificationProgress(
      title: 'Offizielle Unterlagen werden geprüft',
      subtitle:
          'Bitte Fenster offen lassen. Wir übertragen die Unterlage sicher und prüfen sie danach serverseitig.',
      steps: const <_VerificationProgressStep>[
        _VerificationProgressStep(
          title: 'Unterlage sicher übertragen',
          subtitle: 'Das Dokument wird direkt an die geschützte Prüfstrecke gesendet.',
        ),
        _VerificationProgressStep(
          title: 'OCR und KI lesen die Unterlage',
          subtitle: 'Es werden nur belastbare Firmen- und Inhaberdaten extrahiert.',
        ),
        _VerificationProgressStep(
          title: 'Standort und Inhaber abgleichen',
          subtitle: 'Name, Adresse und vertretungsberechtigte Person müssen passen.',
        ),
        _VerificationProgressStep(
          title: 'Amtliche Nachweise bestätigen',
          subtitle: 'Gewerbenachweis, Register- oder USt.-Signal werden serverseitig bewertet.',
        ),
      ],
    );

    try {
      _setVerificationProgressStage(
        1,
        subtitle:
            'Unterlage ist sicher angekommen. Jetzt liest die KI den Gewerbe- und Inhaberbezug aus.',
      );
      final claimantName =
          (ref.read(authUserProvider)?.displayName ?? '').trim();
      final claimedBusinessEmail =
          (ref.read(authUserProvider)?.email ?? _emailController.text)
              .trim()
              .toLowerCase();
      _setVerificationProgressStage(
        2,
        subtitle:
            'Wir gleichen jetzt Inhaber, Standort und amtliche Referenzen serverseitig ab.',
      );
      final link = await ref
          .read(googleBusinessProfileServiceProvider)
          .verifyBusinessEvidenceDocument(
            place: expectedPlace,
            fileName: file.name,
            mimeType: _businessEvidenceMimeType(file.name, bytes),
            claimantName: claimantName,
            claimedBusinessEmail: claimedBusinessEmail,
            fileBytes: bytes,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationMethod = BusinessVerificationMethod.googleBusinessProfile;
        _googleProfileLink = link;
      });
      _applyGoogleProfileLink(link);
      _clearVerificationProgress();
      _showError('Offizielle Unterlagen wurden serverseitig bestätigt.');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyBusinessConnectError(
        error,
        fallback:
            'Die Register- und Dokumentenprüfung konnte gerade nicht abgeschlossen werden.',
      );
      setState(_syncPreferredVerificationMethod);
      _showError(message);
      _clearVerificationProgress();
    } finally {
      if (mounted) {
        setState(() => _verifyingDocumentEvidence = false);
      }
    }
  }

  Future<BusinessGoogleProfileLink?> _pickGoogleProfileLink(
    List<BusinessGoogleProfileLink> links,
  ) async {
    if (links.isEmpty) {
      return null;
    }
    if (links.length == 1) {
      return links.first;
    }

    return showModalBottomSheet<BusinessGoogleProfileLink>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: links.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Standort auswählen',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Wähle den Standort, den du in sparGO verwalten willst.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final link = links[index - 1];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  onTap: () => Navigator.of(context).pop(link),
                  child: Ink(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          link.locationDisplayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          link.locationAddress.isEmpty
                              ? link.locationCity
                              : link.locationAddress,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${link.roleLabel} · ${link.googleUserEmail}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _applyGoogleProfileLink(BusinessGoogleProfileLink link) {
    if (_nameController.text.trim().isEmpty &&
        link.locationDisplayName.isNotEmpty) {
      _nameController.text = link.locationDisplayName;
    }
    if (link.website.trim().isNotEmpty) {
      _websiteController.text = link.website.trim();
    }
    _verificationPlaceId = link.placeId.trim();
    if (link.website.trim().isNotEmpty) {
      _verificationWebsite = link.website.trim();
    }
    if (_phoneController.text.trim().isEmpty && link.phone.trim().isNotEmpty) {
      _phoneController.text = link.phone.trim();
    }
    if (_cityController.text.trim().isEmpty &&
        link.locationCity.trim().isNotEmpty) {
      _cityController.text = link.locationCity.trim();
    }
    if (_districtController.text.trim().isEmpty) {
      _districtController.text = 'In deiner Nähe';
    }
    if (_addressController.text.trim().isEmpty &&
        link.locationAddress.trim().isNotEmpty) {
      _addressController.text = link.locationAddress.trim();
    }
    if (_legalNameController.text.trim().isEmpty &&
        link.locationDisplayName.trim().isNotEmpty) {
      _legalNameController.text = link.locationDisplayName.trim();
    }
    if (_claimedByRoleController.text.trim().isEmpty ||
        _claimedByRoleController.text.trim() == 'Inhaberin / Inhaber') {
      _claimedByRoleController.text = link.roleLabel;
    }
    if (link.googleUserEmail.trim().isNotEmpty) {
      _emailController.text = link.googleUserEmail.trim();
    }
  }

  void _syncPreferredVerificationMethod() {
    if (_googleProfileLink.grantsDashboardAccess) {
      _verificationMethod = BusinessVerificationMethod.googleBusinessProfile;
      _ownershipConfirmed = true;
      return;
    }
    _verificationMethod = BusinessVerificationMethod.googleBusinessProfile;
    _ownershipConfirmed = false;
  }

  Future<void> _saveBusinessProfile() async {
    final authUser = ref.read(authUserProvider);
    final business = ref.read(ownedBusinessProvider);
    final user = ref.read(currentUserProvider);
    if (!_ensureBusinessFlowAllowed()) {
      return;
    }
    final authEmail = (authUser?.email ?? '').trim();
    final contactEmail = _googleProfileLink.googleUserEmail.trim().isNotEmpty
        ? _googleProfileLink.googleUserEmail.trim()
        : (authEmail.isNotEmpty ? authEmail : _emailController.text.trim());
    final website = _websiteController.text.trim().isEmpty
        ? (_verificationWebsite.trim().isEmpty
              ? _googleProfileLink.website.trim()
              : _verificationWebsite.trim())
        : _websiteController.text.trim();
    final selectedVerificationMethod =
        BusinessVerificationMethod.googleBusinessProfile;
    final resolvedOwnershipConfirmed =
        _googleProfileLink.grantsDashboardAccess;

    final name = _nameController.text.trim().isEmpty
        ? (_googleProfileLink.locationDisplayName.trim().isNotEmpty
              ? _googleProfileLink.locationDisplayName.trim()
              : _inferBusinessNameFromWebsite(_websiteController.text))
        : _nameController.text.trim();
    final city = _cityController.text.trim().isEmpty
        ? (_googleProfileLink.locationCity.trim().isNotEmpty
              ? _googleProfileLink.locationCity.trim()
              : (user.city == 'Deutschlandweit'
                    ? 'Deutschlandweit'
                    : user.city.trim()))
        : _cityController.text.trim();
    final district = _districtController.text.trim().isEmpty
        ? (user.district == 'Dein Viertel'
              ? 'Deine Nähe'
              : user.district.trim())
        : _districtController.text.trim();
    final address = _addressController.text.trim().isEmpty
        ? (_googleProfileLink.locationAddress.trim().isNotEmpty
              ? _googleProfileLink.locationAddress.trim()
              : 'Adresse folgt')
        : _addressController.text.trim();
    final tagline = _taglineController.text.trim().isEmpty
        ? 'Coupons und Stories direkt von $name'
        : _taglineController.text.trim();
    final shortDescription = _shortDescriptionController.text.trim().isEmpty
        ? 'Lokale Vorteile, Tagesdeals und direkte Einlösungen von $name.'
        : _shortDescriptionController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? shortDescription
        : _descriptionController.text.trim();
    final phone = _phoneController.text.trim().isEmpty
        ? _googleProfileLink.phone.trim()
        : _phoneController.text.trim();
    final legalName = _legalNameController.text.trim().isEmpty
        ? name
        : _legalNameController.text.trim();
    final claimedByName = _claimedByNameController.text.trim().isEmpty
        ? user.name
        : _claimedByNameController.text.trim();
    final claimedByRole = _claimedByRoleController.text.trim().isEmpty
        ? switch (selectedVerificationMethod) {
            BusinessVerificationMethod.googleBusinessProfile =>
              _googleProfileLink.roleLabel,
            BusinessVerificationMethod.manualReview => 'Business-Kontakt',
            BusinessVerificationMethod.emailDomain => 'Business-Kontakt',
          }
        : _claimedByRoleController.text.trim();
    final imprintInfo = _imprintController.text.trim().isEmpty
        ? _buildImprint(
            legalName: legalName,
            address: address,
            city: city,
            contactEmail: contactEmail,
            website: website,
          )
        : _imprintController.text.trim();

    if (name.isEmpty || contactEmail.isEmpty) {
      _showError(
        'Bitte mindestens Business-Name und eine kontaktierbare E-Mail ausfüllen.',
      );
      return;
    }
    if (authUser == null) {
      _showError(
        'Dein Login ist nicht mehr aktiv. Bitte melde dich erneut an.',
      );
      return;
    }
    if (selectedVerificationMethod ==
        BusinessVerificationMethod.googleBusinessProfile) {
      if (!_googleProfileLink.isLinked || !_googleProfileLink.grantsDashboardAccess) {
        _showError(
          'Bitte verbinde zuerst dein Google Business Profil. Ohne verifizierten Google-Standort kann dieses Business nicht gespeichert werden.',
        );
        return;
      }
    }
    if (user.accountType != AccountType.business) {
      _showError(
        'Nur ein echtes Business-Konto darf ein Business speichern. Bitte melde dich mit einem separaten Business-Zugang an.',
      );
      return;
    }
    if (authUser.uid.trim().isNotEmpty && authUser.uid.trim() != user.id.trim()) {
      _showError(
        'Deine Business-Session ist nicht sauber synchronisiert. Bitte neu anmelden und danach erneut versuchen.',
      );
      return;
    }
    ref
        .read(ownedBusinessDraftProvider.notifier)
        .save(
          business: business,
          category: _selectedCategory,
          name: name,
          tagline: tagline,
          description: description,
          shortDescription: shortDescription,
          website: website,
          phone: phone,
          contactEmail: contactEmail,
          legalEntityName: legalName,
          imprintInfo: imprintInfo,
          address: address,
          city: city,
          district: district,
          claimedByName: claimedByName,
          claimedByRole: claimedByRole,
          ownershipConfirmed: resolvedOwnershipConfirmed,
          verificationPlaceId: _verificationPlaceId,
          verificationWebsite: website,
          verificationMethod: selectedVerificationMethod,
          googleProfileLink: _googleProfileLink,
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
            name: name,
            tagline: tagline,
            description: description,
            shortDescription: shortDescription,
            website: website,
            phone: phone,
            contactEmail: contactEmail,
            legalEntityName: legalName,
            imprintInfo: imprintInfo,
            address: address,
            city: city,
            district: district,
            claimedByName: claimedByName,
            claimedByRole: claimedByRole,
            ownershipConfirmed: resolvedOwnershipConfirmed,
            verificationPlaceId: _verificationPlaceId,
            verificationWebsite: website,
            latitude: _selectedLatitude,
            longitude: _selectedLongitude,
            verificationMethod: selectedVerificationMethod,
            googleProfileLink: _googleProfileLink,
          );

      ref.read(ownedBusinessDraftProvider.notifier).clear();
      ref
          .read(sessionControllerProvider.notifier)
          .finishBusinessOnboarding(businessId: businessId);

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.businessDashboard, (route) => false);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Business-Profil konnte nicht gespeichert werden: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _buildImprint({
    required String legalName,
    required String address,
    required String city,
    required String contactEmail,
    required String website,
  }) {
    final parts = <String>[
      legalName,
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
      if (contactEmail.isNotEmpty) 'Kontakt: $contactEmail',
      if (website.isNotEmpty) 'Web: $website',
    ];
    return parts.join(' | ');
  }

  String _inferBusinessNameFromWebsite(String rawWebsite) {
    final normalizedWebsite = rawWebsite.trim();
    if (normalizedWebsite.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(
      normalizedWebsite.startsWith('http://') ||
              normalizedWebsite.startsWith('https://')
          ? normalizedWebsite
          : 'https://$normalizedWebsite',
    );
    final host = uri?.host.trim().toLowerCase() ?? '';
    if (host.isEmpty) {
      return '';
    }
    final cleanedHost = host.startsWith('www.') ? host.substring(4) : host;
    final namePart = cleanedHost.split('.').first;
    if (namePart.isEmpty) {
      return '';
    }
    return namePart
        .split(RegExp(r'[-_]+'))
        .where((segment) => segment.trim().isNotEmpty)
        .map(
          (segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  bool _ensureBusinessFlowAllowed() {
    final authUser = ref.read(authUserProvider);
    final session = ref.read(sessionControllerProvider);
    final consumerSession =
        authUser != null &&
        !authUser.isAnonymous &&
        session.isAuthenticated &&
        session.user.accountType == AccountType.user;
    if (!consumerSession) {
      return true;
    }
    _showError(
      'Du bist gerade mit einem normalen Nutzerkonto angemeldet. Für Business-Setup musst du dich zuerst ausloggen und danach mit einem separaten Business-Zugang weitermachen.',
    );
    return false;
  }

  Future<void> _signOutConsumerSession() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
      _emailController.clear();
      if (!mounted) {
        return;
      }
      _showError(
        'Nutzerkonto wurde abgemeldet. Du kannst jetzt mit einem Business-Zugang neu starten.',
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Abmelden fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_sanitizeBusinessMessage(message))));
  }

  String _friendlyBusinessConnectError(
    Object error, {
    required String fallback,
  }) {
    final message = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('Google Business Verbindung fehlgeschlagen: ', '')
        .trim();
    if (message.isEmpty) {
      return fallback;
    }
    if (_looksLikeGoogleBusinessLimit(message)) {
      return 'Google Business ist gerade ausgelastet. Nutze jetzt die sichere Dokumentenprüfung mit offiziellen Unterlagen - ohne zusätzliches Google-Popup.';
    }
    return message;
  }

  String _sanitizeBusinessMessage(String message) {
    if (_looksLikeGoogleBusinessLimit(message)) {
      return 'Google Business ist gerade ausgelastet. Nutze jetzt die sichere Dokumentenprüfung mit offiziellen Unterlagen - ohne zusätzliches Google-Popup.';
    }
    return message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('Google Business Verbindung fehlgeschlagen: ', '')
        .trim();
  }

  bool _looksLikeGoogleBusinessLimit(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('quota') ||
        normalized.contains('limit') ||
        normalized.contains('requests per minute') ||
        normalized.contains('resource_exhausted');
  }

  String _businessEvidenceMimeType(String fileName, Uint8List bytes) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }
}

class _SetupHeroCard extends StatelessWidget {
  const _SetupHeroCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF241619),
            Color(0xFF5D1C2B),
            AppColors.primary,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -24,
            top: -18,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  'Business Studio',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupProgressRail extends StatelessWidget {
  const _SetupProgressRail({
    required this.verificationMethod,
    required this.canUseEmailDomainVerification,
    required this.verifiedEmail,
    required this.googleProfileLink,
  });

  final BusinessVerificationMethod verificationMethod;
  final bool canUseEmailDomainVerification;
  final bool verifiedEmail;
  final BusinessGoogleProfileLink googleProfileLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const verificationTitle = 'Business-Identität';
    final verificationText = googleProfileLink.isLinked
        ? '${googleProfileLink.locationDisplayName} · ${googleProfileLink.roleLabel}'
        : 'Standort noch nicht serverseitig bestätigt.';
    final resolvedVerificationTitle =
        verificationMethod == BusinessVerificationMethod.manualReview
        ? 'Manuelle Prüfung'
        : verificationTitle;
    final resolvedVerificationText =
        verificationMethod == BusinessVerificationMethod.manualReview
        ? 'Studio kann vorbereitet werden. Freigabe folgt separat.'
        : verificationText;
    final verificationActive =
        verificationMethod == BusinessVerificationMethod.manualReview
        ? true
        : googleProfileLink.isLinked;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Setup in 3 Schritten',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _SetupRailItem(
            index: '01',
            title: 'Zugang aktiv',
            subtitle: 'Business-Konto steht bereits.',
          ),
          const SizedBox(height: AppSpacing.md),
          _SetupRailItem(
            index: '02',
            title: resolvedVerificationTitle,
            subtitle: resolvedVerificationText,
            active: verificationActive,
          ),
          const SizedBox(height: AppSpacing.md),
          const _SetupRailItem(
            index: '03',
            title: 'Profil live schalten',
            subtitle: 'Danach geht es direkt ins Dashboard.',
          ),
        ],
      ),
    );
  }
}

class _SetupRailItem extends StatelessWidget {
  const _SetupRailItem({
    required this.index,
    required this.title,
    required this.subtitle,
    this.active = true,
  });

  final String index;
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: theme.textTheme.labelLarge?.copyWith(
              color: active ? AppColors.primary : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationMethodCard extends StatelessWidget {
  const _VerificationMethodCard({
    required this.verificationMethod,
    required this.authEmail,
    required this.verificationWebsite,
    required this.canUseEmailDomainVerification,
    required this.googleProfileLink,
    required this.connectingGoogleProfile,
    required this.verifyingDocumentEvidence,
    required this.documentEvidenceName,
    required this.verificationProgressTitle,
    required this.verificationProgressSubtitle,
    required this.verificationProgressSteps,
    required this.verificationProgressIndex,
    required this.onConnectGoogle,
    required this.onVerifyDocuments,
  });

  final BusinessVerificationMethod verificationMethod;
  final String authEmail;
  final String verificationWebsite;
  final bool canUseEmailDomainVerification;
  final BusinessGoogleProfileLink googleProfileLink;
  final bool connectingGoogleProfile;
  final bool verifyingDocumentEvidence;
  final String documentEvidenceName;
  final String verificationProgressTitle;
  final String verificationProgressSubtitle;
  final List<_VerificationProgressStep> verificationProgressSteps;
  final int verificationProgressIndex;
  final VoidCallback onConnectGoogle;
  final VoidCallback onVerifyDocuments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected =
        verificationMethod == BusinessVerificationMethod.googleBusinessProfile;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Business Freigabe',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Zuerst versuchen wir die sichere Freischaltung über Google Business. Kleine Läden ohne Website können stattdessen offizielle Unterlagen wie Gewerbeanmeldung oder Handwerkskammer-Nachweis serverseitig prüfen lassen.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: onConnectGoogle,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            child: Ink(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.28)
                      : theme.dividerColor,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.store_mall_directory_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Google Business Profil',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          googleProfileLink.isLinked
                              ? '${googleProfileLink.locationDisplayName} · ${googleProfileLink.roleLabel}'
                              : 'Nur Google-Business-Konten mit bestätigtem Verwaltungszugriff können dieses Business verbinden.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  connectingGoogleProfile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : googleProfileLink.isLinked
                      ? const Icon(
                          Icons.verified_rounded,
                          color: AppColors.primary,
                        )
                      : const Icon(
                          Icons.login_rounded,
                          color: AppColors.primary,
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: verifyingDocumentEvidence ? null : onVerifyDocuments,
              icon: verifyingDocumentEvidence
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_present_rounded),
              label: Text(
                documentEvidenceName.isEmpty
                    ? 'Offizielle Unterlagen hochladen'
                    : 'Unterlage prüfen: $documentEvidenceName',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Akzeptiert werden nur offizielle Unterlagen wie Gewerbeanmeldung, Gewerbeschein, Handwerkskammer-Nachweis, Handelsregisterauszug oder USt.-Nachweis. Auch kleine Läden ohne Website können so sicher geprüft werden - direkt über deine sparGO-Session.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (authEmail.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Aktives Business-Login: $authEmail',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (verificationProgressSteps.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _VerificationProgressCard(
              title: verificationProgressTitle,
              subtitle: verificationProgressSubtitle,
              steps: verificationProgressSteps,
              activeIndex: verificationProgressIndex,
            ),
          ],
        ],
      ),
    );
  }
}

String _businessWebsiteDomainLabel(String website) {
  final trimmed = website.trim();
  if (trimmed.isEmpty) {
    return 'keine Domain erkannt';
  }
  final uri = Uri.tryParse(
    trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed',
  );
  final host = uri?.host.trim().toLowerCase() ?? trimmed.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

class _VerificationProgressCard extends StatelessWidget {
  const _VerificationProgressCard({
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.activeIndex,
  });

  final String title;
  final String subtitle;
  final List<_VerificationProgressStep> steps;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < steps.length; index++) ...<Widget>[
            _VerificationProgressRow(
              step: steps[index],
              completed: activeIndex > index,
              active: activeIndex == index,
            ),
            if (index < steps.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _VerificationProgressRow extends StatelessWidget {
  const _VerificationProgressRow({
    required this.step,
    required this.completed,
    required this.active,
  });

  final _VerificationProgressStep step;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget leading;
    if (completed) {
      leading = const Icon(Icons.check_circle_rounded, color: AppColors.primary);
    } else if (active) {
      leading = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    } else {
      leading = Icon(
        Icons.radio_button_unchecked_rounded,
        color: theme.colorScheme.outline,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 22, height: 22, child: Center(child: leading)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                step.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard({
    required this.authEmail,
    required this.verifiedEmail,
    required this.sending,
    required this.refreshing,
    required this.onSend,
    required this.onRefresh,
  });

  final String authEmail;
  final bool verifiedEmail;
  final bool sending;
  final bool refreshing;
  final VoidCallback onSend;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = verifiedEmail ? const Color(0xFF1F8B4D) : AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  verifiedEmail
                      ? Icons.verified_rounded
                      : Icons.mail_outline_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      verifiedEmail
                          ? 'Business-E-Mail bestätigt'
                          : 'Business-E-Mail bestätigen',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      authEmail.isEmpty ? 'Keine E-Mail gefunden' : authEmail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            verifiedEmail
                ? 'Perfekt. Deine Business-Identität ist bestätigt. Sobald die passende serverseitige Standort-Prüfung abgeschlossen ist, kann sparGO dein Studio freischalten.'
                : 'Einmal bestätigen, danach bleibt diese E-Mail sauber an dein Business-Login gebunden.',
            style: theme.textTheme.bodyMedium,
          ),
          if (!verifiedEmail) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: sending ? null : onSend,
                    child: Text(sending ? 'Sendet...' : 'Link senden'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: refreshing ? null : onRefresh,
                    child: Text(
                      refreshing ? 'Prüft...' : 'Status aktualisieren',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _BusinessOnboardingBackdrop extends StatelessWidget {
  const _BusinessOnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFF7F8FB), Color(0xFFF1F3F8)],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: -120,
            top: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: -100,
            bottom: -110,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE8EEF7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessOnboardingHeroFeature extends StatelessWidget {
  const _BusinessOnboardingHeroFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: compact ? 20 : 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              icon,
              size: compact ? 18 : 20,
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(width: compact ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessOnboardingVerificationHint extends StatelessWidget {
  const _BusinessOnboardingVerificationHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F8),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: const Color(0xFFE8DCE1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Google-verifiziertes Business',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Dieser Flow bleibt strikt: ohne bestätigten Google-Business-Zugriff für genau diesen Standort wird kein Studio freigeschaltet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFF46B95A),
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessOnboardingLanguagePill extends StatelessWidget {
  const _BusinessOnboardingLanguagePill({
    required this.languageCode,
    required this.onTap,
  });

  final String languageCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7D7DD)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.language_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                languageCode.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessOnboardingLanguageSheet extends StatelessWidget {
  const _BusinessOnboardingLanguageSheet({required this.selectedCode});

  final String selectedCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = <(String, String)>[
      ('de', 'Deutsch'),
      ('en', 'English'),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Sprache',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final option in options) ...<Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  option.$1 == selectedCode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: option.$1 == selectedCode
                      ? AppColors.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(option.$2),
                onTap: () => Navigator.of(context).pop(option.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _domainLabel(String website) {
    final trimmed = website.trim();
    if (trimmed.isEmpty) {
      return 'keine Domain erkannt';
    }
    final uri = Uri.tryParse(
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'https://$trimmed',
    );
    final host = uri?.host.trim().toLowerCase() ?? trimmed.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
