import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/services/secure_screen_service.dart';
import '../../../../core/widgets/empty_state_card.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../domain/models/notification_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/wallet_coupon_card.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key, this.embedded = false, this.initialTab = 0});

  final bool embedded;
  final int initialTab;

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  late final PageController _pageController = PageController(
    viewportFraction: 0.92,
    initialPage: widget.initialTab,
  );

  late int _selectedPage = widget.initialTab;
  int _segment = 0;
  bool _secureModeEnabled = false;

  @override
  void dispose() {
    if (_secureModeEnabled) {
      unawaited(SecureScreenService.instance.disable());
    }
    _pageController.dispose();
    super.dispose();
  }

  void _syncSecureMode(bool enabled) {
    if (_secureModeEnabled == enabled) {
      return;
    }
    _secureModeEnabled = enabled;
    if (enabled) {
      unawaited(SecureScreenService.instance.enable());
      return;
    }
    unawaited(SecureScreenService.instance.disable());
  }

  Future<void> _openRedeemConfirmation({
    required BuildContext context,
    required Redemption redemption,
    required Deal deal,
    required Business business,
  }) async {
    final amountController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return AnimatedPadding(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Einlösung bestätigen',
                    style: Theme.of(sheetContext).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${deal.title} bei ${business.name} wird ins Archiv verschoben.',
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          height: 1.4,
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Wie viel hast du gespart?',
                      hintText: 'z. B. 12,50',
                      prefixText: '€ ',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Der Betrag füllt dein sparGO-Sparschwein im Coupon-Tab. Du kannst auch 0 eintragen, wenn du den Wert nicht kennst.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Abbrechen'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final savedAmountCents = _parseEuroCents(
                              amountController.text,
                            );
                            await ref
                                .read(walletProvider.notifier)
                                .markRedeemed(
                                  redemption.id,
                                  savedAmountCents: savedAmountCents,
                                );
                            await ref
                                .read(notificationsProvider.notifier)
                                .add(
                                  NotificationItem(
                                    id: 'wallet_redeemed_${redemption.id}',
                                    title: 'Pass eingelöst',
                                    body:
                                        '${deal.title} wurde verbindlich eingelöst und liegt jetzt im Archiv.',
                                    timeLabel: 'Jetzt',
                                    type: NotificationType.loyalty,
                                    isRead: false,
                                    dealId: deal.id,
                                    businessId: business.id,
                                  ),
                                );
                            if (!sheetContext.mounted || !context.mounted) {
                              return;
                            }
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  savedAmountCents > 0
                                      ? '${redemption.couponId} eingelöst. ${_formatEuroCents(savedAmountCents)} im Sparschwein gespeichert.'
                                      : '${redemption.couponId} wurde eingelöst.',
                                ),
                              ),
                            );
                          },
                          child: const Text('Eingelöst markieren'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    amountController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = ref.watch(activeWalletProvider);
    final history = ref.watch(walletHistoryProvider);
    final totalSavedCents = ref.watch(totalSavedAmountCentsProvider);
    final hasActive = active.isNotEmpty;
    final selectedIndex = hasActive
        ? _selectedPage.clamp(0, active.length - 1)
        : 0;
    final selectedRedemption = hasActive ? active[selectedIndex] : null;
    final selectedDeal = selectedRedemption == null
        ? null
        : ref.watch(dealByIdProvider(selectedRedemption.dealId));
    final selectedBusiness = selectedDeal == null
        ? null
        : ref.watch(businessByIdProvider(selectedDeal.businessId));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncSecureMode(hasActive);
    });

    final body = CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _WalletHeader(
                activeCount: active.length,
                historyCount: history.length,
                segment: _segment,
                statusLabel: hasActive && selectedRedemption != null
                    ? _expiryLabel(selectedRedemption)
                    : 'Bereit für neue Deals',
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: _WalletSegmentControl(
              selectedIndex: _segment,
              labels: const <String>['Aktiv', 'Archiv'],
              onChanged: (index) => setState(() => _segment = index),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: _SavingsPiggyCard(
              totalSavedCents: totalSavedCents,
              redeemedCount: history
                  .where((item) => item.status == RedemptionStatus.redeemed)
                  .length,
            ),
          ),
        ),
        if (_segment == 0)
          ..._buildActiveSlivers(
            context: context,
            active: active,
            selectedIndex: selectedIndex,
            selectedDeal: selectedDeal,
            selectedBusiness: selectedBusiness,
            selectedRedemption: selectedRedemption,
          )
        else
          ..._buildArchiveSlivers(context: context, history: history),
      ],
    );

    if (widget.embedded) {
      return Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: body,
    );
  }

  List<Widget> _buildActiveSlivers({
    required BuildContext context,
    required List<Redemption> active,
    required int selectedIndex,
    required Deal? selectedDeal,
    required Business? selectedBusiness,
    required Redemption? selectedRedemption,
  }) {
    if (active.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: EmptyStateCard(
              icon: Icons.wallet_outlined,
              title: 'Noch kein aktiver Pass',
              subtitle:
                  'Sobald du einen Gutschein aktivierst, liegt er hier wie ein echter Pass bereit.',
              action: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.search),
                child: const Text('Deals entdecken'),
              ),
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: _WalletDeck(
            items: active,
            selectedIndex: selectedIndex,
            pageController: _pageController,
            itemBuilder: (context, index, focused) {
              final redemption = active[index];
              final deal = ref.watch(dealByIdProvider(redemption.dealId));
              final business = ref.watch(businessByIdProvider(deal.businessId));

              return WalletCouponCard(
                deal: deal,
                business: business,
                redemption: redemption,
                focused: focused,
                onTap: () => _pageController.animateToPage(
                  index,
                  duration: AppDurations.medium,
                  curve: Curves.easeOutCubic,
                ),
              );
            },
            onPageChanged: (index) {
              if (_selectedPage != index) {
                setState(() => _selectedPage = index);
              }
            },
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Center(
            child: AnimatedSmoothIndicator(
              activeIndex: selectedIndex,
              count: active.length,
              effect: ExpandingDotsEffect(
                dotHeight: 7,
                dotWidth: 7,
                spacing: 6,
                expansionFactor: 3,
                activeDotColor: Theme.of(context).colorScheme.secondary,
                dotColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
      if (selectedRedemption != null &&
          selectedDeal != null &&
          selectedBusiness != null) ...<Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _WalletQuickActions(
              onRedeem: () => _openRedeemConfirmation(
                context: context,
                redemption: selectedRedemption,
                deal: selectedDeal,
                business: selectedBusiness,
              ),
              onBusinessTap: () => Navigator.of(context).pushNamed(
                AppRoutes.businessProfile,
                arguments: BusinessRouteArgs(selectedBusiness.id),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            child: _WalletFocusCard(
              deal: selectedDeal,
              business: selectedBusiness,
              redemption: selectedRedemption,
            ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.03, end: 0),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildArchiveSlivers({
    required BuildContext context,
    required List<Redemption> history,
  }) {
    if (history.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            child: EmptyStateCard(
              icon: Icons.history_rounded,
              title: 'Noch kein Archiv',
              subtitle:
                  'Eingelöste oder abgelaufene Gutscheine tauchen hier als ruhige Historie auf.',
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Text(
            'Vergangene Pässe',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: history.length,
        itemBuilder: (context, index) {
          final redemption = history[index];
          final deal = ref.watch(dealByIdProvider(redemption.dealId));
          final business = ref.watch(businessByIdProvider(deal.businessId));

          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: WalletCouponCard(
              deal: deal,
              business: business,
              redemption: redemption,
              compact: true,
            ),
          );
        },
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
    ];
  }
}

class _SavingsPiggyCard extends StatelessWidget {
  const _SavingsPiggyCard({
    required this.totalSavedCents,
    required this.redeemedCount,
  });

  final int totalSavedCents;
  final int redeemedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (totalSavedCents / 10000).clamp(0.08, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF5F7), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFDCE5)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFE91E63).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.92 + (value * 0.08),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE5EC),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.savings_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Positioned(
                        right: 13,
                        top: 13,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFB300),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'sparGO-Sparschwein',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatEuroCents(totalSavedCents),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  redeemedCount == 0
                      ? 'Markiere eingelöste Gutscheine und trage deinen gesparten Betrag ein.'
                      : '$redeemedCount eingelöste Gutscheine mit Sparbetrag.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0);
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({
    required this.activeCount,
    required this.historyCount,
    required this.segment,
    required this.statusLabel,
  });

  final int activeCount;
  final int historyCount;
  final int segment;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Text(
                  segment == 0 ? 'Aktive Pässe' : 'Archiv',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Wallet',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                segment == 0
                    ? '$activeCount aktiv für jetzt'
                    : '$historyCount bereits genutzt',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.dividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                statusLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                segment == 0 ? 'Im Fokus' : 'Historie',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletSegmentControl extends StatelessWidget {
  const _WalletSegmentControl({
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: List<Widget>.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.secondary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WalletDeck extends StatelessWidget {
  const _WalletDeck({
    required this.items,
    required this.selectedIndex,
    required this.pageController,
    required this.itemBuilder,
    required this.onPageChanged,
  });

  final List<Redemption> items;
  final int selectedIndex;
  final PageController pageController;
  final Widget Function(BuildContext context, int index, bool focused)
  itemBuilder;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 506,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          for (var depth = 2; depth >= 1; depth--)
            if (selectedIndex + depth < items.length)
              Positioned(
                top: 24.0 * depth,
                left: 24.0 + (depth * 7),
                right: 24.0 + (depth * 7),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: depth == 1 ? 0.28 : 0.16,
                    child: Transform.scale(
                      scale: depth == 1 ? 0.95 : 0.90,
                      child: itemBuilder(context, selectedIndex + depth, false),
                    ),
                  ),
                ),
              ),
          PageView.builder(
            controller: pageController,
            itemCount: items.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final focused = index == selectedIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: AnimatedSlide(
                  duration: AppDurations.fast,
                  curve: Curves.easeOutCubic,
                  offset: focused ? Offset.zero : const Offset(0, 0.03),
                  child: AnimatedScale(
                    duration: AppDurations.fast,
                    curve: Curves.easeOutCubic,
                    scale: focused ? 1 : 0.97,
                    child: itemBuilder(context, index, focused),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WalletQuickActions extends StatelessWidget {
  const _WalletQuickActions({
    required this.onRedeem,
    required this.onBusinessTap,
  });

  final VoidCallback onRedeem;
  final VoidCallback onBusinessTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: onRedeem,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const <Widget>[
                  Icon(Icons.check_circle_outline_rounded, size: 18),
                  SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Eingelöst markieren',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: onBusinessTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const <Widget>[
                  Icon(Icons.storefront_outlined, size: 18),
                  SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Mehr dazu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _WalletFocusCard extends StatelessWidget {
  const _WalletFocusCard({
    required this.deal,
    required this.business,
    required this.redemption,
  });

  final Deal deal;
  final Business business;
  final Redemption redemption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildRow(String label, String value, {bool emphasized = false}) {
      final style = emphasized
          ? theme.textTheme.titleMedium
          : theme.textTheme.bodyMedium;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: style?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.dividerColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Pass Details',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  deal.type.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        deal.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(business.name, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    deal.savingsHighlightLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          buildRow('Angebot', deal.title),
          buildRow('Laden', business.name),
          buildRow('Adresse', business.primaryBranch.address),
          buildRow('Code', redemption.code, emphasized: true),
          buildRow('Gutschein-ID', redemption.couponId, emphasized: true),
          buildRow(
            'Offline',
            redemption.offlineReady
                ? 'Vollständig gespeichert, auch ohne Netz vorzeigbar'
                : 'Online-Verbindung empfohlen',
          ),
          buildRow(
            'Gültig bis',
            '${redemption.expiresAt.day}.${redemption.expiresAt.month}.${redemption.expiresAt.year}',
          ),
          buildRow('Einlösen', redemption.instructions),
        ],
      ),
    );
  }
}

String _expiryLabel(Redemption redemption) {
  final now = DateTime.now();
  final difference = redemption.expiresAt.difference(now).inDays;
  if (difference <= 0) {
    return 'Läuft heute aus';
  }
  if (difference == 1) {
    return 'Endet morgen';
  }
  return '$difference Tage Rest';
}

int _parseEuroCents(String value) {
  final normalized = value
      .trim()
      .replaceAll('€', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 0;
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isNegative) {
    return 0;
  }
  return (parsed * 100).round().clamp(0, 999999999);
}

String _formatEuroCents(int cents) {
  final value = cents / 100;
  return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
}
