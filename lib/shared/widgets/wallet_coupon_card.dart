import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/utils/mock_qr_painter.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../theme/app_colors.dart';

class WalletCouponCard extends StatelessWidget {
  const WalletCouponCard({
    super.key,
    required this.deal,
    required this.business,
    required this.redemption,
    this.focused = true,
    this.compact = false,
    this.onTap,
  });

  final Deal deal;
  final Business business;
  final Redemption redemption;
  final bool focused;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = compact ? 28.0 : 34.0;
    final cardHeight = compact ? 212.0 : 408.0;
    final cutoutTop = cardHeight * (compact ? 0.58 : 0.62);
    final qrSize = compact ? 68.0 : 82.0;
    final padding = compact ? AppSpacing.md : AppSpacing.lg;

    return SizedBox(
      height: cardHeight,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: AnimatedContainer(
                  duration: AppDurations.medium,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    color: AppColors.primary,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: focused ? 0.24 : 0.16,
                      ),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: focused ? 0.26 : 0.16,
                        ),
                        blurRadius: focused ? 34 : 20,
                        spreadRadius: focused ? 2 : 0,
                        offset: Offset(0, focused ? 20 : 12),
                      ),
                      BoxShadow(
                        color: AppColors.highlightMid.withValues(
                          alpha: focused ? 0.12 : 0.06,
                        ),
                        blurRadius: focused ? 54 : 26,
                        spreadRadius: focused ? 4 : 1,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -16,
                top: cutoutTop,
                child: _PassCutout(color: theme.scaffoldBackgroundColor),
              ),
              Positioned(
                right: -16,
                top: cutoutTop,
                child: _PassCutout(color: theme.scaffoldBackgroundColor),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        right: compact ? -28 : -34,
                        top: compact ? -24 : -30,
                        child: Opacity(
                          opacity: 0.12,
                          child: Image.asset(
                            'assets/branding/spargo_splashscreen.png',
                            width: compact ? 156 : 214,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Container(
                                          width: compact ? 22 : 26,
                                          height: compact ? 22 : 26,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.wallet_membership_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Text(
                                          'sparGO Pass',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.88,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      business.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              _PassStatusChip(
                                label: redemption.status.label,
                                active:
                                    redemption.status ==
                                    RedemptionStatus.active,
                              ),
                            ],
                          ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          Text(
                            deal.title,
                            maxLines: compact ? 2 : 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? theme.textTheme.titleLarge
                                        : theme.textTheme.headlineSmall)
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      height: 1.04,
                                    ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            compact
                                ? deal.priceHint
                                : '${deal.priceHint} - ${deal.socialProof}',
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              height: 1.35,
                            ),
                          ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: <Widget>[
                              _PassMetaChip(
                                icon: Icons.schedule_rounded,
                                label: _formatExpiry(redemption),
                              ),
                              _PassMetaChip(
                                icon: Icons.local_offer_outlined,
                                label: deal.savingsHighlightLabel,
                              ),
                              _PassMetaChip(
                                icon: Icons.cloud_done_outlined,
                                label: redemption.offlineReady
                                    ? 'Offline bereit'
                                    : 'Nur online',
                              ),
                            ],
                          ),
                          const Spacer(),
                          const _PassDivider(),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.lg,
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      'Code',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.76,
                                            ),
                                          ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      redemption.code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          (compact
                                                  ? theme.textTheme.titleMedium
                                                  : theme.textTheme.titleLarge)
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      redemption.couponId,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.88,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      redemption.instructions,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.76,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              _QrPlate(
                                size: qrSize,
                                code: redemption.qrPayload,
                                onTap: () => _showQrPreview(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatExpiry(Redemption redemption) {
    final date = redemption.expiresAt;
    return '${date.day}.${date.month}.${date.year}';
  }

  Future<void> _showQrPreview(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  deal.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  business.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _QrPlate(size: 228, code: redemption.qrPayload),
                const SizedBox(height: AppSpacing.md),
                Text(
                  redemption.code,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  redemption.couponId,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Schließen'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PassStatusChip extends StatelessWidget {
  const _PassStatusChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _PassMetaChip extends StatelessWidget {
  const _PassMetaChip({required this.icon, required this.label});

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
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _QrPlate extends StatelessWidget {
  const _QrPlate({required this.size, required this.code, this.onTap});

  final double size;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          height: size,
          width: size,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: CustomPaint(painter: MockQrPainter(code)),
        ),
      ),
    );
  }
}

class _PassCutout extends StatelessWidget {
  const _PassCutout({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PassDivider extends StatelessWidget {
  const _PassDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(22, (index) {
        return Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            color: Colors.white.withValues(alpha: index.isEven ? 0.48 : 0.16),
          ),
        );
      }),
    );
  }
}
