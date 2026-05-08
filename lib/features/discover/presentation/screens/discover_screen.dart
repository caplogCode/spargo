import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/web_image_proxy.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/nearby_place_models.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/discovery_map_surface.dart';
import '../../../../shared/widgets/showcase_coupon_card.dart';
import '../../../../theme/app_colors.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _selectedSpotId;
  final PageController _spotController = PageController(viewportFraction: 0.86);

  @override
  void dispose() {
    _spotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final deals = ref.watch(dealsProvider);
    final businesses = ref.watch(businessesProvider);
    final stories = ref.watch(storiesProvider);
    final seenStories = ref.watch(storySeenProvider);
    final storyByBusinessId = <String, Story>{};
    for (final story in stories) {
      final current = storyByBusinessId[story.businessId];
      if (current == null ||
          (seenStories.contains(current.id) &&
              !seenStories.contains(story.id))) {
        storyByBusinessId[story.businessId] = story;
      }
    }
    final storyBusinessIds = storyByBusinessId.keys.toSet();
    final area = ref.watch(discoverSearchAreaProvider);
    final distanceKm = ref.watch(settingsControllerProvider).distanceKm;
    final publicCouponStatus = ref.watch(publicCouponCacheStatusProvider);
    final spots = _buildFallbackSpots(
      user: user,
      area: area,
      radiusKm: distanceKm,
      businesses: businesses,
      deals: deals,
      storyBusinessIds: storyBusinessIds,
    );
    final visibleSpots = spots
        .where((spot) => !spot.isLivePlace)
        .toList(growable: false);

    if (visibleSpots.isEmpty) {
      final emptyBody = _DiscoverEmptyState(
        embedded: widget.embedded,
        area: area,
        status: publicCouponStatus,
      );
      if (widget.embedded) {
        return emptyBody;
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF8F3EC),
        body: emptyBody,
      );
    }

    final selectedSpot = visibleSpots.any((spot) => spot.id == _selectedSpotId)
        ? visibleSpots.firstWhere((spot) => spot.id == _selectedSpotId)
        : visibleSpots.first;
    final selectedBusinessId = selectedSpot.id;
    final offerCountByBusinessKey = <String, int>{};
    for (final spot in visibleSpots) {
      final businessKey = spot.business?.id ?? spot.id;
      offerCountByBusinessKey.update(
        businessKey,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final mapPins = <DiscoveryMapPin>[];
    final seenBusinessKeys = <String>{};
    for (final spot in visibleSpots) {
      final businessKey = spot.business?.id ?? spot.id;
      if (!seenBusinessKeys.add(businessKey)) {
        continue;
      }
      final representative = visibleSpots.firstWhere(
        (candidate) =>
            (candidate.business?.id ?? candidate.id) == businessKey &&
            (candidate.id == selectedSpot.id ||
                offerCountByBusinessKey[businessKey] == 1),
        orElse: () => spot,
      );
      mapPins.add(
        DiscoveryMapPin(
          id: representative.id,
          label: representative.name,
          initials: representative.initials,
          alignment: _pinAlignment(mapPins.length),
          palette: representative.palette,
          hasStory: representative.hasStory,
          isPublicCoupon: representative.isPublicCoupon,
          latitude: representative.latitude,
          longitude: representative.longitude,
          imageUrl: _discoverSpotImageUrl(ref, representative),
          stackCount: offerCountByBusinessKey[businessKey] ?? 1,
        ),
      );
    }
    final selectedIndex = visibleSpots.indexWhere(
      (spot) => spot.id == selectedBusinessId,
    );
    final showStatusBar = publicCouponStatus.cacheBlocked;
    const initialSheetSize = 0.50;
    const minSheetSize = 0.50;
    final maxSheetSize = widget.embedded ? 0.88 : 0.84;

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final sheetHeight = constraints.maxHeight * initialSheetSize;
        final mapOverlap = widget.embedded ? 34.0 : 40.0;
        final compactMap = constraints.maxHeight < 820;

        return Stack(
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: sheetHeight - mapOverlap,
              child: DiscoveryMapSurface(
                compact: compactMap,
                bottomInset: mapOverlap + 6,
                pins: mapPins,
                selectedPinId: selectedBusinessId,
                focusInitials: '',
                showFocusPulse: false,
                centerLatitude: area.latitude,
                centerLongitude: area.longitude,
                zoom: 13.4,
                searchHint: 'Suche',
                onSearchTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.search),
                onFilterTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.search),
                onPinTap: (spotId) {
                  final index = spots.indexWhere((spot) => spot.id == spotId);
                  if (index < 0) {
                    return;
                  }
                  final visibleIndex = visibleSpots.indexWhere(
                    (spot) => spot.id == spotId,
                  );
                  if (visibleIndex < 0) {
                    return;
                  }
                  final spot = visibleSpots[visibleIndex];
                  setState(() => _selectedSpotId = spotId);
                  _spotController.animateToPage(
                    visibleIndex,
                    duration: AppDurations.medium,
                    curve: Curves.easeOutCubic,
                  );
                  if (spot.hasStory) {
                    final story =
                        storyByBusinessId[spot.business?.id ?? spot.id];
                    if (story != null) {
                      Navigator.of(context).pushNamed(
                        AppRoutes.storyViewer,
                        arguments: StoryViewerArgs(storyId: story.id),
                      );
                    }
                  }
                },
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                top: false,
                bottom: false,
                child: DraggableScrollableSheet(
                  initialChildSize: initialSheetSize,
                  minChildSize: minSheetSize,
                  maxChildSize: maxSheetSize,
                  builder: (context, controller) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 28,
                            offset: const Offset(0, -10),
                          ),
                        ],
                      ),
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xxxl,
                        ),
                        children: <Widget>[
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Entdecken',
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      'Gutscheine in deiner Nähe.',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _SheetMetricPill(
                                icon: Icons.storefront_rounded,
                                label: '${visibleSpots.length} Gutscheine',
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (showStatusBar) ...<Widget>[
                            _DiscoverStatusBar(
                              status: publicCouponStatus,
                              areaLabel: area.label,
                              radiusKm: distanceKm,
                              onRefresh: () => ref
                                  .read(
                                    publicCouponRefreshControllerProvider
                                        .notifier,
                                  )
                                  .scheduleRefresh(force: true),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          SizedBox(
                            height: 278,
                            child: PageView.builder(
                              controller: _spotController,
                              itemCount: visibleSpots.length,
                              onPageChanged: (index) {
                                setState(
                                  () =>
                                      _selectedSpotId = visibleSpots[index].id,
                                );
                              },
                              itemBuilder: (context, index) {
                                final spot = visibleSpots[index];
                                final selected = index == selectedIndex;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.sm,
                                  ),
                                  child: _DiscoverSpotCard(
                                    spot: spot,
                                    selected: selected,
                                    onTap: () =>
                                        _openPrimaryAction(context, spot),
                                    onBusinessTap: () =>
                                        _openSecondaryAction(context, spot),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: AnimatedSmoothIndicator(
                              activeIndex: selectedIndex,
                              count: visibleSpots.length,
                              effect: ExpandingDotsEffect(
                                dotHeight: 7,
                                dotWidth: 7,
                                spacing: 6,
                                expansionFactor: 3,
                                activeDotColor: theme.colorScheme.primary,
                                dotColor: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            'Schnell in deiner N\u00E4he',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ...visibleSpots.map((spot) {
                            final selected = spot.id == selectedBusinessId;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: _NearbyDealRow(
                                spot: spot,
                                selected: selected,
                                onTap: () {
                                  setState(() => _selectedSpotId = spot.id);
                                  _openPrimaryAction(context, spot);
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(backgroundColor: const Color(0xFFF8F3EC), body: body);
  }

  List<_DiscoverSpot> _buildFallbackSpots({
    required User user,
    required NearbySearchArea area,
    required double radiusKm,
    required List<Business> businesses,
    required List<Deal> deals,
    required Set<String> storyBusinessIds,
  }) {
    final businessesById = <String, Business>{
      for (final business in businesses) business.id: business,
    };
    final orderedBusinesses = <Business>[];
    final seen = <String>{};

    void addBusinesses(Iterable<Business> values) {
      for (final business in values) {
        if (seen.add(business.id)) {
          orderedBusinesses.add(business);
        }
      }
    }

    final normalizedAreaCity = area.city.trim().toLowerCase();

    addBusinesses(
      businesses.where(
        (business) => business.city.trim().toLowerCase() == normalizedAreaCity,
      ),
    );
    addBusinesses(
      businesses.where(
        (business) => user.followingBusinessIds.contains(business.id),
      ),
    );
    addBusinesses(businesses.where((business) => business.isTrending));
    addBusinesses(businesses);

    final hasCenter =
        area.latitude.isFinite &&
        area.longitude.isFinite &&
        area.latitude.abs() <= 90 &&
        area.longitude.abs() <= 180;
    final centerLatitude = hasCenter
        ? area.latitude
        : (user.latitude ?? 52.5200);
    final centerLongitude = hasCenter
        ? area.longitude
        : (user.longitude ?? 13.4050);
    final normalizedRadiusKm = radiusKm
        .clamp(1.0, maxSearchRadiusKm)
        .toDouble();
    final businessOrder = <String, int>{};
    for (var index = 0; index < orderedBusinesses.length; index++) {
      businessOrder[orderedBusinesses[index].id] = index;
    }

    final candidateDeals = deals
        .where((deal) {
          final business = businessesById[deal.businessId];
          if (business == null) {
            return false;
          }
          final liveDistance = _distanceKm(
            centerLatitude,
            centerLongitude,
            business.primaryBranch.latitude,
            business.primaryBranch.longitude,
          );
          return liveDistance.isFinite && liveDistance <= normalizedRadiusKm;
        })
        .toList(growable: true);

    candidateDeals.sort((a, b) {
      final businessA = businessesById[a.businessId]!;
      final businessB = businessesById[b.businessId]!;

      if (hasCenter) {
        final distanceA = _distanceKm(
          centerLatitude,
          centerLongitude,
          businessA.primaryBranch.latitude,
          businessA.primaryBranch.longitude,
        );
        final distanceB = _distanceKm(
          centerLatitude,
          centerLongitude,
          businessB.primaryBranch.latitude,
          businessB.primaryBranch.longitude,
        );
        final byDistance = distanceA.compareTo(distanceB);
        if (byDistance != 0) {
          return byDistance;
        }
      }

      final rankA = businessOrder[a.businessId] ?? 9999;
      final rankB = businessOrder[b.businessId] ?? 9999;
      final byBusinessRank = rankA.compareTo(rankB);
      if (byBusinessRank != 0) {
        return byBusinessRank;
      }

      return a.distanceKm.compareTo(b.distanceKm);
    });

    return candidateDeals
        .map((deal) {
          final business = businessesById[deal.businessId]!;
          final liveDistance = _distanceKm(
            centerLatitude,
            centerLongitude,
            business.primaryBranch.latitude,
            business.primaryBranch.longitude,
          );
          return _DiscoverSpot.fromBusinessDeal(
            business: business,
            deal: deal,
            distanceKm: liveDistance,
            hasStory: storyBusinessIds.contains(business.id),
          );
        })
        .toList(growable: false);
  }

  Future<void> _openPrimaryAction(
    BuildContext context,
    _DiscoverSpot spot,
  ) async {
    if (spot.deal != null) {
      await Navigator.of(context).pushNamed(
        AppRoutes.dealDetail,
        arguments: DealRouteArgs(spot.deal!.id),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _LivePlaceSheet(
        spot: spot,
        onOpenMaps: () => _launchMaps(context, spot.googleMapsUri),
      ),
    );
  }

  Future<void> _openSecondaryAction(
    BuildContext context,
    _DiscoverSpot spot,
  ) async {
    if (spot.business != null) {
      await Navigator.of(context).pushNamed(
        AppRoutes.businessProfile,
        arguments: BusinessRouteArgs(spot.business!.id),
      );
      return;
    }

    await _launchMaps(context, spot.googleMapsUri);
  }

  Future<void> _launchMaps(BuildContext context, String? mapsUri) async {
    final uri = mapsUri == null ? null : Uri.tryParse(mapsUri);
    if (uri == null) {
      if (!context.mounted) {
        return;
      }
      showAppToast(context, 'Route ist für diesen Ort gerade nicht verfügbar.');
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && context.mounted) {
      showAppToast(context, 'Karten-App konnte nicht geöffnet werden.');
    }
  }

  static Alignment _pinAlignment(int index) {
    const positions = <Alignment>[
      Alignment(-0.58, -0.58),
      Alignment(0.02, -0.72),
      Alignment(0.60, -0.54),
      Alignment(-0.38, -0.24),
      Alignment(0.34, -0.20),
      Alignment(-0.66, -0.02),
      Alignment(0.66, -0.02),
    ];

    return positions[index % positions.length];
  }

  double _distanceKm(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _degToRad(endLat - startLat);
    final deltaLng = _degToRad(endLng - startLng);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(_degToRad(startLat)) *
            math.cos(_degToRad(endLat)) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double degrees) => degrees * 0.017453292519943295;
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState({
    required this.embedded,
    required this.area,
    required this.status,
  });

  final bool embedded;
  final NearbySearchArea area;
  final PublicCouponCacheStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = status.cacheBlocked
        ? Icons.refresh_rounded
        : status.nativeScanInProgress && !status.hasVisibleCoupons
        ? Icons.sync_rounded
        : status.hasVisibleCoupons
        ? Icons.check_circle_rounded
        : Icons.public_rounded;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DiscoveryMapSurface(
            compact: embedded,
            pins: const <DiscoveryMapPin>[],
            focusInitials: 'GO',
            showFocusPulse: false,
            centerLatitude: area.latitude,
            centerLongitude: area.longitude,
            zoom: 12.8,
            searchHint: 'Suche',
            onSearchTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.search),
            onFilterTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.search),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Container(
              margin: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                embedded ? AppSpacing.lg : AppSpacing.xl,
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Entdecken',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Sobald ein sparGO Gutschein in ${_cleanAreaCity(area)} live ist, erscheint er hier mit Karte, Route und Einlösung.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.42),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Icon(
                        statusIcon,
                        size: 14,
                        color: AppColors.primary.withValues(alpha: 0.72),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          status.nativeScanInProgress
                              ? 'Öffentliche Fundstücke werden leise im Hintergrund aktualisiert.'
                              : status.hasVisibleCoupons
                              ? '${status.visibleDealCount} öffentliche Fundstücke zusätzlich verfügbar.'
                              : 'Öffentliche Fundstücke laufen nur als Zusatz mit.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B5C61),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.search),
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Zur Suche'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _cleanAreaCity(NearbySearchArea area) {
  final city = area.city.trim();
  if (city.isNotEmpty && city != 'Deutschlandweit') {
    return city;
  }
  final label = area.label
      .replaceAll('Dein Viertel,', '')
      .replaceAll('Dein Viertel', '')
      .trim();
  return label.isEmpty ? 'deiner Nähe' : label;
}

class _DiscoverStatusBar extends StatelessWidget {
  const _DiscoverStatusBar({
    required this.status,
    required this.areaLabel,
    required this.radiusKm,
    required this.onRefresh,
  });

  final PublicCouponCacheStatus status;
  final String areaLabel;
  final double radiusKm;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = status.cacheBlocked
        ? Icons.refresh_rounded
        : status.nativeScanInProgress
        ? Icons.sync_rounded
        : status.hasVisibleCoupons
        ? Icons.check_circle_rounded
        : Icons.public_rounded;
    final showPercent =
        status.nativeScanInProgress || status.hasMeasuredProgress;
    final headline = status.cacheBlocked
        ? 'Öffentliche Quellen werden neu verbunden'
        : status.nativeScanInProgress
        ? status.hasVisibleCoupons
              ? '${status.visibleDealCount} sichtbar, weitere folgen gerade'
              : 'Öffentliche Coupons werden geladen'
        : '${status.visibleDealCount} Öffentliche Coupons sichtbar';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFDCE4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(statusIcon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  headline,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: showPercent ? status.syncProgress : null,
                          backgroundColor: const Color(0xFFFFE6EC),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      showPercent
                          ? '${status.syncProgressPercent}%'
                          : status.hasVisibleCoupons
                          ? 'bereit'
                          : 'aktiv',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_cleanCouponStatusText(areaLabel)} · ${radiusKm.round()} km',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: status.nativeScanInProgress ? null : onRefresh,
            child: Text(
              status.nativeScanInProgress
                  ? 'Aktiv'
                  : status.hasVisibleCoupons
                  ? 'Aktualisiert'
                  : 'Neu laden',
            ),
          ),
        ],
      ),
    );
  }
}

String _cleanCouponStatusText(String value) {
  return value
      .replaceAll('Ã¤', 'ä')
      .replaceAll('Ã¶', 'ö')
      .replaceAll('Ã¼', 'ü')
      .replaceAll('Ã„', 'Ä')
      .replaceAll('Ã–', 'Ö')
      .replaceAll('ÃŒ', 'Ü')
      .replaceAll('ÃŸ', 'ß')
      .replaceAll('Â·', '·')
      .replaceAll('Â', '');
}

String? _discoverSpotImageUrl(WidgetRef ref, _DiscoverSpot spot) {
  final deal = spot.deal;
  final business = spot.business;
  if (deal != null && business != null) {
    return webSafeImageUrl(
      ref
              .watch(
                dealPresentationImageUrlProvider((
                  businessId: business.id,
                  dealId: deal.id,
                )),
              )
              .valueOrNull ??
          spot.photoUrl,
    );
  }
  return webSafeImageUrl(spot.photoUrl);
}

class _DiscoverSpot {
  const _DiscoverSpot({
    required this.id,
    required this.name,
    required this.title,
    required this.address,
    required this.categoryLabel,
    required this.distanceKm,
    required this.savingsPercent,
    required this.rating,
    required this.latitude,
    required this.longitude,
    required this.initials,
    required this.palette,
    required this.supportingText,
    this.hasStory = false,
    this.photoUrl,
    this.googleMapsUri,
    this.openNow,
    this.business,
    this.deal,
  });

  factory _DiscoverSpot.fromBusinessDeal({
    required Business business,
    required Deal deal,
    double? distanceKm,
    bool hasStory = false,
  }) {
    return _DiscoverSpot(
      id: deal.id,
      name: business.name,
      title: deal.title,
      address: business.primaryBranch.address,
      categoryLabel: business.category.label,
      distanceKm: distanceKm ?? deal.distanceKm,
      savingsPercent: deal.savingsPercent,
      rating: business.rating,
      latitude: business.primaryBranch.latitude,
      longitude: business.primaryBranch.longitude,
      initials: _initialsFor(business.name),
      palette: business.coverPalette,
      supportingText: deal.socialProof,
      hasStory: hasStory,
      openNow: deal.openNow,
      business: business,
      deal: deal,
      photoUrl: deal.imageUrl.trim().isEmpty
          ? business.imageUrl
          : deal.imageUrl,
    );
  }

  factory _DiscoverSpot.fromNearbyPlace({
    required NearbyPlace place,
    required NearbySearchArea area,
  }) {
    return _DiscoverSpot(
      id: place.id,
      name: place.name,
      title: 'Öffentlicher Ort in deiner Nähe',
      address: place.address.isEmpty ? area.label : place.address,
      categoryLabel: place.category.label,
      distanceKm: place.distanceKmFrom(area),
      savingsPercent: 0,
      rating: place.rating,
      latitude: place.latitude,
      longitude: place.longitude,
      initials: place.initials,
      palette: place.palette,
      supportingText:
          'Kostenlos aus öffentlichen Ortsdaten übernommen. Unternehmen können hier später eigene Gutscheine und Stories veröffentlichen.',
      photoUrl: place.photoUrl,
      googleMapsUri: place.googleMapsUri,
      openNow: place.openNow,
    );
  }

  final String id;
  final String name;
  final String title;
  final String address;
  final String categoryLabel;
  final double distanceKm;
  final int savingsPercent;
  final double rating;
  final double latitude;
  final double longitude;
  final String initials;
  final List<int> palette;
  final String supportingText;
  final bool hasStory;
  final String? photoUrl;
  final String? googleMapsUri;
  final bool? openNow;
  final Business? business;
  final Deal? deal;

  bool get isLivePlace => deal == null || business == null;
  bool get isPublicCoupon => deal?.isThirdParty ?? false;

  String get primaryActionLabel => isLivePlace ? 'Zum Ort' : 'Zum Deal';

  String get availabilityLabel => openNow == null
      ? categoryLabel
      : openNow!
      ? 'Jetzt offen'
      : 'Gerade geschlossen';

  static String _initialsFor(String value) {
    final parts = value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'SP';
    }
    return parts.map((part) => part.characters.first).join().toUpperCase();
  }
}

class _SheetMetricPill extends StatelessWidget {
  const _SheetMetricPill({required this.icon, required this.label});

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
        color: const Color(0xFFFFE8ED),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _DiscoverSpotCard extends ConsumerWidget {
  const _DiscoverSpotCard({
    required this.spot,
    required this.selected,
    required this.onTap,
    required this.onBusinessTap,
  });

  final _DiscoverSpot spot;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onBusinessTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewImageUrl = _discoverSpotImageUrl(ref, spot);
    final savingsLabel = spot.isLivePlace
        ? 'Ort'
        : (spot.savingsPercent > 0 ? '${spot.savingsPercent}%' : 'Deal');

    return ShowcaseCouponCard(
      highlighted: selected,
      title: spot.title,
      subtitle: spot.supportingText.isEmpty
          ? spot.address
          : spot.supportingText,
      businessName: spot.name,
      imageUrl: previewImageUrl,
      highlightLabel: savingsLabel,
      topBadges: <String>[
        spot.categoryLabel,
        spot.isPublicCoupon ? 'öffentlich' : 'sparGO',
        if (spot.hasStory) 'Story live',
      ],
      statusLabel: spot.isLivePlace || spot.openNow == null
          ? null
          : spot.availabilityLabel,
      statusIcon: spot.openNow == true
          ? Icons.check_circle_rounded
          : Icons.schedule_rounded,
      statusColor: spot.openNow == true
          ? const Color(0xFF2F9E63)
          : const Color(0xFFB46B1F),
      metrics: <ShowcaseCouponCardMetric>[
        ShowcaseCouponCardMetric(
          icon: Icons.place_rounded,
          label: '${spot.distanceKm.toStringAsFixed(1)} km',
        ),
        ShowcaseCouponCardMetric(
          icon: Icons.star_rounded,
          label: spot.rating == 0 ? 'Neu' : spot.rating.toStringAsFixed(1),
        ),
      ],
      primaryActionLabel: spot.primaryActionLabel,
      onTap: onTap,
      onSecondaryTap: onBusinessTap,
      secondaryIcon: spot.isLivePlace
          ? Icons.near_me_rounded
          : Icons.storefront_rounded,
      heroHeight: 112,
    );
  }
}

class _SpotMetaPill extends StatelessWidget {
  const _SpotMetaPill({required this.icon, required this.label});

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
        color: const Color(0xFFFFF3F6),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: const Color(0xFFFFDCE4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.secondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyDealRow extends ConsumerWidget {
  const _NearbyDealRow({
    required this.spot,
    required this.selected,
    required this.onTap,
  });

  final _DiscoverSpot spot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewImageUrl = _discoverSpotImageUrl(ref, spot);

    return ShowcaseCouponCard(
      highlighted: selected,
      title: spot.title,
      subtitle: spot.supportingText.isEmpty
          ? spot.address
          : spot.supportingText,
      businessName: spot.name,
      imageUrl: previewImageUrl,
      highlightLabel: spot.isLivePlace
          ? 'Ort'
          : (spot.savingsPercent > 0 ? '${spot.savingsPercent}%' : 'Deal'),
      topBadges: <String>[
        spot.categoryLabel,
        spot.isPublicCoupon ? 'öffentlich' : 'sparGO',
        if (spot.hasStory) 'Story live',
      ],
      statusLabel: spot.isLivePlace || spot.openNow == null
          ? null
          : spot.availabilityLabel,
      statusIcon: spot.openNow == true
          ? Icons.check_circle_rounded
          : Icons.schedule_rounded,
      statusColor: spot.openNow == true
          ? const Color(0xFF2F9E63)
          : const Color(0xFFB46B1F),
      metrics: <ShowcaseCouponCardMetric>[
        ShowcaseCouponCardMetric(
          icon: Icons.place_rounded,
          label: '${spot.distanceKm.toStringAsFixed(1)} km',
        ),
        ShowcaseCouponCardMetric(
          icon: Icons.star_rounded,
          label: spot.rating == 0 ? 'Neu' : spot.rating.toStringAsFixed(1),
        ),
        if (spot.hasStory)
          const ShowcaseCouponCardMetric(
            icon: Icons.play_circle_fill_rounded,
            label: 'Story',
          ),
      ],
      primaryActionLabel: spot.primaryActionLabel,
      onTap: onTap,
      heroHeight: 104,
    );
  }
}

class _SpotThumbnail extends StatelessWidget {
  const _SpotThumbnail({
    required this.spot,
    required this.accent,
    this.imageUrl,
  });

  final _DiscoverSpot spot;
  final Color accent;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = webSafeImageUrl(imageUrl);

    return Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.24),
          width: 2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent,
            Color.lerp(accent, Colors.white, 0.28) ?? accent,
          ],
        ),
      ),
      child: resolvedImageUrl == null
          ? Center(
              child: Text(
                spot.initials,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Image.network(
              resolvedImageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    spot.initials,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _MiniDiscoverBadge extends StatelessWidget {
  const _MiniDiscoverBadge({required this.label});

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
        color: const Color(0xFFFFF0F4),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: const Color(0xFFFFDDE5)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LivePlaceSheet extends StatelessWidget {
  const _LivePlaceSheet({required this.spot, required this.onOpenMaps});

  final _DiscoverSpot spot;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = spot.palette.map(Color.new).toList(growable: false);
    final start = colors.isEmpty ? AppColors.primary : colors.first;
    final end = colors.length > 1 ? colors[1] : start;
    final resolvedImageUrl = webSafeImageUrl(spot.photoUrl);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 188,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[start, end],
                ),
              ),
              child: resolvedImageUrl == null
                  ? Center(
                      child: Text(
                        spot.initials,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.network(
                          resolvedImageUrl,
                          fit: BoxFit.cover,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.fallback,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                spot.initials,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          },
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.black.withValues(alpha: 0.08),
                                Colors.black.withValues(alpha: 0.42),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              spot.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(spot.title, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _SheetTag(label: spot.categoryLabel),
                _SheetTag(label: spot.availabilityLabel),
                _SheetTag(
                  label: spot.rating == 0
                      ? 'Neu'
                      : '${spot.rating.toStringAsFixed(1)} Sterne',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(spot.address, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              spot.supportingText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.near_me_rounded),
                    label: const Text('Route starten'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Schließen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTag extends StatelessWidget {
  const _SheetTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF2),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.secondary),
      ),
    );
  }
}
