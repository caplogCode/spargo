import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/services/app_location_service.dart';
import '../../../../core/services/location_label_resolver.dart';
import '../../../../core/widgets/adaptive_scroll_body.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_shadows.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.startInBusinessMode = false});

  final bool startInBusinessMode;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _websiteController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _cityController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(milliseconds: 900),
  );
  late final _locationService = createAppLocationService();

  late _AccountMode _mode;
  bool _submitting = false;
  bool _locating = false;
  String? _resolvedLocationLabel;

  static const List<String> _citySuggestions = <String>[
    'Berlin',
    'Hamburg',
    'München',
    'Köln',
    'Frankfurt am Main',
    'Stuttgart',
    'Düsseldorf',
    'Dortmund',
    'Essen',
    'Leipzig',
    'Bremen',
    'Dresden',
    'Hannover',
    'Nürnberg',
    'Duisburg',
    'Bochum',
    'Wuppertal',
    'Bielefeld',
    'Bonn',
    'Münster',
    'Karlsruhe',
    'Mannheim',
    'Augsburg',
    'Wiesbaden',
    'Gelsenkirchen',
    'Münchengladbach',
    'Braunschweig',
    'Chemnitz',
    'Kiel',
    'Aachen',
    'Halle',
    'Magdeburg',
    'Freiburg',
    'Krefeld',
    'Lübeck',
    'Oberhausen',
    'Erfurt',
    'Mainz',
    'Rostock',
    'Kassel',
    'Potsdam',
    'Osnabrück',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.startInBusinessMode
        ? _AccountMode.business
        : _AccountMode.user;
    final initialUser = ref.read(currentUserProvider);
    final initialCity = initialUser.city.trim();
    final initialDistrict = initialUser.district.trim();

    _cityController.text =
        initialCity.isEmpty || initialCity == 'Deutschlandweit'
        ? ''
        : initialCity;

    if (_cityController.text.isNotEmpty && initialDistrict.isNotEmpty) {
      _resolvedLocationLabel = '$initialDistrict, ${_cityController.text}';
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _nameController.dispose();
    _websiteController.dispose();
    _nicknameController.dispose();
    _cityController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusiness = _mode == _AccountMode.business;
    final compact = MediaQuery.sizeOf(context).height < 760;
    final matchingCities = isBusiness
        ? const <String>[]
        : _matchingCities(_cityController.text);
    final locationLabel =
        _resolvedLocationLabel ??
        (_cityController.text.trim().isEmpty
            ? 'Standort später freigeben'
            : _cityController.text.trim());

    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: <Widget>[
          AdaptiveScrollBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  height: compact ? 168 : 188,
                  child: _RegisterHero(
                    isBusiness: isBusiness,
                    compact: compact,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _AccountModePicker(
                  current: _mode,
                  onChanged: (value) => setState(() => _mode = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isBusiness
                            ? 'Business-Zugang anlegen'
                            : 'Konto erstellen',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        isBusiness
                            ? 'Business-E-Mail und Passwort reichen. Mit Website geht es sofort, sonst über Google Business Profil.'
                            : 'Name, Nickname und E-Mail reichen für den Start.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isBusiness) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Mit Website plus Firmen-Mail geht es direkt. Ohne Domain bestätigst du dein Google Business Profil im nächsten Schritt.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: isBusiness
                              ? 'Business-Name'
                              : 'Vor- und Nachname',
                        ),
                      ),
                      if (isBusiness) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _websiteController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: context.t('Website (optional)'),
                            hintText: context.t('https://dein-business.de'),
                          ),
                        ),
                      ],
                      if (!isBusiness) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _nicknameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.t('Nickname'),
                            hintText: context.t('z. B. Lara, Ben oder Mila'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _cityController,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: context.t('Stadt oder Ort'),
                            hintText: context.t('Stadt eingeben'),
                          ),
                        ),
                        if (matchingCities.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: matchingCities
                                .map(
                                  (city) => ActionChip(
                                    label: Text(city),
                                    onPressed: () => _applyCity(city),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE8ED),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.my_location_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'Standort übernehmen',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          locationLabel,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _locating
                                      ? null
                                      : _requestLocation,
                                  child: Text(
                                    _locating
                                        ? 'Lädt...'
                                        : 'Standort freigeben',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: isBusiness ? 'Business-E-Mail' : 'E-Mail',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: context.t('Passwort'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        autocorrect: false,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: context.t('Passwort bestätigen'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AnimatedCtaButton(
                  label: _submitting
                      ? 'Wird angelegt...'
                      : isBusiness
                      ? 'Business-Zugang anlegen'
                      : 'Registrieren',
                  expanded: true,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.03,
              numberOfParticles: 24,
              gravity: 0.18,
              maxBlastForce: 20,
              minBlastForce: 7,
              colors: const <Color>[
                AppColors.primary,
                Color(0xFFFF86A0),
                Color(0xFFFFC2D0),
                Color(0xFF9CD7FF),
                Colors.white,
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _matchingCities(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const <String>[];
    }
    final matches = _citySuggestions
        .where((city) {
          return city.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
    return matches.take(6).toList(growable: false);
  }

  String _buildHandle({
    required String nickname,
    required String name,
    required String email,
  }) {
    final seed = nickname.trim().isNotEmpty
        ? nickname.trim()
        : name.trim().isNotEmpty
        ? name.trim()
        : (email.contains('@') ? email.split('@').first : 'spargo');
    final normalized = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${normalized.isEmpty ? 'spargo' : normalized}';
  }

  void _applyCity(String city) {
    final resolved = city.trim().isEmpty ? 'Deutschlandweit' : city.trim();
    _cityController
      ..text = resolved
      ..selection = TextSelection.collapsed(offset: resolved.length);
    ref
        .read(sessionControllerProvider.notifier)
        .grantLocation(
          city: resolved,
          district: 'In deiner Nähe',
          clearCoordinates: true,
        );
    _resolvedLocationLabel = 'In deiner Nähe, $resolved';
    setState(() {});
  }

  Future<void> _requestLocation() async {
    if (_locating) {
      return;
    }

    setState(() => _locating = true);

    try {
      final position = await _locationService.requestCurrentLocation();
      final resolvedLocation = await resolveLocationLabel(
        latitude: position.latitude,
        longitude: position.longitude,
        businesses: ref.read(businessesProvider),
      );

      _cityController
        ..text = resolvedLocation.city
        ..selection = TextSelection.collapsed(
          offset: resolvedLocation.city.length,
        );

      ref
          .read(sessionControllerProvider.notifier)
          .grantLocation(
            city: resolvedLocation.city,
            district: resolvedLocation.district,
            latitude: position.latitude,
            longitude: position.longitude,
          );

      setState(() {
        _resolvedLocationLabel =
            '${resolvedLocation.district}, ${resolvedLocation.city}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(context, error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _submit() async {
    final isBusiness = _mode == _AccountMode.business;
    final name = _nameController.text.trim();
    final website = _websiteController.text.trim();
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final city = _cityController.text.trim().isEmpty
        ? 'Deutschlandweit'
        : _cityController.text.trim();
    final handle = _buildHandle(nickname: nickname, name: name, email: email);

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showError(
        isBusiness
            ? 'Bitte Business-Name, Business-E-Mail und Passwort ausfüllen.'
            : 'Bitte Vor- und Nachname, E-Mail und Passwort ausfüllen.',
      );
      return;
    }

    if (password.length < 6) {
      _showError('Das Passwort muss mindestens 6 Zeichen haben.');
      return;
    }

    if (password != confirmPassword) {
      _showError('Die Passwörter stimmen nicht überein.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: email,
            password: password,
            name: name,
            handle: handle,
            city: city,
            accountType: isBusiness ? AccountType.business : AccountType.user,
          );

      if (!mounted) {
        return;
      }

      await _playRegistrationConfetti();
      if (!mounted) {
        return;
      }

      if (isBusiness) {
        final draftBusiness = ref.read(ownedBusinessProvider);
        final verificationMethod =
            _canUseBusinessEmailFastPath(email: email, website: website)
            ? BusinessVerificationMethod.emailDomain
            : BusinessVerificationMethod.googleBusinessProfile;
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
              phone: '',
              contactEmail: email,
              legalEntityName: name,
              imprintInfo: '',
              address: '',
              city: city,
              district: 'Deine Nähe',
              claimedByName: '',
              claimedByRole: '',
              ownershipConfirmed: true,
              verificationMethod: verificationMethod,
            );
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.businessOnboarding,
          (route) => false,
        );
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.shell, (route) => false);
    } on Exception catch (error) {
      _showError(_friendlyRegisterError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _friendlyRegisterError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('insufficient permission') ||
        lower.contains('missing or insufficient permissions') ||
        lower.contains('permission-denied')) {
      return 'Registrierung blockiert: Firestore erlaubt den Zugriff noch nicht korrekt.';
    }
    return 'Registrierung fehlgeschlagen: $error';
  }

  bool _emailMatchesWebsiteDomain({
    required String email,
    required String website,
  }) {
    final emailParts = email.trim().toLowerCase().split('@');
    if (emailParts.length != 2) {
      return false;
    }
    final emailDomain = emailParts.last;
    final uri = Uri.tryParse(
      website.startsWith('http://') || website.startsWith('https://')
          ? website
          : 'https://$website',
    );
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) {
      return false;
    }
    final normalizedHost = host.startsWith('www.') ? host.substring(4) : host;
    final normalizedEmailDomain = emailDomain.startsWith('www.')
        ? emailDomain.substring(4)
        : emailDomain;
    return normalizedEmailDomain == normalizedHost ||
        normalizedEmailDomain.endsWith('.$normalizedHost') ||
        normalizedHost.endsWith('.$normalizedEmailDomain');
  }

  bool _isPrivateMailboxDomain(String email) {
    final parts = email.trim().toLowerCase().split('@');
    if (parts.length != 2) {
      return true;
    }
    const blockedDomains = <String>{
      'gmail.com',
      'googlemail.com',
      'outlook.com',
      'hotmail.com',
      'live.com',
      'icloud.com',
      'me.com',
      'mac.com',
      'yahoo.com',
      'gmx.de',
      'gmx.net',
      'web.de',
      't-online.de',
      'aol.com',
      'mail.com',
      'proton.me',
      'protonmail.com',
    };
    return blockedDomains.contains(parts.last);
  }

  bool _canUseBusinessEmailFastPath({
    required String email,
    required String website,
  }) {
    if (website.trim().isEmpty) {
      return false;
    }
    if (_isPrivateMailboxDomain(email)) {
      return false;
    }
    return _emailMatchesWebsiteDomain(email: email, website: website);
  }

  void _showError(String message) {
    showAppToast(context, message);
  }

  Future<void> _playRegistrationConfetti() async {
    _confettiController.play();
    await Future<void>.delayed(const Duration(milliseconds: 820));
  }
}

class _RegisterHero extends StatelessWidget {
  const _RegisterHero({required this.isBusiness, required this.compact});

  final bool isBusiness;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final clampedScale = mediaQuery.textScaler.clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.04,
    );

    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: clampedScale),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.highlightStart,
              AppColors.highlightMid,
              AppColors.primary,
            ],
          ),
          boxShadow: <BoxShadow>[
            ...AppShadows.floating,
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -44,
              right: -12,
              child: Container(
                width: compact ? 120 : 148,
                height: compact ? 120 : 148,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: -34,
              bottom: -44,
              child: Container(
                width: compact ? 132 : 156,
                height: compact ? 132 : 156,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: compact ? -6 : 12,
              bottom: compact ? -6 : 4,
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(
                  'assets/branding/spargo_splashscreen.png',
                  width: compact ? 112 : 136,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _RegisterHeroPill(
                    icon: isBusiness
                        ? Icons.storefront_rounded
                        : Icons.person_rounded,
                    label: isBusiness ? 'Unternehmen' : 'Nutzerkonto',
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: compact ? 52 : 64,
                        height: compact ? 52 : 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.22),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isBusiness
                              ? Icons.campaign_rounded
                              : Icons.local_offer_rounded,
                          size: compact ? 24 : 28,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              isBusiness
                                  ? 'Business-Zugang'
                                  : 'Schnell registrieren',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 0.98,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isBusiness
                                  ? 'Zugang anlegen, dann direkt weiter ins Business-Profil.'
                                  : 'Name, Nickname und E-Mail genügen für den Start.',
                              maxLines: compact ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterHeroPill extends StatelessWidget {
  const _RegisterHeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AccountMode { user, business }

class _AccountModePicker extends StatelessWidget {
  const _AccountModePicker({required this.current, required this.onChanged});

  final _AccountMode current;
  final ValueChanged<_AccountMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildOption({
      required _AccountMode mode,
      required String label,
      required IconData icon,
    }) {
      final selected = current == mode;

      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(mode),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        icon,
                        size: 18,
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: <Widget>[
          buildOption(
            mode: _AccountMode.user,
            label: 'Nutzer',
            icon: Icons.person_rounded,
          ),
          buildOption(
            mode: _AccountMode.business,
            label: 'Unternehmen',
            icon: Icons.storefront_rounded,
          ),
        ],
      ),
    );
  }
}
