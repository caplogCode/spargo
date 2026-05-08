import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_functions_config.dart';
import '../../../../core/config/google_maps_config.dart';
import '../../../../core/constants/app_tokens.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_language_provider.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../theme/app_colors.dart';

const _distancePresets = <double>[
  minSearchRadiusKm,
  10,
  20,
  35,
  50,
  75,
  maxSearchRadiusKm,
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingOut = false;
  double? _draftDistanceKm;

  Future<void> _handleSignOut() async {
    if (_signingOut) {
      return;
    }

    setState(() => _signingOut = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _applyDistance(double value) {
    final normalizedValue = normalizeSearchRadiusKm(value);
    setState(() => _draftDistanceKm = normalizedValue);
    ref.read(settingsControllerProvider.notifier).setDistance(normalizedValue);
  }

  Future<void> _setLanguage(String languageCode) async {
    await ref
        .read(appLanguageControllerProvider.notifier)
        .setLanguageCode(languageCode);
    if (!mounted) {
      return;
    }
    showAppToast(
      context,
      languageCode == 'en'
          ? 'Sprache wurde auf Englisch gesetzt.'
          : 'Sprache wurde auf Deutsch gesetzt.',
      type: AppToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final language = ref.watch(appLanguageControllerProvider);
    final authUser = ref.watch(authUserProvider);
    final area = ref.watch(discoverSearchAreaProvider);
    final sliderDistanceKm =
        _draftDistanceKm != null &&
            (_draftDistanceKm! - settings.distanceKm).abs() >= 0.05
        ? _draftDistanceKm!
        : settings.distanceKm;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          const _SettingsSectionTitle(
            title: 'Sprache',
            subtitle:
                'Gilt für die komplette App, Firebase-Mails und bleibt gespeichert.',
          ),
          _SettingsCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _LanguageChoiceButton(
                    label: 'Deutsch',
                    code: 'DE',
                    selected: language.languageCode == 'de',
                    onTap: _signingOut ? null : () => _setLanguage('de'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _LanguageChoiceButton(
                    label: 'English',
                    code: 'EN',
                    selected: language.languageCode == 'en',
                    onTap: _signingOut ? null : () => _setLanguage('en'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SettingsSectionTitle(
            title: 'Suchradius',
            subtitle: 'Direkt sehen, wie weit dein Suchgebiet wirklich reicht.',
          ),
          _RadiusPreviewCard(
            radiusKm: sliderDistanceKm,
            city: area.city,
            district: area.district,
            latitude: area.latitude,
            longitude: area.longitude,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _distancePresets
                .map((preset) {
                  final selected = (sliderDistanceKm - preset).abs() < 0.5;
                  return ChoiceChip(
                    label: Text('${preset.round()} km'),
                    selected: selected,
                    onSelected: _signingOut
                        ? null
                        : (_) => _applyDistance(preset),
                    selectedColor: const Color(0xFFFFE7EE),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFFFFC8D7)
                            : theme.dividerColor,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: AppSpacing.md),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: const Color(0xFFFFDCE4),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.12),
              valueIndicatorColor: AppColors.primary,
              valueIndicatorTextStyle: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Slider(
              value: sliderDistanceKm
                  .clamp(minSearchRadiusKm, maxSearchRadiusKm)
                  .toDouble(),
              min: minSearchRadiusKm,
              max: maxSearchRadiusKm,
              divisions: ((maxSearchRadiusKm - minSearchRadiusKm) / 5).round(),
              label: '${sliderDistanceKm.toStringAsFixed(0)} km',
              onChanged: _signingOut
                  ? null
                  : (value) => setState(() => _draftDistanceKm = value),
              onChangeEnd: _signingOut ? null : _applyDistance,
            ),
          ),
          Text(
            'Öffentliche Quellen werden serverseitig nach deinem Radius geprüft. Direkte Coupons aus sparGO bleiben davon unberührt und stehen weiter oben im Feed.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SettingsSectionTitle(
            title: 'Benachrichtigungen',
            subtitle: 'Nur die Schalter, die für deinen Flow wirklich zählen.',
          ),
          _SettingsCard(
            child: Column(
              children: <Widget>[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.pushEnabled,
                  title: const Text('Push aktiv'),
                  subtitle: const Text(
                    'Deals, Wallet und Business-News direkt sehen',
                  ),
                  onChanged: _signingOut
                      ? null
                      : ref
                            .read(settingsControllerProvider.notifier)
                            .togglePush,
                ),
                Divider(color: theme.dividerColor, height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.openNowOnly,
                  title: const Text('Nur offen jetzt'),
                  subtitle: const Text(
                    'In Entdecken und Suche nur offene Orte priorisieren',
                  ),
                  onChanged: _signingOut
                      ? null
                      : ref
                            .read(settingsControllerProvider.notifier)
                            .toggleOpenNow,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SettingsSectionTitle(
            title: 'Konto',
            subtitle: 'Verifizierung und Abmeldung ohne versteckte Umwege.',
          ),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('E-Mail-Verifizierung'),
                  subtitle: Text(
                    authUser == null
                        ? 'Nicht angemeldet'
                        : authUser.emailVerified
                        ? 'Deine E-Mail ist bestätigt'
                        : 'Deine E-Mail ist noch nicht bestätigt',
                  ),
                  trailing:
                      authUser == null || authUser.emailVerified || _signingOut
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await ref
                                .read(repositoryProvider)
                                .sendEmailVerification();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Verifizierungs-Mail wurde gesendet.',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text('Senden'),
                        ),
                ),
                if (authUser != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _signingOut ? null : _handleSignOut,
                      child: Text(
                        _signingOut ? 'Wird abgemeldet...' : 'Abmelden',
                      ),
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
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LanguageChoiceButton extends StatelessWidget {
  const _LanguageChoiceButton({
    required this.label,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String code;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFE7EE)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: selected ? const Color(0xFFFFBFD0) : theme.dividerColor,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              height: 32,
              width: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Text(
                code,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? Colors.white : AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusPreviewCard extends StatelessWidget {
  const _RadiusPreviewCard({
    required this.radiusKm,
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  final double radiusKm;
  final String city;
  final String district;
  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCoordinates =
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
    final center = hasCoordinates
        ? gmaps.LatLng(latitude, longitude)
        : const gmaps.LatLng(51.1657, 10.4515);
    final effectiveRadiusKm = normalizeSearchRadiusKm(radiusKm);
    final locationLabel =
        district.trim().isEmpty ||
            district == 'Dein Viertel' ||
            district == city
        ? city
        : '$city, $district';
    final resolvedLocationLabel = locationLabel.trim().isEmpty
        ? 'Deutschland'
        : locationLabel;
    final useGoogleMap = hasGoogleMapsApiKey && !kIsWeb;
    final showStaticGoogleMap = !useGoogleMap;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Aktiver Radius',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resolvedLocationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7EE),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '${radiusKm.round()} km',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Die Karte zeigt dir direkt, wie weit dein aktuelles Suchgebiet rund um deinen Standort reicht.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 236,
              width: double.infinity,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: useGoogleMap
                        ? gmaps.GoogleMap(
                            initialCameraPosition: gmaps.CameraPosition(
                              target: center,
                              zoom: _radiusPreviewZoom(effectiveRadiusKm),
                            ),
                            mapType: gmaps.MapType.normal,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            compassEnabled: false,
                            rotateGesturesEnabled: false,
                            tiltGesturesEnabled: false,
                            circles: <gmaps.Circle>{
                              gmaps.Circle(
                                circleId: const gmaps.CircleId('radius'),
                                center: center,
                                radius: effectiveRadiusKm * 1000,
                                fillColor: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                strokeColor: AppColors.primary.withValues(
                                  alpha: 0.72,
                                ),
                                strokeWidth: 2,
                              ),
                            },
                            markers: <gmaps.Marker>{
                              gmaps.Marker(
                                markerId: const gmaps.MarkerId('center'),
                                position: center,
                              ),
                            },
                          )
                        : _StaticRadiusMap(
                            center: center,
                            zoom: _radiusPreviewZoom(effectiveRadiusKm),
                            radiusKm: effectiveRadiusKm,
                            showStaticMap: showStaticGoogleMap,
                          ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0.08),
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.08),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _RadiusInfoChip(
                icon: Icons.place_rounded,
                label: resolvedLocationLabel,
              ),
              _RadiusInfoChip(
                icon: Icons.radar_rounded,
                label: 'Suchgebiet ${radiusKm.round()} km',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _radiusPreviewZoom(double radiusKm) {
  if (radiusKm <= 8) {
    return 11.8;
  }
  if (radiusKm <= 15) {
    return 11.2;
  }
  if (radiusKm <= 35) {
    return 10.2;
  }
  if (radiusKm <= 75) {
    return 9.2;
  }
  if (radiusKm <= 100) {
    return 8.2;
  }
  return 7.6;
}

class _RadiusCenterPin extends StatelessWidget {
  const _RadiusCenterPin();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticRadiusMap extends StatelessWidget {
  const _StaticRadiusMap({
    required this.center,
    required this.zoom,
    required this.radiusKm,
    required this.showStaticMap,
  });

  final gmaps.LatLng center;
  final double zoom;
  final double radiusKm;
  final bool showStaticMap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? (constraints.maxWidth.round().clamp(220, 640) as num).toInt()
            : 640;
        final height = constraints.maxHeight.isFinite
            ? (constraints.maxHeight.round().clamp(220, 640) as num).toInt()
            : 480;
        final metersPerPixel = _metersPerPixel(
          latitude: center.latitude,
          zoom: zoom,
        );
        final radiusPixels =
            (((radiusKm * 1000) / metersPerPixel).clamp(
                      18,
                      math.min(width, height) * 0.92,
                    )
                    as num)
                .toDouble();

        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: showStaticMap
                  ? Image.network(
                      _buildStaticMapUrl(width: width, height: height),
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (context, error, stackTrace) {
                        return const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0xFFF6F7F9),
                                Color(0xFFEFF2F5),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0xFFF6F7F9), Color(0xFFEFF2F5)],
                        ),
                      ),
                    ),
            ),
            IgnorePointer(
              child: Container(
                width: radiusPixels * 2,
                height: radiusPixels * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.72),
                    width: 2,
                  ),
                ),
              ),
            ),
            const IgnorePointer(child: _RadiusCenterPin()),
          ],
        );
      },
    );
  }

  double _metersPerPixel({required double latitude, required double zoom}) {
    final latitudeRadians = latitude * (math.pi / 180);
    return 156543.03392 *
        math.cos(latitudeRadians) /
        (math.pow(2, zoom) as num).toDouble();
  }

  String _buildStaticMapUrl({required int width, required int height}) {
    return firebaseFunctionUri(
      'googleMapsStaticMap',
      queryParameters: <String, String>{
        'centerLat': center.latitude.toString(),
        'centerLng': center.longitude.toString(),
        'zoom': zoom.toStringAsFixed(2),
        'width': width.toString(),
        'height': height.toString(),
      },
    ).toString();
  }
}

class _RadiusInfoChip extends StatelessWidget {
  const _RadiusInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F7),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: const Color(0xFFFFDCE4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF6D4F59),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
