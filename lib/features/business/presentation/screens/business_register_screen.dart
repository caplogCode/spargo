// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/nearby_place_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_language_provider.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../theme/app_colors.dart';

enum _BusinessEntryMode { login, register }

class _VerificationProgressStep {
  const _VerificationProgressStep({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

class BusinessRegisterScreen extends ConsumerStatefulWidget {
  const BusinessRegisterScreen({super.key});

  @override
  ConsumerState<BusinessRegisterScreen> createState() =>
      _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState
    extends ConsumerState<BusinessRegisterScreen> {
  final _placeSearchController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _websiteController = TextEditingController();
  final _claimantNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _BusinessEntryMode _mode = _BusinessEntryMode.login;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitting = false;
  bool _sendingReset = false;
  bool _connectingGoogleProfile = false;
  bool _verifyingDocumentEvidence = false;
  bool _searchingPlaces = false;
  bool _rememberMe = true;
  String? _errorText;
  String _documentEvidenceName = '';
  NearbyPlace? _selectedPlace;
  List<NearbyPlace> _placeResults = const <NearbyPlace>[];
  BusinessGoogleProfileLink _googleProfileLink =
      const BusinessGoogleProfileLink();
  String _verificationPlaceId = '';
  String _verificationWebsite = '';
  String _verificationProgressTitle = '';
  String _verificationProgressSubtitle = '';
  List<_VerificationProgressStep> _verificationProgressSteps =
      const <_VerificationProgressStep>[];
  int _verificationProgressIndex = -1;
  Timer? _placeSearchDebounce;
  Timer? _verificationProgressTimer;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    final authUser = ref.read(authUserProvider);
    final authEmail =
        authUser != null &&
            !authUser.isAnonymous &&
            session.isAuthenticated &&
            session.user.accountType == AccountType.business
        ? (authUser.email ?? '')
        : '';
    final authDisplayName =
        authUser != null &&
            !authUser.isAnonymous &&
            session.isAuthenticated &&
            session.user.accountType == AccountType.business
        ? (authUser.displayName ?? '')
        : '';
    if (authEmail.trim().isNotEmpty) {
      _emailController.text = authEmail.trim();
    }
    if (authDisplayName.trim().isNotEmpty) {
      _claimantNameController.text = authDisplayName.trim();
    }
  }

  @override
  void dispose() {
    _placeSearchDebounce?.cancel();
    _verificationProgressTimer?.cancel();
    _placeSearchController.dispose();
    _businessNameController.dispose();
    _websiteController.dispose();
    _claimantNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    final clampedIndex = math.max(
      0,
      math.min(index, _verificationProgressSteps.length - 1),
    );
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
    final mediaQuery = MediaQuery.of(context);
    final session = ref.watch(sessionControllerProvider);
    final authUser = ref.watch(authUserProvider);
    final hasConsumerSession =
        authUser != null &&
        !authUser.isAnonymous &&
        session.isAuthenticated &&
        session.user.accountType == AccountType.user;
    final trustedBusinessEmail =
        authUser != null &&
            !authUser.isAnonymous &&
            session.isAuthenticated &&
            session.user.accountType == AccountType.business
        ? (authUser.email ?? '').trim().toLowerCase()
        : (_googleProfileLink.grantsDashboardAccess
              ? _googleProfileLink.googleUserEmail.trim().toLowerCase()
              : '');

    if (trustedBusinessEmail.isNotEmpty &&
        _emailController.text.trim().toLowerCase() != trustedBusinessEmail) {
      _emailController.value = _emailController.value.copyWith(
        text: trustedBusinessEmail,
        selection: TextSelection.collapsed(offset: trustedBusinessEmail.length),
        composing: TextRange.empty,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _BusinessBackdrop()),
          SafeArea(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _buildBusinessShell(
                    theme,
                    constraints,
                    hasConsumerSession: hasConsumerSession,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessShell(
    ThemeData theme,
    BoxConstraints constraints, {
    required bool hasConsumerSession,
  }) {
    final isPhone = constraints.maxWidth < 860;
    final compactDesktop =
        !isPhone &&
        (constraints.maxHeight < 980 || constraints.maxWidth < 1400);
    final shellCompact = isPhone || compactDesktop;
    final horizontalPadding = isPhone ? 16.0 : (compactDesktop ? 24.0 : 32.0);
    final verticalPadding = isPhone ? 12.0 : (compactDesktop ? 18.0 : 26.0);
    final maxWidth = isPhone ? 560.0 : 1520.0;
    final minHeight = math.max(
      0.0,
      constraints.maxHeight - (verticalPadding * 2),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: isPhone
          ? SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    minHeight: minHeight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildBusinessHeroPanel(theme, compact: true),
                      const SizedBox(height: 16),
                      _buildBusinessEntryCard(
                        theme,
                        compact: true,
                        hasConsumerSession: hasConsumerSession,
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
                  minHeight: minHeight,
                  maxHeight: minHeight,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 10,
                      child: _buildBusinessHeroPanel(
                        theme,
                        compact: shellCompact,
                      ),
                    ),
                    SizedBox(width: compactDesktop ? 22 : 28),
                    Expanded(
                      flex: 11,
                      child: _buildBusinessEntryCard(
                        theme,
                        compact: shellCompact,
                        hasConsumerSession: hasConsumerSession,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBusinessHeroPanel(ThemeData theme, {required bool compact}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFBFBFE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 22 : 28),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE7EAF1)),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFF101828).withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.business_center_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Business Studio',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 22 : 28),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, heroConstraints) {
                    final shortHero = heroConstraints.maxHeight < 660;
                    final titleSize = compact ? 34.0 : (shortHero ? 42.0 : 50.0);
                    final bodySize = compact ? 15.0 : 17.0;
                    final featureGap = shortHero ? 12.0 : 16.0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Dein Business.',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: titleSize,
                              height: 0.94,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            'Verifiziert.',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: titleSize,
                              height: 0.94,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            'Verbunden.',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: titleSize,
                              height: 0.94,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: shortHero ? 14 : 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              'Verbinde dein Business mit sparGO und erreiche tausende Nutzer in deiner Nähe - einfach, schnell und sicher.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF5F6574),
                                fontSize: bodySize,
                                height: 1.5,
                              ),
                            ),
                          ),
                          SizedBox(height: shortHero ? 20 : 28),
                          _buildBusinessHeroFeatureRow(
                            theme,
                            icon: Icons.verified_user_outlined,
                            title: 'Sicher & zuverlässig',
                            subtitle: 'Verifizierte Profile für mehr Vertrauen.',
                            compact: compact,
                          ),
                          SizedBox(height: featureGap),
                          _buildBusinessHeroFeatureRow(
                            theme,
                            icon: Icons.groups_2_outlined,
                            title: 'Mehr Reichweite',
                            subtitle: 'Erreiche neue Kunden in deiner Nähe.',
                            compact: compact,
                          ),
                          SizedBox(height: featureGap),
                          _buildBusinessHeroFeatureRow(
                            theme,
                            icon: Icons.trending_up_rounded,
                            title: 'Wachstum fördern',
                            subtitle: 'Insights, Angebote und Aktionen an einem Ort.',
                            compact: compact,
                          ),
                          SizedBox(height: shortHero ? 18 : 26),
                          _buildBusinessHeroVerificationCard(
                            theme,
                            compact: compact,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessHeroFeatureRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF101828).withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
              mainAxisSize: MainAxisSize.min,
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

  Widget _buildBusinessHeroVerificationCard(
    ThemeData theme, {
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 20,
        vertical: compact ? 18 : 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFE9E1E6),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFDB2149).withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: compact ? 50 : 58,
                height: compact ? 50 : 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFDB2149).withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  size: compact ? 28 : 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              CircleAvatar(
                radius: compact ? 14 : 16,
                backgroundColor: const Color(0xFF46B95A),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 14 : 16),
          Text(
            'Google-verifiziertes Business',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Suche zuerst deinen Ort, bestätige das verifizierte Google Business Profil und lege danach deinen Studio-Zugang fest.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessShellHeader({required bool compact}) {
    return Row(
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
    );
  }

  void _setBusinessMode(_BusinessEntryMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _errorText = null;
    });
  }

  Widget _buildBusinessHeroCard(ThemeData theme, {required bool compact}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 24),
        child: LayoutBuilder(
          builder: (context, heroConstraints) {
            final titleSize = compact
                ? 38.0
                : (heroConstraints.maxWidth >= 620 ? 46.0 : 40.0);

            return Column(
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
                      avatar: const Icon(
                        Icons.business_center_outlined,
                        size: 18,
                      ),
                      label: const Text('Business Studio'),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 18 : 22),
                Text(
                  'Dein Business.',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: titleSize,
                    height: 0.98,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Verifiziert.',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: titleSize,
                    height: 0.98,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Verbunden.',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: titleSize,
                    height: 0.98,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: compact ? 14 : 16),
                Text(
                  'Verbinde dein Business mit sparGO und erreiche tausende Nutzer in deiner Nähe - einfach, schnell und sicher.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF5F6574),
                    height: 1.35,
                  ),
                ),
                SizedBox(height: compact ? 16 : 18),
                _buildBusinessBenefitTile(
                  theme,
                  icon: Icons.verified_user_outlined,
                  title: 'Sicher & zuverlässig',
                  subtitle: 'Verifizierte Profile für mehr Vertrauen.',
                ),
                const SizedBox(height: 8),
                _buildBusinessBenefitTile(
                  theme,
                  icon: Icons.groups_2_outlined,
                  title: 'Mehr Reichweite',
                  subtitle: 'Erreiche neue Kunden in deiner Nähe.',
                ),
                const SizedBox(height: 8),
                _buildBusinessBenefitTile(
                  theme,
                  icon: Icons.trending_up_rounded,
                  title: 'Wachstum fördern',
                  subtitle: 'Insights, Angebote und Aktionen an einem Ort.',
                ),
                SizedBox(height: compact ? 16 : 18),
                Card(
                  margin: EdgeInsets.zero,
                  color: theme.colorScheme.surfaceContainerLowest,
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 20 : 24),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Google-verifiziertes Business',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Suche zuerst deinen Ort, bestätige das verifizierte Google Business Profil und lege danach deinen Studio-Zugang fest.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: <Widget>[
                            CircleAvatar(
                              radius: compact ? 36 : 44,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(
                                Icons.storefront_rounded,
                                size: compact ? 34 : 42,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Positioned(
                              right: -4,
                              top: -4,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.green,
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 14),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    const Icon(
                      Icons.star_rounded,
                      size: 20,
                      color: Color(0xFF00A878),
                    ),
                    Text(
                      'Trustpilot',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '4.8',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Basierend auf 1.200+ Bewertungen',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBusinessBenefitTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildBusinessEntryCard(
    ThemeData theme, {
    required bool compact,
    required bool hasConsumerSession,
  }) {
    final title = hasConsumerSession
        ? 'Business-Zugang absichern'
        : _mode == _BusinessEntryMode.login
        ? 'Willkommen zurück'
        : 'Business registrieren';
    final detail = hasConsumerSession
        ? 'Ein Nutzerkonto darf kein Business übernehmen oder neu anlegen.'
        : _mode == _BusinessEntryMode.login
        ? 'Melde dich mit deinem Studio-Zugang an und arbeite direkt weiter.'
        : 'Standort wählen, Identität bestätigen und danach den Studio-Zugang festlegen.';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFDFDFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 20 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4F6),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFF2D7E0),
                                ),
                              ),
                              child: Text(
                                hasConsumerSession
                                    ? 'Business-Sicherheit'
                                    : _mode == _BusinessEntryMode.login
                                    ? 'Studio Login'
                                    : 'Studio Registrierung',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!hasConsumerSession)
                              Text(
                                _mode == _BusinessEntryMode.login
                                    ? 'Für bestehende Business-Zugänge'
                                    : 'Neuen Business-Zugang einrichten',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 14 : 16),
                        Text(
                          title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            fontSize: compact ? 30 : 34,
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Text(
                            detail,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                              fontSize: compact ? 15.5 : 16.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE7EAF1)),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFF101828).withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _showLanguageSheet,
                      icon: const Icon(Icons.language_rounded, size: 18),
                      label: Text(
                        ref
                            .watch(appLanguageControllerProvider)
                            .languageCode
                            .toUpperCase(),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 18 : 22),
              if (!hasConsumerSession) ...<Widget>[
                _buildModeSwitch(theme),
                SizedBox(height: compact ? 14 : 16),
              ],
              Expanded(
                child: hasConsumerSession
                    ? _buildConsumerSessionBlockedCard(theme, compact: compact)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: SingleChildScrollView(
                          key: ValueKey<String>(_mode.name),
                          child: _mode == _BusinessEntryMode.login
                              ? _buildNativeBusinessLogin(
                                  theme,
                                  compact: compact,
                                )
                              : _buildNativeBusinessRegister(
                                  theme,
                                  compact: compact,
                                ),
                        ),
                      ),
              ),
            ],
          ),
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
                  ? 'Dieses sparGO-Nutzerkonto darf kein Business übernehmen oder registrieren. Bitte melde dich zuerst aus und starte danach mit einem separaten Business-Zugang neu.'
                  : 'Du bist gerade mit $authEmail als Nutzerkonto angemeldet. Dieses Konto darf kein Business übernehmen oder registrieren. Bitte melde dich zuerst aus und starte danach mit einem separaten Business-Zugang neu.',
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

  Widget _buildNativeBusinessLogin(ThemeData theme, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSectionIntro(
          theme,
          title: 'Direkt ins Studio',
          detail:
              'Melde dich mit deiner Business-Mail an. Angebote, Insights und Standorte bleiben danach sofort verfügbar.',
        ),
        const SizedBox(height: 14),
        _buildBusinessSectionCard(
          theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Studio-Zugang',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              _buildNativeTextField(
                label: 'Business-E-Mail',
                hintText: 'deine@business.de',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildNativeTextField(
                label: 'Passwort',
                hintText: 'Dein Passwort',
                controller: _passwordController,
                obscureText: _obscureLoginPassword,
                prefixIcon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  onPressed: () => setState(
                    () => _obscureLoginPassword = !_obscureLoginPassword,
                  ),
                  icon: Icon(
                    _obscureLoginPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 12,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Checkbox.adaptive(
                        value: _rememberMe,
                        onChanged: (value) =>
                            setState(() => _rememberMe = value ?? false),
                      ),
                      const Text('Angemeldet bleiben'),
                    ],
                  ),
                  TextButton(
                    onPressed: _sendingReset ? null : _handleForgotPassword,
                    child: Text(
                      _sendingReset
                          ? 'Link wird gesendet...'
                          : 'Passwort vergessen?',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_errorText != null && _errorText!.trim().isNotEmpty) ...<Widget>[
          _buildInlineError(theme, _errorText!),
        ],
        SizedBox(height: compact ? 18 : 20),
        _buildBusinessSectionCard(
          theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Alternative Anmeldung',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'oder',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _submitBusinessGoogleLogin,
                  icon: const _GoogleMark(size: 18),
                  label: const Text('Mit Google fortfahren'),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Einloggen'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => _setBusinessMode(_BusinessEntryMode.register),
            child: const Text('Noch kein Business-Konto? Registrieren'),
          ),
        ),
      ],
    );
  }

  Widget _buildNativeBusinessRegister(
    ThemeData theme, {
    required bool compact,
  }) {
    final session = ref.read(sessionControllerProvider);
    final authUser = ref.read(authUserProvider);
    final linked =
        _googleProfileLink.isLinked && _googleProfileLink.grantsDashboardAccess;
    final lockedBusinessEmail =
        _googleProfileLink.grantsDashboardAccess &&
            _googleProfileLink.googleUserEmail.trim().isNotEmpty
        ? _googleProfileLink.googleUserEmail.trim().toLowerCase()
        : (authUser != null &&
                  !authUser.isAnonymous &&
                  session.isAuthenticated &&
                  session.user.accountType == AccountType.business
              ? (authUser.email ?? '').trim().toLowerCase()
              : '');
    final hasPlace = _selectedPlace != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildRegisterStageStrip(theme, hasPlace: hasPlace, linked: linked),
        SizedBox(height: compact ? 20 : 24),
        if (!hasPlace) ...<Widget>[
          _buildSectionIntro(
            theme,
            title: 'Standort zuerst sauber festlegen',
            detail:
                'Wir koppeln das Studio immer an einen echten Standort. Suche deshalb exakt den Ort, den du später verwalten willst.',
          ),
          const SizedBox(height: 14),
          _buildBusinessSectionCard(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Schritt 1: Standort wählen',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Suche zuerst genau den Ort, den du später im Business Studio verwalten willst.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _buildNativeTextField(
                  label: 'Business suchen',
                  hintText: 'Businessname, Stadt oder Straße',
                  controller: _placeSearchController,
                  prefixIcon: Icons.search_rounded,
                  onChanged: _triggerPlaceSearch,
                ),
                if (_searchingPlaces) ...<Widget>[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ] else if (_placeResults.isEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _placeSearchController.text.trim().length >= 2
                          ? 'Noch kein passender Treffer. Versuch Name und Stadt zusammen.'
                          : 'Gib einen Businessnamen oder eine Adresse ein. Danach kannst du den passenden Ort direkt auswählen.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 12),
                  for (final place in _placeResults.take(
                    compact ? 3 : 5,
                  )) ...<Widget>[
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.storefront_rounded),
                        title: Text(place.name),
                        subtitle: Text(place.address),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _selectPlace(place),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ] else ...<Widget>[
          _buildBusinessSectionCard(
            theme,
            child: _buildNativeSelectedPlaceCard(theme),
          ),
          const SizedBox(height: 16),
          if (!linked) ...<Widget>[
            _buildSectionIntro(
              theme,
              title: 'Identität bestätigen',
              detail:
                  'Erst der bestätigte Nachweis schaltet das Business frei. Google Business ist der schnellste Weg, offizielle Unterlagen bleiben der sichere Reservepfad.',
            ),
            const SizedBox(height: 14),
            _buildBusinessSectionCard(
              theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Schritt 2: Identität bestätigen',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Zuerst versuchen wir die sichere Freischaltung über Google Business. Falls das hier nicht sauber greift, kannst du offizielle Unterlagen hochladen. Freigeschaltet wird nur, wenn die Beweise stark genug zusammenpassen.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNativeTextField(
                    label: 'Verantwortliche Person',
                    hintText: 'Vor- und Nachname laut Unterlage',
                    controller: _claimantNameController,
                    prefixIcon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildNativeTextField(
                    label: 'Business-E-Mail',
                    hintText: 'kontakt@deinbusiness.de',
                    controller: _emailController,
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    helperText:
                        'Diese E-Mail wird an die spätere Registrierung und die Dokumentenprüfung gebunden.',
                  ),
                  const SizedBox(height: 18),
                  _buildVerificationMethodCard(
                    theme,
                    icon: Icons.verified_rounded,
                    title: 'Google Business',
                    detail:
                        'Serverseitiger Abgleich auf bestätigten Verwaltungszugriff für genau diesen Standort.',
                    primary: true,
                    action: FilledButton.icon(
                      onPressed: _connectingGoogleProfile
                          ? null
                          : _connectGoogleBusinessProfile,
                      icon: _connectingGoogleProfile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_rounded),
                      label: const Text('Mit Google Business verbinden'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildVerificationMethodCard(
                    theme,
                    icon: Icons.file_present_rounded,
                    title: 'Offizielle Unterlagen',
                    detail:
                        'Gewerbeanmeldung, Registerauszug oder vergleichbarer Nachweis werden sicher geprüft.',
                    action: OutlinedButton.icon(
                      onPressed: _verifyingDocumentEvidence
                          ? null
                          : _verifyBusinessEvidenceDocument,
                      icon: _verifyingDocumentEvidence
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_present_rounded),
                      label: Text(
                        _documentEvidenceName.isEmpty
                            ? 'Unterlage prüfen'
                            : 'Unterlage prüfen: $_documentEvidenceName',
                      ),
                    ),
                  ),
                  if (_verificationProgressSteps.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    _VerificationProgressCard(
                      title: _verificationProgressTitle,
                      subtitle: _verificationProgressSubtitle,
                      steps: _verificationProgressSteps,
                      activeIndex: _verificationProgressIndex,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Akzeptiert werden nur offizielle Unterlagen wie Gewerbeanmeldung, Gewerbeschein, Handwerkskammer-Nachweis, Handelsregisterauszug oder USt.-Nachweis.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (linked) ...<Widget>[
            _buildBusinessSectionCard(
              theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildNativeGoogleStatusCard(theme),
                  const SizedBox(height: 16),
                  _buildSectionIntro(
                    theme,
                    title: 'Studio-Zugang jetzt fertig machen',
                    detail:
                        'Die Business-Identität ist bestätigt. Wir übernehmen die verknüpfte Business-Mail und du legst nur noch dein sparGO-Passwort fest.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Schritt 3: Studio-Zugang festlegen',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Die verifizierte Business-Identität ist bestätigt. Die zugehörige Business-Mail wird übernommen und du legst nur noch dein sparGO-Passwort fest.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE7EAF1)),
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.mail_outline_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Verknüpfte Business-Mail',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lockedBusinessEmail.isEmpty
                                    ? 'Wird aus deiner bestätigten Business-Identität übernommen.'
                                    : lockedBusinessEmail,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNativeTextField(
                    label: 'Passwort',
                    hintText: 'Mindestens 6 Zeichen',
                    controller: _passwordController,
                    obscureText: _obscureRegisterPassword,
                    prefixIcon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => _obscureRegisterPassword =
                            !_obscureRegisterPassword,
                      ),
                      icon: Icon(
                        _obscureRegisterPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNativeTextField(
                    label: 'Passwort bestätigen',
                    hintText: 'Passwort erneut eingeben',
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    prefixIcon: Icons.verified_user_outlined,
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => _obscureConfirmPassword =
                            !_obscureConfirmPassword,
                      ),
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Business registrieren'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (_errorText != null && _errorText!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _buildInlineError(theme, _errorText!),
        ],
      ],
    );
  }

  Widget _buildBusinessSectionCard(ThemeData theme, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7EAF1)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF101828).withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInlineError(ThemeData theme, String message) {
    final isHint = message.startsWith('Hinweis:');
    final backgroundColor = isHint
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.errorContainer;
    final foregroundColor = isHint
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onErrorContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isHint ? Icons.info_outline_rounded : Icons.error_outline_rounded,
            color: foregroundColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterStageStrip(
    ThemeData theme, {
    required bool hasPlace,
    required bool linked,
  }) {
    Widget pill({
      required String label,
      required bool active,
      required bool complete,
    }) {
      final bg = complete
          ? const Color(0xFFFFEFF3)
          : active
          ? const Color(0xFFF7F8FC)
          : const Color(0xFFFFFFFF);
      final border = complete
          ? const Color(0xFFF2CDD7)
          : active
          ? const Color(0xFFE2E7F0)
          : const Color(0xFFE8EBF2);
      final fg = complete || active
          ? AppColors.ink
          : theme.colorScheme.onSurfaceVariant;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: complete
                      ? AppColors.primary
                      : active
                      ? const Color(0xFFEAEFFA)
                      : const Color(0xFFF6F7FA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  complete
                      ? Icons.check_rounded
                      : active
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: complete ? 14 : 12,
                  color: complete ? Colors.white : fg,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        pill(label: 'Ort wählen', active: !hasPlace, complete: hasPlace),
        const SizedBox(width: 8),
        pill(label: 'Verifizieren', active: hasPlace && !linked, complete: linked),
        const SizedBox(width: 8),
        pill(label: 'Zugang', active: linked, complete: false),
      ],
    );
  }

  Widget _buildNativeSelectedPlaceCard(ThemeData theme) {
    final place = _selectedPlace;
    if (place == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.storefront_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  place.address,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedPlace = null;
                _googleProfileLink = const BusinessGoogleProfileLink();
                _placeSearchController.clear();
                _placeResults = const <NearbyPlace>[];
                _errorText = null;
              });
            },
            child: const Text('Ändern'),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeGoogleStatusCard(ThemeData theme) {
    final email = _googleProfileLink.googleUserEmail.trim();
    final subtitle = _googleProfileLink.locationDisplayName.trim().isNotEmpty
        ? '${_googleProfileLink.locationDisplayName} - ${_googleProfileLink.roleLabel}'
        : 'Business-Identität erfolgreich bestätigt';
    final title = _googleProfileLink.normalizedRole ==
            'VERIFIED_REGISTRY_DOCUMENT'
        ? 'Business-Identität bestätigt'
        : 'Google Business verknüpft';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1FBF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD3E9DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CircleAvatar(
            backgroundColor: Color(0xFFDFF5E6),
            child: Icon(Icons.check_rounded, color: Colors.green),
          ),
          const SizedBox(width: 14),
          Expanded(
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
                const SizedBox(height: 4),
                Text(
                  email.isEmpty ? subtitle : '$subtitle\n$email',
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

  Widget _buildNativeTextField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? helperText,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: context.t(label),
        hintText: context.t(hintText),
        helperText: helperText == null ? null : context.t(helperText),
        prefixIcon: Icon(prefixIcon),
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildModeSwitch(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EAF1)),
      ),
      child: SegmentedButton<_BusinessEntryMode>(
        showSelectedIcon: false,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: Colors.transparent),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 16),
          ),
          textStyle: WidgetStatePropertyAll(
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        segments: const <ButtonSegment<_BusinessEntryMode>>[
          ButtonSegment<_BusinessEntryMode>(
            value: _BusinessEntryMode.login,
            label: Text('Einloggen'),
          ),
          ButtonSegment<_BusinessEntryMode>(
            value: _BusinessEntryMode.register,
            label: Text('Registrieren'),
          ),
        ],
        selected: <_BusinessEntryMode>{_mode},
        onSelectionChanged: (selection) => _setBusinessMode(selection.first),
      ),
    );
  }

  Widget _buildSectionIntro(
    ThemeData theme, {
    required String title,
    required String detail,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationMethodCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String detail,
    required Widget action,
    bool primary = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary ? const Color(0xFFFFF7F8) : const Color(0xFFF9FAFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary ? const Color(0xFFF0D8DF) : const Color(0xFFE8EBF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: primary
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.primaryContainer,
                child: Icon(
                  icon,
                  color: primary ? AppColors.primary : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
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
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: action),
        ],
      ),
    );
  }

  Widget _buildEntryCard(ThemeData theme, {required bool compact}) {
    if (_mode == _BusinessEntryMode.login) {
      return _BusinessLoginPanel(
        compact: compact,
        emailController: _emailController,
        passwordController: _passwordController,
        submitting: _submitting,
        sendingReset: _sendingReset,
        rememberMe: _rememberMe,
        errorText: _errorText,
        languageCode: ref.watch(appLanguageControllerProvider).languageCode,
        onRememberChanged: (value) => setState(() => _rememberMe = value),
        onSubmit: _submit,
        onForgotPassword: _handleForgotPassword,
        onGoogle: _submitBusinessGoogleLogin,
        onRegister: () {
          setState(() {
            _mode = _BusinessEntryMode.register;
            _errorText = null;
          });
        },
        onLanguageTap: _showLanguageSheet,
      );
    }

    final linked = _googleProfileLink.isLinked;
    final stageKey =
        '${_mode.name}-${_selectedPlace?.id ?? 'none'}-${linked ? 'linked' : 'open'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = compact || constraints.maxHeight < 720;

        return Container(
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(
            dense ? 18 : 28,
            dense ? 18 : 26,
            dense ? 18 : 28,
            dense ? 18 : 22,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(dense ? 30 : 36),
            border: Border.all(color: const Color(0xFFE5E8F0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF101828).withValues(alpha: 0.08),
                blurRadius: 42,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildEntryTopBar(theme, dense: dense),
              SizedBox(height: dense ? 12 : 14),
              _ModeSwitch(
                mode: _mode,
                dense: dense,
                onChanged: (mode) {
                  setState(() {
                    _mode = mode;
                    _errorText = null;
                  });
                },
              ),
              if (_mode == _BusinessEntryMode.register) ...<Widget>[
                SizedBox(height: dense ? 10 : 12),
                _buildRegisterProgress(theme, dense: dense),
              ],
              SizedBox(height: dense ? 12 : 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppDurations.fast,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Align(
                    key: ValueKey<String>(stageKey),
                    alignment: Alignment.topLeft,
                    child: _mode == _BusinessEntryMode.login
                        ? _buildLoginFields(compact: dense)
                        : _buildRegisterFields(compact: dense),
                  ),
                ),
              ),
              if (_errorText != null) ...<Widget>[
                SizedBox(height: dense ? 10 : 12),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 14 : 16,
                    vertical: dense ? 12 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFF2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF4CDD7)),
                  ),
                  child: Text(
                    _errorText!,
                    maxLines: dense ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
              SizedBox(height: dense ? 12 : 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_submitting || _connectingGoogleProfile)
                      ? null
                      : _primaryAction(linked: linked),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(dense ? 52 : 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: (_submitting || _connectingGoogleProfile)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        )
                      : Text(
                          _primaryActionLabel(linked: linked),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              if (_mode == _BusinessEntryMode.login) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _sendingReset ? null : _handleForgotPassword,
                    child: Text(
                      _sendingReset
                          ? 'Link wird gesendet...'
                          : 'Passwort vergessen?',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  int get _registerStageIndex {
    if (_selectedPlace == null) {
      return 0;
    }
    if (!_googleProfileLink.grantsDashboardAccess) {
      return 1;
    }
    return 2;
  }

  Widget _buildEntryTopBar(ThemeData theme, {required bool dense}) {
    return Row(
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6FA),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E7EF)),
          ),
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.ink,
            splashRadius: dense ? 18 : 20,
            constraints: BoxConstraints.tightFor(
              width: dense ? 44 : 48,
              height: dense ? 44 : 48,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'sparGO Business',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _mode == _BusinessEntryMode.login ? 'Login' : 'Registrierung',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Image.asset(
          'assets/branding/spargo_onboarding_logo.png',
          width: dense ? 72 : 94,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _buildRegisterProgress(ThemeData theme, {required bool dense}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _RegisterStepPill(
              label: 'Ort',
              icon: Icons.search_rounded,
              active: _registerStageIndex == 0,
              complete: _registerStageIndex > 0,
              dense: dense,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _RegisterStepPill(
              label: 'Google',
              icon: Icons.verified_rounded,
              active: _registerStageIndex == 1,
              complete: _registerStageIndex > 1,
              dense: dense,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _RegisterStepPill(
              label: 'Zugang',
              icon: Icons.lock_outline_rounded,
              active: _registerStageIndex == 2,
              complete: false,
              dense: dense,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageLead({
    required String eyebrow,
    required String title,
    required String detail,
    required bool compact,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          eyebrow,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.02,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF636B78),
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleBusinessSection({
    required bool linked,
    required bool compact,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: linked ? const Color(0xFFF1F7F2) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: linked ? const Color(0xFFD9E9DE) : const Color(0xFFE4E9F2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: compact ? 38 : 42,
            height: compact ? 38 : 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              linked
                  ? Icons.verified_rounded
                  : Icons.store_mall_directory_rounded,
              color: linked
                  ? const Color(0xFF2E7D4F)
                  : AppColors.primary,
              size: compact ? 20 : 22,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  linked
                      ? 'Google Business verbunden'
                      : 'Google Business verifizieren',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  linked
                      ? '${_googleProfileLink.locationDisplayName} · ${_googleProfileLink.roleLabel}'
                      : 'Es geht nur mit dem verifizierten Profil genau dieses Standorts weiter.',
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF606874),
                    height: 1.25,
                  ),
                ),
                if (linked &&
                    _googleProfileLink.googleUserEmail
                        .trim()
                        .isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _googleProfileLink.googleUserEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  VoidCallback? _primaryAction({required bool linked}) {
    final canUseAutomaticCompanyVerification =
        _verificationPlaceId.trim().isNotEmpty &&
        _verificationWebsite.trim().isNotEmpty;
    if (_mode == _BusinessEntryMode.login) {
      return _submit;
    }
    if (_selectedPlace == null) {
      return null;
    }
    if (!linked && !canUseAutomaticCompanyVerification) {
      return _connectGoogleBusinessProfile;
    }
    return _submit;
  }

  String _primaryActionLabel({required bool linked}) {
    final canUseAutomaticCompanyVerification =
        _verificationPlaceId.trim().isNotEmpty &&
        _verificationWebsite.trim().isNotEmpty;
    if (_mode == _BusinessEntryMode.login) {
      return 'Einloggen';
    }
    if (_selectedPlace == null) {
      return 'Ort auswählen';
    }
    if (!linked && !canUseAutomaticCompanyVerification) {
      return 'Google verbinden';
    }
    return 'Zugang festlegen';
  }

  Widget _buildLoginFields({required bool compact}) {
    return Column(
      key: const ValueKey<String>('business-login-fields'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildStageLead(
          eyebrow: 'Studio Login',
          title: 'Business einloggen',
          detail: 'Mit Mail und Passwort direkt ins Studio.',
          compact: compact,
        ),
        SizedBox(height: compact ? 14 : 16),
        _BusinessTextField(
          controller: _emailController,
          label: 'Business-E-Mail',
          hintText: context.t('kontakt@dein-business.de'),
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.mail_outline_rounded,
          compact: compact,
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        _BusinessTextField(
          controller: _passwordController,
          label: 'Passwort',
          hintText: context.t('Dein Studio-Passwort'),
          obscureText: true,
          prefixIcon: Icons.lock_outline_rounded,
          compact: compact,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Widget _buildRegisterFields({required bool compact}) {
    final linked =
        _googleProfileLink.isLinked && _googleProfileLink.grantsDashboardAccess;
    final canUseAutomaticCompanyVerification =
        _verificationPlaceId.trim().isNotEmpty &&
        _verificationWebsite.trim().isNotEmpty;

    if (_selectedPlace == null) {
      return Column(
        key: const ValueKey<String>('business-register-search'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStageLead(
            eyebrow: 'Schritt 1',
            title: 'Business zuerst suchen',
            detail: 'Name oder Stadt eingeben, passenden Ort antippen.',
            compact: compact,
          ),
          SizedBox(height: compact ? 14 : 16),
          _buildPlaceSearchSection(compact: compact),
        ],
      );
    }

    if (!linked && !canUseAutomaticCompanyVerification) {
      return Column(
        key: const ValueKey<String>('business-register-connect'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStageLead(
            eyebrow: 'Schritt 2',
            title: 'Google Business bestätigen',
            detail: 'Nur das verifizierte Profil dieses Orts kann weitergehen.',
            compact: compact,
          ),
          SizedBox(height: compact ? 14 : 16),
          _buildSelectedPlaceSummary(compact: compact),
          SizedBox(height: compact ? 12 : 14),
          _buildGoogleBusinessSection(linked: false, compact: compact),
        ],
      );
    }

    return Column(
      key: const ValueKey<String>('business-register-credentials'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildStageLead(
          eyebrow: 'Schritt 3',
          title: 'Studio-Zugang festlegen',
          detail: 'Mail und Passwort setzen, dann ist dein Studio bereit.',
          compact: compact,
        ),
        SizedBox(height: compact ? 14 : 16),
        _buildSelectedPlaceSummary(compact: compact),
        SizedBox(height: compact ? 12 : 14),
        _buildGoogleBusinessSection(linked: linked, compact: compact),
        SizedBox(height: compact ? 14 : 16),
        _buildCredentialFields(compact: compact),
      ],
    );
  }

  Widget _buildCredentialFields({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _BusinessTextField(
          controller: _emailController,
          label: 'Business-E-Mail',
          hintText: context.t('kontakt@dein-business.de'),
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.alternate_email_rounded,
          compact: compact,
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        _BusinessTextField(
          controller: _passwordController,
          label: 'Passwort',
          hintText: context.t('Mindestens 6 Zeichen'),
          obscureText: true,
          prefixIcon: Icons.lock_outline_rounded,
          compact: compact,
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        _BusinessTextField(
          controller: _confirmPasswordController,
          label: 'Passwort bestätigen',
          hintText: context.t('Nochmal eingeben'),
          obscureText: true,
          prefixIcon: Icons.verified_user_outlined,
          compact: compact,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Widget _buildSelectedPlaceSummary({required bool compact}) {
    final theme = Theme.of(context);
    final place = _selectedPlace;

    if (place == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: compact ? 38 : 42,
            height: compact ? 38 : 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place.address,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF636B78),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedPlace = null;
                _googleProfileLink = const BusinessGoogleProfileLink();
                _placeSearchController.clear();
                _placeResults = const <NearbyPlace>[];
              });
            },
            child: const Text('Ändern'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceSearchSection({required bool compact}) {
    final theme = Theme.of(context);
    final query = _placeSearchController.text.trim();
    final hasQuery = query.length >= 2;
    final visibleResults = _placeResults
        .take(compact ? 1 : 3)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _BusinessTextField(
          controller: _placeSearchController,
          hintText: context.t('Businessname, Stadt oder Straße'),
          prefixIcon: Icons.search_rounded,
          compact: true,
          onChanged: _triggerPlaceSearch,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_searchingPlaces)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (visibleResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              hasQuery
                  ? 'Noch kein passender Treffer. Versuch Name plus Stadt.'
                  : 'Direkt über Google suchen und dann den Ort auswählen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF636B78),
                height: 1.3,
              ),
            ),
          )
        else ...<Widget>[
          for (
            var index = 0;
            index < visibleResults.length;
            index++
          ) ...<Widget>[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _selectPlace(visibleResults[index]),
              child: Ink(
                padding: EdgeInsets.all(compact ? 14 : 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE4E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E8EF)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            visibleResults[index].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            visibleResults[index].address,
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF636B78),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Color(0xFF7F8794),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_placeResults.length > visibleResults.length) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Mehr Treffer gefunden. Suchbegriff kurz verfeinern.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF636B78),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ],
    );
  }

  void _triggerPlaceSearch(String value) {
    _placeSearchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searchingPlaces = false;
        _placeResults = const <NearbyPlace>[];
      });
      return;
    }

    _placeSearchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => _searchBusinesses(query),
    );
  }

  Future<void> _searchBusinesses(String query) async {
    if (!mounted) {
      return;
    }

    setState(() => _searchingPlaces = true);
    final results = await ref
        .read(googleMapsPlacesServiceProvider)
        .searchBusinesses(query: query);
    if (!mounted || _placeSearchController.text.trim() != query) {
      return;
    }
    setState(() {
      _searchingPlaces = false;
      _placeResults = results;
    });
  }

  void _selectPlace(NearbyPlace place) {
    setState(() {
      _selectedPlace = place;
      _verificationPlaceId = place.id.trim();
      _verificationWebsite = place.websiteUrl?.trim() ?? '';
      _businessNameController.text = place.name;
      _websiteController.text = place.websiteUrl?.trim() ?? '';
      _placeResults = const <NearbyPlace>[];
      _placeSearchController.text = place.name;
      _errorText = null;
      _googleProfileLink = const BusinessGoogleProfileLink();
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (_mode == _BusinessEntryMode.login) {
        await _submitLogin();
      } else {
        await _submitRegister();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyAuthError(error);
      setState(() => _errorText = message);
      showAppToast(context, message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      throw Exception('Bitte gib Business-E-Mail und Passwort ein.');
    }

    final result = await ref
        .read(sessionControllerProvider.notifier)
        .login(email: email, password: password)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw Exception(
            'Business-Login antwortet gerade nicht. Bitte Seite neu laden und erneut versuchen.',
          ),
        );
    if (result.requiresApproval) {
      throw Exception(
        'Neues ${result.deviceLabel} erkannt. Bitte bestätige zuerst die Mail an ${result.email}.',
      );
    }

    final session = await _waitForResolvedSession();
    final userRecord = ref.read(firebaseSessionUserRecordProvider).valueOrNull;
    if (userRecord == null) {
      throw Exception(
        'Business-Profil konnte nach dem Login nicht sauber geladen werden. Bitte versuche es erneut.',
      );
    }

    if (!session.isBusinessAccount) {
      await ref.read(sessionControllerProvider.notifier).signOut();
      throw Exception(
        'Dieses Konto ist kein Business-Zugang. Bitte nutze dafür den normalen Nutzer-Login.',
      );
    }

    if (!mounted) {
      return;
    }

    final targetRoute = session.needsBusinessSetup
        ? AppRoutes.businessOnboarding
        : AppRoutes.businessDashboard;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(targetRoute, (route) => false);
  }

  Future<void> _submitBusinessGoogleLogin() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .loginWithGoogle()
          .timeout(
            const Duration(seconds: 24),
            onTimeout: () => throw Exception(
              'Google-Login antwortet gerade nicht. Bitte erneut versuchen.',
            ),
          );
      if (result.requiresApproval) {
        throw Exception(
          'Neues ${result.deviceLabel} erkannt. Bitte bestätige zuerst die Mail an ${result.email}.',
        );
      }

      final session = await _waitForResolvedSession();
      final userRecord = ref
          .read(firebaseSessionUserRecordProvider)
          .valueOrNull;
      if (userRecord == null) {
        throw Exception(
          'Business-Profil konnte nach dem Google-Login nicht sauber geladen werden.',
        );
      }
      if (!session.isBusinessAccount) {
        await ref.read(sessionControllerProvider.notifier).signOut();
        throw Exception(
          'Dieses Google-Konto ist kein Business-Zugang. Bitte nutze den normalen Nutzer-Login.',
        );
      }
      if (!mounted) {
        return;
      }
      final targetRoute = session.needsBusinessSetup
          ? AppRoutes.businessOnboarding
          : AppRoutes.businessDashboard;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(targetRoute, (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyAuthError(error);
      setState(() => _errorText = message);
      showAppToast(context, message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _showLanguageSheet() async {
    final currentCode = ref.read(appLanguageControllerProvider).languageCode;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (context) => _BusinessLanguageSheet(selectedCode: currentCode),
    );
    if (selected == null || selected == currentCode) {
      return;
    }
    await ref
        .read(appLanguageControllerProvider.notifier)
        .setLanguageCode(selected);
  }

  Future<SessionState> _waitForResolvedSession() async {
    for (var attempt = 0; attempt < 30; attempt += 1) {
      if (!mounted) {
        return ref.read(sessionControllerProvider);
      }

      final authUser = ref.read(authUserProvider);
      final session = ref.read(sessionControllerProvider);
      final userRecord = ref
          .read(firebaseSessionUserRecordProvider)
          .valueOrNull;
      final expectedAccountType = userRecord == null
          ? null
          : (userRecord.ownedBusinessId.isNotEmpty
                ? AccountType.business
                : userRecord.user.accountType);

      final sessionResolved =
          authUser != null &&
          userRecord != null &&
          session.isAuthenticated &&
          session.user.id == authUser.uid &&
          session.user.accountType == expectedAccountType &&
          session.businessOnboardingComplete ==
              userRecord.businessOnboardingComplete &&
          session.ownedBusinessId == userRecord.ownedBusinessId;

      if (sessionResolved) {
        return session;
      }

      await Future<void>.delayed(const Duration(milliseconds: 140));
    }

    return ref.read(sessionControllerProvider);
  }

  Future<void> _submitRegister() async {
    if (!_ensureBusinessFlowAllowed()) {
      return;
    }
    final selectedPlace = _selectedPlace;
    final name = _businessNameController.text.trim();
    final verifiedPlaceWebsite = _googleProfileLink.website.trim().isNotEmpty
        ? _googleProfileLink.website.trim()
        : (_verificationWebsite.trim().isNotEmpty
              ? _verificationWebsite.trim()
              : (selectedPlace?.websiteUrl?.trim() ?? ''));
    final website = _websiteController.text.trim().isEmpty
        ? verifiedPlaceWebsite
        : _websiteController.text.trim();
    final email = _googleProfileLink.googleUserEmail.trim().isNotEmpty
        ? _googleProfileLink.googleUserEmail.trim().toLowerCase()
        : _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final claimantName = _claimantNameController.text.trim();
    final hasVerifiedGoogleProfile =
        _googleProfileLink.isLinked && _googleProfileLink.grantsDashboardAccess;
    final effectiveEmail = email;

    if (selectedPlace == null) {
      throw Exception(
        'Bitte suche zuerst dein Business über Google und wähle den passenden Ort aus.',
      );
    }
    if (!hasVerifiedGoogleProfile) {
      throw Exception(
        'Bitte bestätige zuerst dein Business über Google Business für genau diesen Standort.',
      );
    }
    if (name.isEmpty || effectiveEmail.isEmpty || password.isEmpty) {
      throw Exception(
        'Bitte Business-Name und Passwort ausfüllen.',
      );
    }
    if (password.length < 6) {
      throw Exception('Das Passwort muss mindestens 6 Zeichen haben.');
    }
    if (password != confirmPassword) {
      throw Exception('Die Passwörter stimmen nicht überein.');
    }
    final city = hasVerifiedGoogleProfile
        ? (_googleProfileLink.locationCity.trim().isEmpty
              ? 'Deutschlandweit'
              : _googleProfileLink.locationCity.trim())
        : 'Deutschlandweit';
    final address = hasVerifiedGoogleProfile
        ? (_googleProfileLink.locationAddress.trim().isEmpty
              ? selectedPlace.address.trim()
              : _googleProfileLink.locationAddress.trim())
        : selectedPlace.address.trim();
    final handle = _buildBusinessHandle(name, effectiveEmail);

    await ref
        .read(sessionControllerProvider.notifier)
        .register(
          email: effectiveEmail,
          password: password,
          name: name,
          handle: handle,
          city: city,
          accountType: AccountType.business,
        );

    final draftBusiness = ref.read(ownedBusinessProvider);
    ref
        .read(ownedBusinessDraftProvider.notifier)
        .save(
          business: draftBusiness,
          category: draftBusiness.category,
          name: name,
          tagline: '',
          description: '',
          shortDescription: '',
          website: website,
          phone: hasVerifiedGoogleProfile ? _googleProfileLink.phone.trim() : '',
          contactEmail: effectiveEmail,
          legalEntityName: name,
          imprintInfo: '',
          address: address,
          city: city,
          district: city == 'Deutschlandweit'
              ? 'Deine Nähe'
              : 'In deiner Nähe',
          claimedByName: claimantName,
          claimedByRole: hasVerifiedGoogleProfile
              ? (_googleProfileLink.roleLabel == 'Unbekannt'
                    ? ''
                    : _googleProfileLink.roleLabel)
              : '',
          ownershipConfirmed: hasVerifiedGoogleProfile,
          verificationPlaceId: _verificationPlaceId,
          verificationWebsite: website,
          verificationMethod: BusinessVerificationMethod.googleBusinessProfile,
          googleProfileLink: _googleProfileLink,
        );

    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.businessOnboarding, (route) => false);
  }

  Future<void> _handleForgotPassword() async {
    if (_sendingReset) {
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(
        () => _errorText = 'Bitte gib zuerst deine Business-E-Mail ein.',
      );
      return;
    }

    setState(() => _sendingReset = true);
    try {
      await ref.read(repositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) {
        return;
      }
      showAppToast(context, 'Reset-Link wurde gesendet.');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyAuthError(error);
      setState(() => _errorText = message);
      showAppToast(context, message);
    } finally {
      if (mounted) {
        setState(() => _sendingReset = false);
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

    final selectedPlace = _selectedPlace;
    if (selectedPlace == null) {
      setState(
        () => _errorText = 'Suche zuerst dein Business über Google Places.',
      );
      return;
    }

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
      final matchingLinks = await service.fetchMatchingOwnedOrManagedLocations(
        selectedPlace,
      );
      _setVerificationProgressStage(
        1,
        subtitle:
            'Google-Zugriff ist da. Jetzt gleichen wir mögliche Business-Standorte mit deiner Auswahl ab.',
      );
      if (!mounted) {
        return;
      }

      if (matchingLinks.isEmpty) {
        throw Exception(
          'In deinem Google Business Konto wurde kein Standort gefunden, der zu deiner Auswahl passt.',
        );
      }

      final selectedLink = await _pickGoogleProfileLink(matchingLinks);
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
      if (_selectedPlace != null &&
          !_googleLocationMatchesSelectedPlace(
            link: verifiedLink,
            place: _selectedPlace!,
          )) {
        throw Exception(
          'Der verbundene Google Business Standort passt nicht zu deiner Auswahl. Bitte wähle das passende Geschäft aus.',
        );
      }

      setState(() {
        _googleProfileLink = verifiedLink;
        _errorText = null;
      });
      _applyGoogleProfileLink(verifiedLink);
      _clearVerificationProgress();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_looksLikeGoogleBusinessLimit(error.toString())) {
        final canTryCompanyIdentity =
            (selectedPlace.websiteUrl?.trim().isNotEmpty ?? false);
        if (canTryCompanyIdentity) {
          try {
            final service = ref.read(googleBusinessProfileServiceProvider);
            _setVerificationProgressStage(
              3,
              subtitle:
                  'Google ist ausgelastet. Wir prüfen jetzt sichere Unternehmenssignale für genau diesen Standort.',
            );
            final identityLink = await service.verifyCompanyIdentityForPlace(
              selectedPlace,
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _googleProfileLink = identityLink;
              _errorText = null;
            });
            _applyGoogleProfileLink(identityLink);
            showAppToast(
              context,
              'Unternehmenszugang wurde automatisch bestätigt.',
            );
            _clearVerificationProgress();
            return;
          } on Object catch (identityError) {
            if (!mounted) {
              return;
            }
            final identityMessage = _friendlyBusinessConnectError(
              identityError,
              fallback:
                  'Hinweis: Google Business ist gerade ausgelastet. Nutze direkt die sichere Dokumentenprüfung darunter - ohne zusätzliches Google-Popup.',
            );
            setState(() {
              _errorText = identityMessage;
            });
            showAppToast(
              context,
              identityMessage.replaceFirst('Hinweis: ', ''),
            );
            _clearVerificationProgress();
            return;
          }
        }
        const infoMessage =
            'Hinweis: Google Business ist gerade ausgelastet. Nutze direkt die sichere Dokumentenprüfung darunter - ohne zusätzliches Google-Popup.';
        setState(() {
          _errorText = infoMessage;
        });
        showAppToast(context, infoMessage.replaceFirst('Hinweis: ', ''));
        _clearVerificationProgress();
        return;
      }
      final message = _friendlyBusinessConnectError(
        error,
        fallback:
            'Google Business konnte für diesen Standort gerade nicht bestätigt werden. Bitte versuche es erneut.',
      );
      setState(() {
        _errorText = message;
      });
      showAppToast(context, message);
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

    final selectedPlace = _selectedPlace;
    if (selectedPlace == null) {
      setState(
        () => _errorText = 'Suche zuerst dein Business über Google Places.',
      );
      return;
    }

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
      if (!mounted) {
        return;
      }
      const message = 'Das ausgewählte Dokument konnte nicht gelesen werden.';
      setState(() => _errorText = message);
      showAppToast(context, message);
      return;
    }

    final claimantName = _claimantNameController.text.trim();
    final claimedBusinessEmail = _emailController.text.trim().toLowerCase();
    if (claimantName.isEmpty) {
      const message =
          'Bitte gib zuerst die verantwortliche Person an, die auf der Unterlage genannt ist.';
      if (!mounted) {
        return;
      }
      setState(() => _errorText = message);
      showAppToast(context, message);
      return;
    }
    if (claimedBusinessEmail.isEmpty) {
      const message =
          'Bitte gib zuerst die Business-E-Mail ein, die später den Studio-Zugang bekommen soll.';
      if (!mounted) {
        return;
      }
      setState(() => _errorText = message);
      showAppToast(context, message);
      return;
    }

    setState(() {
      _verifyingDocumentEvidence = true;
      _errorText = null;
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
      _setVerificationProgressStage(
        2,
        subtitle:
            'Wir gleichen jetzt Inhaber, Standort und amtliche Referenzen serverseitig ab.',
      );
      final link = await ref
          .read(googleBusinessProfileServiceProvider)
          .verifyBusinessEvidenceDocument(
            place: selectedPlace,
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
        _googleProfileLink = link;
        _errorText = null;
      });
      _applyGoogleProfileLink(link);
      _clearVerificationProgress();
      showAppToast(
        context,
        'Offizielle Unterlagen wurden serverseitig bestätigt.',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyBusinessConnectError(
        error,
        fallback:
            'Die Register- und Dokumentenprüfung konnte gerade nicht abgeschlossen werden.',
      );
      setState(() => _errorText = message);
      showAppToast(context, message);
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
        final visibleLinks = links.take(4).toList(growable: false);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: AppSpacing.md),
                for (
                  var index = 0;
                  index < visibleLinks.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) const SizedBox(height: AppSpacing.sm),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      onTap: () =>
                          Navigator.of(context).pop(visibleLinks[index]),
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
                              visibleLinks[index].locationDisplayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              visibleLinks[index].locationAddress.isEmpty
                                  ? visibleLinks[index].locationCity
                                  : visibleLinks[index].locationAddress,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${visibleLinks[index].roleLabel} - ${visibleLinks[index].googleUserEmail}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (links.length > visibleLinks.length) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Mehr Treffer vorhanden. Bitte Suchbegriff in Google Business genauer halten.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyGoogleProfileLink(BusinessGoogleProfileLink link) {
    if (_businessNameController.text.trim().isEmpty &&
        link.locationDisplayName.isNotEmpty) {
      _businessNameController.text = link.locationDisplayName.trim();
    }
    if (_websiteController.text.trim().isEmpty &&
        link.website.trim().isNotEmpty) {
      _websiteController.text = link.website.trim();
    }
    _verificationPlaceId = link.placeId.trim();
    if (link.website.trim().isNotEmpty) {
      _verificationWebsite = link.website.trim();
    }
    if (link.googleUserEmail.trim().isNotEmpty) {
      _emailController.text = link.googleUserEmail.trim();
    }
  }

  bool _googleLocationMatchesSelectedPlace({
    required BusinessGoogleProfileLink link,
    required NearbyPlace place,
  }) {
    final selectedPlaceId = place.id.trim();
    final linkedPlaceId = link.placeId.trim();
    return selectedPlaceId.isNotEmpty &&
        linkedPlaceId.isNotEmpty &&
        selectedPlaceId == linkedPlaceId;
  }

  String _buildBusinessHandle(String name, String email) {
    final seed = name.trim().isNotEmpty
        ? name.trim()
        : (email.contains('@') ? email.split('@').first : 'spargo-business');
    final normalized = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${normalized.isEmpty ? 'spargobusiness' : normalized}';
  }

  String _friendlyAuthError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Die E-Mail-Adresse ist nicht gültig.';
        case 'email-already-in-use':
          return 'Für diese E-Mail gibt es schon ein Konto.';
        case 'wrong-password':
        case 'invalid-credential':
        case 'user-not-found':
          return 'E-Mail oder Passwort stimmen nicht.';
        case 'weak-password':
          return 'Bitte nimm ein stärkeres Passwort.';
        case 'too-many-requests':
          return 'Zu viele Versuche. Bitte kurz später nochmal.';
        case 'network-request-failed':
          return 'Netzwerkfehler. Bitte prüfe deine Verbindung.';
      }
    }

    final message = error.toString().toLowerCase();
    if (_looksLikeGoogleBusinessLimit(message)) {
      return 'Google Business ist gerade ausgelastet. Bitte versuche die Verknüpfung in einem Moment erneut.';
    }
    if (message.contains('permission-denied') ||
        message.contains('insufficient permission')) {
      return 'Die Business-Anmeldung ist serverseitig noch nicht sauber freigegeben.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _friendlyBusinessConnectError(
    Object error, {
    required String fallback,
  }) {
    final raw = error.toString();
    final cleaned = raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('Google Business Verbindung fehlgeschlagen: ', '')
        .trim();
    if (cleaned.isEmpty) {
      return fallback;
    }
    if (_looksLikeGoogleBusinessLimit(cleaned)) {
      return 'Hinweis: Google Business ist gerade ausgelastet. Nutze direkt die sichere Dokumentenprüfung darunter - ohne zusätzliches Google-Popup.';
    }
    return cleaned;
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
    final message =
        'Du bist gerade mit einem normalen Nutzerkonto angemeldet. Für Business-Registrierung musst du dich zuerst ausloggen und danach mit einem separaten Business-Zugang weitermachen.';
    setState(() => _errorText = message);
    showAppToast(context, message);
    return false;
  }

  Future<void> _signOutConsumerSession() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _googleProfileLink = const BusinessGoogleProfileLink();
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        'Nutzerkonto wurde abgemeldet. Du kannst jetzt mit einem Business-Zugang weitermachen.',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyAuthError(error);
      setState(() => _errorText = message);
      showAppToast(context, message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

}

class _BusinessHeroPanel extends StatelessWidget {
  const _BusinessHeroPanel({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF10141E),
            Color(0xFF192232),
            Color(0xFF24334B),
          ],
        ),
        borderRadius: BorderRadius.circular(36),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 42,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -32,
            top: -12,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -42,
            bottom: -54,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    onPressed: onBack,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      'Business Studio',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Image.asset(
                'assets/branding/spargo_complete_logo.png',
                width: 188,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Verifiziert.\nVerbunden.\nLive.',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.9,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  'Suche deinen Ort, verbinde das passende Google Business Profil und öffne danach sofort dein Studio.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Column(
                  children: <Widget>[
                    _HeroLineItem(
                      icon: Icons.search_rounded,
                      title: 'Ort finden',
                      text: 'Google-Suche direkt im Studio.',
                    ),
                    SizedBox(height: AppSpacing.md),
                    _HeroLineItem(
                      icon: Icons.verified_rounded,
                      title: 'Profil prüfen',
                      text: 'Nur mit verifiziertem Profil geht es weiter.',
                    ),
                    SizedBox(height: AppSpacing.md),
                    _HeroLineItem(
                      icon: Icons.dashboard_customize_outlined,
                      title: 'Studio öffnen',
                      text: 'Stories, Coupons und Insights an einem Ort.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroLineItem extends StatelessWidget {
  const _HeroLineItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
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

class _BusinessDesktopHeroPanel extends StatefulWidget {
  const _BusinessDesktopHeroPanel();

  @override
  State<_BusinessDesktopHeroPanel> createState() =>
      _BusinessDesktopHeroPanelState();
}

class _BusinessDesktopHeroPanelState extends State<_BusinessDesktopHeroPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          1.05,
          math.max(
            0.84,
            math.min(constraints.maxWidth / 790, constraints.maxHeight / 900),
          ),
        );
        final padding = 42.0 * scale;

        return Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.fromLTRB(padding, padding, padding, 34 * scale),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.985),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF8E6675).withValues(alpha: 0.12),
                blurRadius: 52,
                offset: const Offset(0, 26),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: -130 * scale,
                top: -140 * scale,
                child: Container(
                  width: 290 * scale,
                  height: 290 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.055),
                  ),
                ),
              ),
              Positioned(
                right: -84 * scale,
                top: 120 * scale,
                child: Container(
                  width: 360 * scale,
                  height: 360 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        AppColors.primary.withValues(alpha: 0.15),
                        AppColors.primary.withValues(alpha: 0.015),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -34 * scale,
                bottom: -18 * scale,
                child: Container(
                  width: 380 * scale,
                  height: 190 * scale,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(120),
                    color: const Color(0xFFFFF3F6),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Image.asset(
                        'assets/branding/spargo_onboarding_logo.png',
                        width: 176 * scale,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                      const _BusinessDesktopStudioPill(),
                    ],
                  ),
                  SizedBox(height: 30 * scale),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              RichText(
                                text: TextSpan(
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w900,
                                    height: 1.04,
                                    letterSpacing: -0.6,
                                    fontSize: 47 * scale,
                                  ),
                                  children: const <InlineSpan>[
                                    TextSpan(text: 'Dein Business.\n'),
                                    TextSpan(text: 'Verifiziert.\n'),
                                    TextSpan(
                                      text: 'Verbunden.',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20 * scale),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 470 * scale,
                                ),
                                child: Text(
                                  'Verbinde dein Business mit sparGO und erreiche tausende Nutzer in deiner Nähe – einfach, schnell und sicher.',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    height: 1.38,
                                    fontSize: 17 * scale,
                                  ),
                                ),
                              ),
                              SizedBox(height: 34 * scale),
                              const _BusinessDesktopBenefitList(),
                              const Spacer(),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: <Widget>[
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF00A878),
                                    size: 22,
                                  ),
                                  Text(
                                    'Trustpilot',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    '4.8',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List<Widget>.generate(
                                      5,
                                      (_) => const Padding(
                                        padding: EdgeInsets.only(right: 2),
                                        child: Icon(
                                          Icons.star_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Basierend auf 1.200+ Bewertungen',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10 * scale),
                        Expanded(
                          flex: 8,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                final wave = math.sin(
                                  _controller.value * math.pi * 2,
                                );
                                return Transform.translate(
                                  offset: Offset(0, wave * 7),
                                  child: child,
                                );
                              },
                              child: _BusinessDesktopHeroVisual(scale: scale),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessDesktopStudioPill extends StatelessWidget {
  const _BusinessDesktopStudioPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECE2E7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.business_center_outlined,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            'Business Studio',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDesktopBenefitList extends StatelessWidget {
  const _BusinessDesktopBenefitList();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 390,
      child: Column(
        children: <Widget>[
          _BusinessDesktopBenefitTile(
            icon: Icons.verified_user_outlined,
            title: 'Sicher & zuverlässig',
            text: 'Verifizierte Profile für mehr Vertrauen.',
          ),
          SizedBox(height: 18),
          _BusinessDesktopBenefitTile(
            icon: Icons.groups_2_outlined,
            title: 'Mehr Reichweite',
            text: 'Erreiche neue Kunden in deiner Nähe.',
          ),
          SizedBox(height: 18),
          _BusinessDesktopBenefitTile(
            icon: Icons.trending_up_rounded,
            title: 'Wachstum fördern',
            text: 'Insights, Angebote & Aktionen an einem Ort.',
          ),
        ],
      ),
    );
  }
}

class _BusinessDesktopBenefitTile extends StatelessWidget {
  const _BusinessDesktopBenefitTile({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEF2),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BusinessDesktopHeroVisual extends StatelessWidget {
  const _BusinessDesktopHeroVisual({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360 * scale,
      height: 430 * scale,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Positioned(
            bottom: 8 * scale,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(0.88),
              child: Container(
                width: 286 * scale,
                height: 118 * scale,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFFF4F6), Color(0xFFF3D9DF)],
                  ),
                  borderRadius: BorderRadius.circular(30 * scale),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 34,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 8 * scale,
            bottom: 80 * scale,
            child: Container(
              width: 246 * scale,
              height: 246 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.primary.withValues(alpha: 0.16),
                    AppColors.primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 84 * scale,
            child: Container(
              width: 172 * scale,
              height: 224 * scale,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Colors.white, Color(0xFFFFE8EE)],
                ),
                borderRadius: BorderRadius.circular(32 * scale),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF9B6B79).withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 104 * scale,
                  height: 96 * scale,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20 * scale),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.34),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: CustomPaint(painter: _StorePainter()),
                ),
              ),
            ),
          ),
          Positioned(
            right: 40 * scale,
            top: 28 * scale,
            child: Container(
              width: 84 * scale,
              height: 84 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFFF6C87), AppColors.primary],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.36),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 46 * scale,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDesktopLoginCard extends StatelessWidget {
  const _BusinessDesktopLoginCard({
    required this.emailController,
    required this.passwordController,
    required this.submitting,
    required this.sendingReset,
    required this.rememberMe,
    required this.languageCode,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onRegister,
    required this.onLanguageTap,
    this.errorText,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool submitting;
  final bool sendingReset;
  final bool rememberMe;
  final String languageCode;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogle;
  final VoidCallback onRegister;
  final VoidCallback onLanguageTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          1.0,
          math.max(
            0.82,
            math.min(constraints.maxWidth / 860, constraints.maxHeight / 880),
          ),
        );
        final paddingX = 38.0 * scale;
        final dense = scale < 0.9;

        return Container(
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(
            paddingX,
            34 * scale,
            paddingX,
            30 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.985),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF8E6675).withValues(alpha: 0.11),
                blurRadius: 46,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -110 * scale,
                top: -90 * scale,
                child: Container(
                  width: 240 * scale,
                  height: 240 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.03),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Image.asset(
                        'assets/branding/spargo_onboarding_logo.png',
                        width: 148 * scale,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                      _BusinessLanguagePill(
                        languageCode: languageCode,
                        onTap: onLanguageTap,
                      ),
                    ],
                  ),
                  SizedBox(height: 28 * scale),
                  Text(
                    'Willkommen zurück!',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                      height: 1.04,
                      letterSpacing: -0.5,
                      fontSize: 34 * scale,
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Text(
                    'Schön, dass du wieder da bist.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 17 * scale,
                    ),
                  ),
                  SizedBox(height: 28 * scale),
                  _BusinessDesktopModeSwitch(onRegister: onRegister),
                  SizedBox(height: 26 * scale),
                  _BusinessLoginInput(
                    label: 'Business E-Mail',
                    hintText: 'deine@business.de',
                    controller: emailController,
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => onSubmit(),
                    dense: dense,
                  ),
                  SizedBox(height: 18 * scale),
                  _BusinessLoginInput(
                    label: 'Passwort',
                    hintText: 'Dein Passwort',
                    controller: passwordController,
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                    onSubmitted: (_) => onSubmit(),
                    dense: dense,
                  ),
                  SizedBox(height: 16 * scale),
                  _BusinessDesktopRememberRow(
                    rememberMe: rememberMe,
                    sendingReset: sendingReset,
                    onRememberChanged: onRememberChanged,
                    onForgotPassword: onForgotPassword,
                  ),
                  if (errorText != null &&
                      errorText!.trim().isNotEmpty) ...<Widget>[
                    SizedBox(height: 14 * scale),
                    _BusinessInlineError(message: errorText!),
                  ],
                  SizedBox(height: 18 * scale),
                  _BusinessDesktopPrimaryButton(
                    label: 'Einloggen',
                    loading: submitting,
                    onTap: submitting ? null : onSubmit,
                  ),
                  SizedBox(height: 18 * scale),
                  const _BusinessOrDivider(),
                  SizedBox(height: 18 * scale),
                  _BusinessDesktopGoogleButton(
                    loading: submitting,
                    onTap: submitting ? null : onGoogle,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessDesktopModeSwitch extends StatelessWidget {
  const _BusinessDesktopModeSwitch({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 66,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2F4),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  Center(
                    child: Text(
                      'Einloggen',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 72,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onRegister,
              borderRadius: BorderRadius.circular(18),
              child: Center(
                child: Text(
                  'Registrieren',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDesktopRememberRow extends StatelessWidget {
  const _BusinessDesktopRememberRow({
    required this.rememberMe,
    required this.sendingReset,
    required this.onRememberChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final bool sendingReset;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final leading = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              onTap: () => onRememberChanged(!rememberMe),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: rememberMe ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: rememberMe
                        ? AppColors.primary
                        : const Color(0xFFE3D9DE),
                  ),
                ),
                child: rememberMe
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Angemeldet bleiben',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );

        final trailing = TextButton(
          onPressed: sendingReset ? null : onForgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            sendingReset ? 'Sende...' : 'Passwort vergessen?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

        if (constraints.maxWidth < 470) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[leading, const SizedBox(height: 10), trailing],
          );
        }

        return Row(children: <Widget>[leading, const Spacer(), trailing]);
      },
    );
  }
}

class _BusinessDesktopPrimaryButton extends StatelessWidget {
  const _BusinessDesktopPrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFFFF4A63), Color(0xFFF50046)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BusinessDesktopGoogleButton extends StatelessWidget {
  const _BusinessDesktopGoogleButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAE1E4)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.045),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const _GoogleMark(size: 22),
                      const SizedBox(width: 16),
                      Text(
                        'Mit Google fortfahren',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
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

class _BusinessResponsiveBusinessLoginLayout extends StatelessWidget {
  const _BusinessResponsiveBusinessLoginLayout({
    required this.useTwoPane,
    required this.availableHeight,
    required this.emailController,
    required this.passwordController,
    required this.submitting,
    required this.sendingReset,
    required this.rememberMe,
    required this.languageCode,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onRegister,
    required this.onLanguageTap,
    this.errorText,
  });

  final bool useTwoPane;
  final double availableHeight;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool submitting;
  final bool sendingReset;
  final bool rememberMe;
  final String languageCode;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogle;
  final VoidCallback onRegister;
  final VoidCallback onLanguageTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final maxWidth = useTwoPane ? 1760.0 : 1120.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: useTwoPane
          ? SizedBox(
              height: availableHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Expanded(flex: 11, child: _BusinessFreshHeroCard()),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 12,
                    child: _BusinessFreshLoginCard(
                      emailController: emailController,
                      passwordController: passwordController,
                      submitting: submitting,
                      sendingReset: sendingReset,
                      rememberMe: rememberMe,
                      errorText: errorText,
                      languageCode: languageCode,
                      onRememberChanged: onRememberChanged,
                      onSubmit: onSubmit,
                      onForgotPassword: onForgotPassword,
                      onGoogle: onGoogle,
                      onRegister: onRegister,
                      onLanguageTap: onLanguageTap,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: math.min(560, availableHeight * 0.48),
                    child: const _BusinessFreshHeroCard(),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: math.min(760, availableHeight * 0.72),
                    child: _BusinessFreshLoginCard(
                      emailController: emailController,
                      passwordController: passwordController,
                      submitting: submitting,
                      sendingReset: sendingReset,
                      rememberMe: rememberMe,
                      errorText: errorText,
                      languageCode: languageCode,
                      onRememberChanged: onRememberChanged,
                      onSubmit: onSubmit,
                      onForgotPassword: onForgotPassword,
                      onGoogle: onGoogle,
                      onRegister: onRegister,
                      onLanguageTap: onLanguageTap,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BusinessFreshHeroCard extends StatelessWidget {
  const _BusinessFreshHeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 720 || constraints.maxHeight < 650;
        final horizontalPadding = compact ? 28.0 : 44.0;
        final verticalPadding = compact ? 28.0 : 42.0;
        final titleSize = compact ? 48.0 : 68.0;
        final bodySize = compact ? 16.0 : 20.0;

        return Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFFE8EAF0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF1E293B).withValues(alpha: 0.06),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: -120,
                top: -120,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                right: -80,
                bottom: -50,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        AppColors.primary.withValues(alpha: 0.11),
                        AppColors.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Image.asset(
                        'assets/branding/spargo_onboarding_logo.png',
                        width: compact ? 150 : 184,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                      const _BusinessFreshStudioPill(),
                    ],
                  ),
                  SizedBox(height: compact ? 24 : 34),
                  Expanded(
                    child: Flex(
                      direction: constraints.maxWidth >= 760
                          ? Axis.horizontal
                          : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          flex: constraints.maxWidth >= 760 ? 11 : 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              RichText(
                                text: TextSpan(
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w900,
                                    height: 0.98,
                                    letterSpacing: -1.1,
                                    fontSize: titleSize,
                                  ),
                                  children: const <InlineSpan>[
                                    TextSpan(text: 'Dein Business.\n'),
                                    TextSpan(text: 'Verifiziert.\n'),
                                    TextSpan(
                                      text: 'Verbunden.',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Verbinde dein Business mit sparGO und erreiche tausende Nutzer in deiner Nähe – einfach, schnell und sicher.',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: bodySize,
                                  height: 1.35,
                                  color: const Color(0xFF5F6574),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _BusinessFreshBenefitList(),
                              const Spacer(),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: <Widget>[
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF00A878),
                                    size: 22,
                                  ),
                                  Text(
                                    'Trustpilot',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  Text(
                                    '4.8',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List<Widget>.generate(
                                      5,
                                      (_) => const Padding(
                                        padding: EdgeInsets.only(right: 2),
                                        child: Icon(
                                          Icons.star_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Basierend auf 1.200+ Bewertungen',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth >= 760 ? 20 : 0,
                          height: constraints.maxWidth >= 760 ? 0 : 20,
                        ),
                        Expanded(
                          flex: constraints.maxWidth >= 760 ? 8 : 0,
                          child: const Align(
                            alignment: Alignment.bottomCenter,
                            child: _BusinessFreshHeroIllustration(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessFreshStudioPill extends StatelessWidget {
  const _BusinessFreshStudioPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAF0)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF111827).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.business_center_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Text(
            'Business Studio',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessFreshBenefitList extends StatelessWidget {
  const _BusinessFreshBenefitList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _BusinessFreshBenefitTile(
          icon: Icons.verified_user_outlined,
          title: 'Sicher & zuverlässig',
          text: 'Verifizierte Profile für mehr Vertrauen.',
        ),
        SizedBox(height: 16),
        _BusinessFreshBenefitTile(
          icon: Icons.groups_2_outlined,
          title: 'Mehr Reichweite',
          text: 'Erreiche neue Kunden in deiner Nähe.',
        ),
        SizedBox(height: 16),
        _BusinessFreshBenefitTile(
          icon: Icons.trending_up_rounded,
          title: 'Wachstum fördern',
          text: 'Insights, Angebote & Aktionen an einem Ort.',
        ),
      ],
    );
  }
}

class _BusinessFreshBenefitTile extends StatelessWidget {
  const _BusinessFreshBenefitTile({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F4),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                  height: 1.24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BusinessFreshHeroIllustration extends StatelessWidget {
  const _BusinessFreshHeroIllustration();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 360,
        height: 420,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Positioned(
              bottom: 14,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(0.9),
                child: Container(
                  width: 292,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFFFFF5F7), Color(0xFFF3D9DF)],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 18,
              bottom: 90,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      AppColors.primary.withValues(alpha: 0.13),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 92,
              child: Container(
                width: 176,
                height: 226,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Colors.white, Color(0xFFFFEBF0)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 108,
                    height: 102,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: CustomPaint(painter: _StorePainter()),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 34,
              right: 34,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFF647E), AppColors.primary],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessFreshLoginCard extends StatelessWidget {
  const _BusinessFreshLoginCard({
    required this.emailController,
    required this.passwordController,
    required this.submitting,
    required this.sendingReset,
    required this.rememberMe,
    required this.languageCode,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onRegister,
    required this.onLanguageTap,
    this.errorText,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool submitting;
  final bool sendingReset;
  final bool rememberMe;
  final String languageCode;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogle;
  final VoidCallback onRegister;
  final VoidCallback onLanguageTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 760 || constraints.maxHeight < 700;
        final horizontalPadding = compact ? 26.0 : 42.0;
        final verticalPadding = compact ? 26.0 : 36.0;

        return Container(
          height: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFFE8EAF0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF1E293B).withValues(alpha: 0.06),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Image.asset(
                    'assets/branding/spargo_onboarding_logo.png',
                    width: compact ? 132 : 156,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  _BusinessLanguagePill(
                    languageCode: languageCode,
                    onTap: onLanguageTap,
                  ),
                ],
              ),
              SizedBox(height: compact ? 24 : 32),
              Text(
                'Willkommen zurück!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: compact ? 28 : 34,
                  height: 1.04,
                  letterSpacing: -0.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Schön, dass du wieder da bist.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 16 : 18,
                ),
              ),
              SizedBox(height: compact ? 22 : 28),
              _BusinessFreshModeSwitch(onRegister: onRegister),
              SizedBox(height: compact ? 22 : 28),
              _BusinessLoginInput(
                label: 'Business E-Mail',
                hintText: 'deine@business.de',
                controller: emailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => onSubmit(),
                dense: compact,
              ),
              const SizedBox(height: 18),
              _BusinessLoginInput(
                label: 'Passwort',
                hintText: 'Dein Passwort',
                controller: passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
                onSubmitted: (_) => onSubmit(),
                dense: compact,
              ),
              const SizedBox(height: 16),
              _BusinessFreshRememberRow(
                rememberMe: rememberMe,
                sendingReset: sendingReset,
                onRememberChanged: onRememberChanged,
                onForgotPassword: onForgotPassword,
              ),
              if (errorText != null &&
                  errorText!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _BusinessInlineError(message: errorText!),
              ],
              const Spacer(),
              _BusinessFreshPrimaryButton(
                label: 'Einloggen',
                loading: submitting,
                onTap: submitting ? null : onSubmit,
              ),
              const SizedBox(height: 18),
              const _BusinessOrDivider(),
              const SizedBox(height: 18),
              _BusinessFreshGoogleButton(
                loading: submitting,
                onTap: submitting ? null : onGoogle,
              ),
              const SizedBox(height: 20),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      'Noch kein Business-Konto?',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: onRegister,
                      child: Text(
                        'Registrieren',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessFreshModeSwitch extends StatelessWidget {
  const _BusinessFreshModeSwitch({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF111827).withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Einloggen',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onRegister,
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: Text(
                  'Registrieren',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessFreshRememberRow extends StatelessWidget {
  const _BusinessFreshRememberRow({
    required this.rememberMe,
    required this.sendingReset,
    required this.onRememberChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final bool sendingReset;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final remember = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              onTap: () => onRememberChanged(!rememberMe),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: rememberMe ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: rememberMe
                        ? AppColors.primary
                        : const Color(0xFFE1DCE1),
                  ),
                ),
                child: rememberMe
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Angemeldet bleiben',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );

        final forgot = TextButton(
          onPressed: sendingReset ? null : onForgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            sendingReset ? 'Sende...' : 'Passwort vergessen?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[remember, const SizedBox(height: 8), forgot],
          );
        }

        return Row(children: <Widget>[remember, const Spacer(), forgot]);
      },
    );
  }
}

class _BusinessFreshPrimaryButton extends StatelessWidget {
  const _BusinessFreshPrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFFFF4A63), Color(0xFFF50046)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.26),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 18),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BusinessFreshGoogleButton extends StatelessWidget {
  const _BusinessFreshGoogleButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EAF0)),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const _GoogleMark(size: 22),
                      const SizedBox(width: 14),
                      Text(
                        'Mit Google fortfahren',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
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

class _BusinessHeroDesignPanel extends StatefulWidget {
  const _BusinessHeroDesignPanel({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_BusinessHeroDesignPanel> createState() =>
      _BusinessHeroDesignPanelState();
}

class _BusinessHeroDesignPanelState extends State<_BusinessHeroDesignPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(48, 44, 44, 40),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF9B6B79).withValues(alpha: 0.12),
            blurRadius: 46,
            offset: const Offset(0, 26),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -90,
            bottom: 28,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -42,
            child: Container(
              width: 360,
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(90),
                color: const Color(0xFFFFF0F3),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 34,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final wave = math.sin(_controller.value * math.pi * 2);
                return Transform.translate(
                  offset: Offset(0, wave * 7),
                  child: child,
                );
              },
              child: const _BusinessStudioVisual(),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Image.asset(
                    'assets/branding/spargo_onboarding_logo.png',
                    width: 150,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  _BusinessStudioPill(
                    icon: Icons.business_center_outlined,
                    label: 'Business Studio',
                    onTap: widget.onBack,
                  ),
                ],
              ),
              const SizedBox(height: 76),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    height: 1.04,
                    letterSpacing: 0,
                    fontSize: 58,
                  ),
                  children: const <InlineSpan>[
                    TextSpan(text: 'Dein Business.\nVerifiziert.\n'),
                    TextSpan(
                      text: 'Verbunden.',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Text(
                  'Verbinde dein Business mit sparGO und erreiche tausende Nutzer in deiner Nähe – einfach, schnell und sicher.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 52),
              const SizedBox(
                width: 390,
                child: Column(
                  children: <Widget>[
                    _BusinessHeroBenefit(
                      icon: Icons.verified_user_outlined,
                      title: 'Sicher & zuverlässig',
                      text: 'Verifizierte Profile für mehr Vertrauen.',
                    ),
                    SizedBox(height: 28),
                    _BusinessHeroBenefit(
                      icon: Icons.groups_2_outlined,
                      title: 'Mehr Reichweite',
                      text: 'Erreiche neue Kunden in deiner Nähe.',
                    ),
                    SizedBox(height: 28),
                    _BusinessHeroBenefit(
                      icon: Icons.trending_up_rounded,
                      title: 'Wachstum fördern',
                      text: 'Insights, Angebote & Aktionen an einem Ort.',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFF00A878),
                    size: 24,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Trustpilot',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '4.8',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (var index = 0; index < 5; index += 1)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(
                        Icons.star_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Basierend auf 1.200+ Bewertungen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessStudioPill extends StatelessWidget {
  const _BusinessStudioPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAE2E5)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.05),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessHeroBenefit extends StatelessWidget {
  const _BusinessHeroBenefit({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEF2),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.primary, size: 27),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BusinessStudioVisual extends StatelessWidget {
  const _BusinessStudioVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 388,
      height: 388,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Positioned(
            bottom: 0,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(0.88),
              child: Container(
                width: 346,
                height: 148,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFFF4F6), Color(0xFFF3D9DF)],
                  ),
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 34,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 74,
            child: Container(
              width: 174,
              height: 220,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Colors.white, Color(0xFFFFE8EE)],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF9B6B79).withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 102,
                  height: 94,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.34),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: CustomPaint(painter: _StorePainter()),
                ),
              ),
            ),
          ),
          Positioned(
            right: 64,
            top: 52,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFFF6C87), AppColors.primary],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.36),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final width = size.width;
    final height = size.height;

    final awning = Path()
      ..moveTo(width * 0.12, height * 0.2)
      ..lineTo(width * 0.88, height * 0.2)
      ..quadraticBezierTo(
        width * 0.82,
        height * 0.48,
        width * 0.68,
        height * 0.48,
      )
      ..quadraticBezierTo(
        width * 0.56,
        height * 0.48,
        width * 0.5,
        height * 0.38,
      )
      ..quadraticBezierTo(
        width * 0.44,
        height * 0.48,
        width * 0.32,
        height * 0.48,
      )
      ..quadraticBezierTo(
        width * 0.18,
        height * 0.48,
        width * 0.12,
        height * 0.2,
      )
      ..close();
    canvas.drawPath(awning, paint);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(width * 0.18, height * 0.47, width * 0.64, height * 0.38),
      Radius.circular(width * 0.07),
    );
    canvas.drawRRect(body, paint);

    final doorPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;
    final door = RRect.fromRectAndRadius(
      Rect.fromLTWH(width * 0.42, height * 0.58, width * 0.16, height * 0.27),
      Radius.circular(width * 0.08),
    );
    canvas.drawRRect(door, doorPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BusinessLoginPanel extends StatelessWidget {
  const _BusinessLoginPanel({
    required this.compact,
    required this.emailController,
    required this.passwordController,
    required this.submitting,
    required this.sendingReset,
    required this.rememberMe,
    required this.languageCode,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onRegister,
    required this.onLanguageTap,
    this.errorText,
  });

  final bool compact;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool submitting;
  final bool sendingReset;
  final bool rememberMe;
  final String languageCode;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogle;
  final VoidCallback onRegister;
  final VoidCallback onLanguageTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = compact || constraints.maxHeight < 760;
        final tight = constraints.maxHeight < 650;
        final horizontal = dense ? 24.0 : 56.0;

        return Container(
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            dense ? 24 : 42,
            horizontal,
            dense ? 22 : 36,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(dense ? 30 : 36),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF9B6B79).withValues(alpha: 0.11),
                blurRadius: 44,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Image.asset(
                    'assets/branding/spargo_onboarding_logo.png',
                    width: dense ? 120 : 156,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  _BusinessLanguagePill(
                    languageCode: languageCode,
                    onTap: onLanguageTap,
                  ),
                ],
              ),
              SizedBox(
                height: tight
                    ? 22
                    : dense
                    ? 32
                    : 62,
              ),
              Text(
                'Willkommen zurück!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: 0,
                  fontSize: dense ? 28 : 42,
                ),
              ),
              SizedBox(height: dense ? 8 : 10),
              Text(
                'Schön, dass du wieder da bist.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              SizedBox(
                height: tight
                    ? 18
                    : dense
                    ? 26
                    : 38,
              ),
              _BusinessLoginModeSwitch(onRegister: onRegister),
              SizedBox(
                height: tight
                    ? 18
                    : dense
                    ? 26
                    : 36,
              ),
              _BusinessLoginInput(
                label: 'Business E-Mail',
                hintText: 'deine@business.de',
                controller: emailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => onSubmit(),
                dense: dense,
              ),
              SizedBox(
                height: tight
                    ? 14
                    : dense
                    ? 20
                    : 28,
              ),
              _BusinessLoginInput(
                label: 'Passwort',
                hintText: 'Dein Passwort',
                controller: passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
                onSubmitted: (_) => onSubmit(),
                dense: dense,
              ),
              SizedBox(height: tight ? 14 : 20),
              _BusinessRememberRow(
                rememberMe: rememberMe,
                sendingReset: sendingReset,
                onRememberChanged: onRememberChanged,
                onForgotPassword: onForgotPassword,
              ),
              if (errorText != null &&
                  errorText!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _BusinessInlineError(message: errorText!),
              ],
              const Spacer(),
              _BusinessPrimaryButton(
                label: submitting ? 'Einloggen...' : 'Einloggen',
                loading: submitting,
                onTap: submitting ? null : onSubmit,
              ),
              SizedBox(height: dense ? 18 : 26),
              const _BusinessOrDivider(),
              SizedBox(height: dense ? 18 : 22),
              _BusinessGoogleButton(
                loading: submitting,
                onTap: submitting ? null : onGoogle,
              ),
              SizedBox(height: dense ? 18 : 28),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      'Noch kein Business-Konto? ',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: onRegister,
                      child: Text(
                        'Registrieren',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessLoginModeSwitch extends StatelessWidget {
  const _BusinessLoginModeSwitch({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  Center(
                    child: Text(
                      'Einloggen',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onRegister,
              child: Center(
                child: Text(
                  'Registrieren',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessLoginInput extends StatefulWidget {
  const _BusinessLoginInput({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.icon,
    required this.dense,
    this.keyboardType,
    this.obscureText = false,
    this.onSubmitted,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool dense;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_BusinessLoginInput> createState() => _BusinessLoginInputState();
}

class _BusinessLoginInputState extends State<_BusinessLoginInput> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          onSubmitted: widget.onSubmitted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF92878B),
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(
              widget.icon,
              color: const Color(0xFF7E7478),
              size: 24,
            ),
            suffixIcon: widget.obscureText
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF7E7478),
                    ),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: widget.dense ? 15 : 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEAE1E4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEAE1E4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessRememberRow extends StatelessWidget {
  const _BusinessRememberRow({
    required this.rememberMe,
    required this.sendingReset,
    required this.onRememberChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final bool sendingReset;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        GestureDetector(
          onTap: () => onRememberChanged(!rememberMe),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: rememberMe ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: rememberMe ? AppColors.primary : const Color(0xFFE4D9DD),
              ),
            ),
            child: rememberMe
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Angemeldet bleiben',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: sendingReset ? null : onForgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Text(
            sendingReset ? 'Sende...' : 'Passwort vergessen?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessInlineError extends StatelessWidget {
  const _BusinessInlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFF2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF4CDD7)),
      ),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

class _BusinessPrimaryButton extends StatelessWidget {
  const _BusinessPrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFFFF4D61), Color(0xFFF50046)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.26),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BusinessOrDivider extends StatelessWidget {
  const _BusinessOrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: Color(0xFFECE5E8))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'oder',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFECE5E8))),
      ],
    );
  }
}

class _BusinessGoogleButton extends StatelessWidget {
  const _BusinessGoogleButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEAE1E4)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const _GoogleMark(size: 22),
                const SizedBox(width: 16),
                Text(
                  'Mit Google fortfahren',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
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

class _GoogleMark extends StatelessWidget {
  const _GoogleMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.18;
    final rect = Offset.zero & size;
    final bluePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4285F4);
    final redPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEA4335);
    final yellowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFBBC05);
    final greenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF34A853);

    canvas.drawArc(rect.deflate(stroke / 2), -0.08, 1.28, false, bluePaint);
    canvas.drawArc(rect.deflate(stroke / 2), 4.98, 1.22, false, redPaint);
    canvas.drawArc(rect.deflate(stroke / 2), 2.72, 1.12, false, yellowPaint);
    canvas.drawArc(rect.deflate(stroke / 2), 1.8, 1.0, false, greenPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * 0.54, size.height * 0.5),
      Offset(size.width * 0.92, size.height * 0.5),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BusinessLanguagePill extends StatelessWidget {
  const _BusinessLanguagePill({
    required this.languageCode,
    required this.onTap,
  });

  final String languageCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = languageCode.toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECE4E7)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.language_rounded,
                color: Color(0xFF7E7478),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                code,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessLanguageSheet extends StatelessWidget {
  const _BusinessLanguageSheet({required this.selectedCode});

  final String selectedCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <({String code, String label})>[
      (code: 'de', label: 'Deutsch'),
      (code: 'en', label: 'English'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.12),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Sprache auswählen',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              for (final option in options) ...<Widget>[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(option.code),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: selectedCode == option.code
                            ? const Color(0xFFFFEEF2)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selectedCode == option.code
                              ? const Color(0xFFF8C8D2)
                              : const Color(0xFFECE4E7),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              option.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (selectedCode == option.code)
                            const Icon(
                              Icons.check_rounded,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (option != options.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterStepPill extends StatelessWidget {
  const _RegisterStepPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.complete,
    required this.dense,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool complete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? AppColors.ink
        : complete
        ? const Color(0xFFE9F4EC)
        : Colors.transparent;
    final foreground = active
        ? Colors.white
        : complete
        ? const Color(0xFF2E7D4F)
        : const Color(0xFF78808D);

    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(vertical: dense ? 10 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            complete && !active ? Icons.check_rounded : icon,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.onChanged,
    required this.dense,
  });

  final _BusinessEntryMode mode;
  final ValueChanged<_BusinessEntryMode> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EAF1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ModeButton(
              label: 'Einloggen',
              selected: mode == _BusinessEntryMode.login,
              dense: dense,
              onTap: () => onChanged(_BusinessEntryMode.login),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeButton(
              label: 'Registrieren',
              selected: mode == _BusinessEntryMode.register,
              dense: dense,
              onTap: () => onChanged(_BusinessEntryMode.register),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: dense ? 12 : 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BusinessTextField extends StatefulWidget {
  const _BusinessTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.label,
    this.keyboardType,
    this.obscureText = false,
    this.compact = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool compact;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_BusinessTextField> createState() => _BusinessTextFieldState();
}

class _BusinessTextFieldState extends State<_BusinessTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLabel = (widget.label ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasLabel) ...<Widget>[
          Text(
            widget.label!,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: Icon(widget.prefixIcon, size: 20),
            suffixIcon: widget.obscureText
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF7F8FB),
            contentPadding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 16 : 18,
              vertical: widget.compact ? 14 : 16,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: Color(0xFFE4E7EE)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: Color(0xFFE4E7EE)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < steps.length; index++) ...<Widget>[
            _VerificationProgressRow(
              step: steps[index],
              completed: activeIndex > index,
              active: activeIndex == index,
            ),
            if (index < steps.length - 1) const SizedBox(height: 10),
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
    final inactiveColor = theme.colorScheme.outline;

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
      leading = Icon(Icons.radio_button_unchecked_rounded, color: inactiveColor);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 22, height: 22, child: Center(child: leading)),
        const SizedBox(width: 12),
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

class _BusinessBackdrop extends StatelessWidget {
  const _BusinessBackdrop();

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

class _VerificationRouteCard extends StatelessWidget {
  const _VerificationRouteCard({
    required this.googleProfileLink,
    required this.selectedPlace,
  });

  final BusinessGoogleProfileLink googleProfileLink;
  final NearbyPlace? selectedPlace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2F3),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  selectedPlace == null
                      ? 'Suche zuerst dein Business über Google Places. Danach muss genau dieses Business über Google Business verifiziert verbunden werden.'
                      : googleProfileLink.isLinked
                      ? '${googleProfileLink.locationDisplayName} · ${googleProfileLink.roleLabel}'
                      : 'Business-Registrierung ist nur mit verifiziertem Google-Standort möglich.',
                  style: theme.textTheme.bodySmall?.copyWith(
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



