import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/compact_deal_card.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void initState() {
    super.initState();
    final searchController = ref.read(searchControllerProvider.notifier);
    searchController.updateQuery(widget.initialQuery);
    searchController.setDistance(
      ref.read(settingsControllerProvider).distanceKm,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final settingsDistanceKm = ref.watch(settingsControllerProvider).distanceKm;
    final sliderMaxDistanceKm = settingsDistanceKm <= minSearchRadiusKm
        ? minSearchRadiusKm + 5
        : settingsDistanceKm;
    final effectiveDistanceKm = search.maxDistanceKm.clamp(
      minSearchRadiusKm,
      settingsDistanceKm,
    );
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ergebnisse')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _controller,
                  onChanged: ref
                      .read(searchControllerProvider.notifier)
                      .updateQuery,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: context.t('Suche verfeinern'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      FilterChip(
                        selected: search.onlyToday,
                        label: const Text('Nur heute'),
                        onSelected: ref
                            .read(searchControllerProvider.notifier)
                            .toggleToday,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilterChip(
                        selected: search.onlyExclusive,
                        label: const Text('Exklusiv'),
                        onSelected: ref
                            .read(searchControllerProvider.notifier)
                            .toggleExclusive,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilterChip(
                        selected: search.openNowOnly,
                        label: const Text('Offen jetzt'),
                        onSelected: ref
                            .read(searchControllerProvider.notifier)
                            .toggleOpenNow,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilterChip(
                        selected: search.popularOnly,
                        label: const Text('Beliebt'),
                        onSelected: ref
                            .read(searchControllerProvider.notifier)
                            .togglePopular,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Distanz bis ${effectiveDistanceKm.toStringAsFixed(0)} km',
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(searchControllerProvider.notifier)
                          .setDistance(settingsDistanceKm),
                      child: const Text('Max'),
                    ),
                  ],
                ),
                Slider(
                  value: effectiveDistanceKm.toDouble(),
                  min: minSearchRadiusKm,
                  max: sliderMaxDistanceKm,
                  divisions: ((sliderMaxDistanceKm - minSearchRadiusKm) / 5)
                      .clamp(1, 1000)
                      .round(),
                  label: '${effectiveDistanceKm.toStringAsFixed(0)} km',
                  onChanged: settingsDistanceKm <= minSearchRadiusKm
                      ? null
                      : ref.read(searchControllerProvider.notifier).setDistance,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: results.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final deal = results[index];
                final business = ref.read(
                  businessByIdProvider(deal.businessId),
                );
                return CompactDealCard(
                  deal: deal,
                  business: business,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.dealDetail,
                    arguments: DealRouteArgs(deal.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
