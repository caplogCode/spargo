import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/mock_qr_painter.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';

class BusinessRedemptionsScreen extends ConsumerStatefulWidget {
  const BusinessRedemptionsScreen({super.key});

  @override
  ConsumerState<BusinessRedemptionsScreen> createState() =>
      _BusinessRedemptionsScreenState();
}

class _BusinessRedemptionsScreenState
    extends ConsumerState<BusinessRedemptionsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final business = ref.watch(ownedBusinessProvider);
    final query = _searchController.text.trim().toLowerCase();
    final rawItems = ref.watch(businessRedemptionsProvider);
    final items =
        rawItems
            .where((redemption) {
              if (query.isEmpty) {
                return true;
              }
              final deal = ref.read(dealByIdProvider(redemption.dealId));
              final haystack = <String>[
                redemption.couponId,
                redemption.code,
                redemption.qrPayload,
                deal.title,
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            })
            .toList(growable: false)
          ..sort((a, b) => b.activatedAt.compareTo(a.activatedAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Einlösungen')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: theme.dividerColor),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Codes & QR-Pässe',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Sobald Nutzer einen Gutschein aktivieren, siehst du hier Coupon-ID, Code und QR direkt für ${business.name}.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: context.t(
                        'Coupon-ID, Code oder Gutschein suchen',
                      ),
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          rawItems.isEmpty
                              ? 'Sobald Kund:innen Gutscheine aktivieren oder einlösen, erscheinen sie hier.'
                              : 'Für diese Suche wurde noch kein passender Pass gefunden.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final redemption = items[index];
                        final deal = ref.read(
                          dealByIdProvider(redemption.dealId),
                        );
                        return _RedemptionCard(
                          redemption: redemption,
                          deal: deal,
                          onTap: () => _openRedemptionSheet(
                            context: context,
                            business: business,
                            redemption: redemption,
                            deal: deal,
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

  Future<void> _openRedemptionSheet({
    required BuildContext context,
    required Business business,
    required Redemption redemption,
    required Deal deal,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Padding(
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
              Text(
                deal.title,
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${redemption.couponId} · ${redemption.code}',
                style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Container(
                  width: 228,
                  height: 228,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: MockQrPainter(redemption.qrPayload),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  _DetailPill(
                    icon: Icons.schedule_rounded,
                    label: _dateLabel(redemption.activatedAt),
                  ),
                  _DetailPill(
                    icon: Icons.event_available_rounded,
                    label: _dateLabel(redemption.expiresAt),
                  ),
                  _DetailPill(
                    icon: Icons.verified_rounded,
                    label: redemption.status.label,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Beim Einlösen reicht der QR, die Coupon-ID oder der Code. Das Geschäft muss nichts selbst erzeugen.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: redemption.status == RedemptionStatus.active
                          ? () async {
                              try {
                                await ref
                                    .read(repositoryProvider)
                                    .redeemRedemptionFromBusiness(
                                      business: business,
                                      redemption: redemption,
                                    );
                                if (!mounted) {
                                  return;
                                }
                                Navigator.of(sheetContext).pop();
                              } on Exception catch (error) {
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Pass konnte nicht als eingelöst markiert werden: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          : null,
                      child: Text(
                        redemption.status == RedemptionStatus.active
                            ? 'Als eingelöst markieren'
                            : 'Bereits eingelöst',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Schließen'),
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

  String _dateLabel(DateTime value) {
    return '${value.day}.${value.month}.${value.year}';
  }
}

class _RedemptionCard extends StatelessWidget {
  const _RedemptionCard({
    required this.redemption,
    required this.deal,
    required this.onTap,
  });

  final Redemption redemption;
  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = redemption.status == RedemptionStatus.active;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.dividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEF2),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Icon(
                  active ? Icons.qr_code_2_rounded : Icons.verified_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${redemption.couponId} · ${redemption.code}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFFFE8ED)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  redemption.status.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: active
                        ? AppColors.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.icon, required this.label});

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
        color: const Color(0xFFFFEFF3),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(label),
        ],
      ),
    );
  }
}
