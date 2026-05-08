import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/user_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_shadows.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final isBusiness = user.accountType == AccountType.business;
    final savedCount = ref.watch(savedDealsProvider).length;
    final activeCount = ref.watch(activeWalletProvider).length;
    final level = ref.watch(userLevelProvider);

    final content = ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: _ProfileHeroCard(
            name: user.name,
            handle: user.handle,
            city: user.city,
            district: user.district,
            points: user.points,
            freeCouponCredits: user.freeCouponCredits,
            savedCount: savedCount,
            activeCount: activeCount,
            level: level,
            initials: user.avatarInitials,
          ),
        ),
        const _SectionTitle(title: 'Konto'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _ActionGroup(
            children: <Widget>[
              _ProfileAction(
                icon: Icons.edit_outlined,
                title: 'Profil bearbeiten',
                subtitle: 'Name, Nickname, Standort und Interessen anpassen',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.editProfile),
              ),
              _ProfileAction(
                icon: Icons.settings_outlined,
                title: 'Einstellungen',
                subtitle: 'Benachrichtigungen und Distanzsteuerung',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(title: 'Community'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _ActionGroup(
            children: <Widget>[
              _ProfileAction(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Freunde einladen',
                subtitle: 'Deals gemeinsam entdecken und teilen',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.inviteFriends),
              ),
              _ProfileAction(
                icon: Icons.workspace_premium_outlined,
                title: 'Perks',
                subtitle: 'Punkte, freie Gutscheine und Belohnungen',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.rewards),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(title: 'Rechtliches'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _ActionGroup(
            children: <Widget>[
              _ProfileAction(
                icon: Icons.gavel_rounded,
                title: 'Rechtliches',
                subtitle: 'Datenschutz, Impressum und Open-Source-Lizenzen',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.legal),
              ),
            ],
          ),
        ),
        if (isBusiness) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const _SectionTitle(title: 'Business'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _ActionGroup(
              children: <Widget>[
                _ProfileAction(
                  icon: Icons.storefront_outlined,
                  title: 'Business Dashboard',
                  subtitle: 'Deals, Stories und Reichweite verwalten',
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.businessDashboard),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final wrapped = SafeArea(top: true, bottom: false, child: content);

    if (embedded) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: wrapped,
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: wrapped,
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.handle,
    required this.city,
    required this.district,
    required this.points,
    required this.freeCouponCredits,
    required this.savedCount,
    required this.activeCount,
    required this.level,
    required this.initials,
  });

  final String name;
  final String handle;
  final String city;
  final String district;
  final int points;
  final int freeCouponCredits;
  final int savedCount;
  final int activeCount;
  final int level;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final titleColor = Colors.white;
    final softWhite = Colors.white.withValues(alpha: 0.84);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: <BoxShadow>[
          ...AppShadows.floating,
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 42,
            spreadRadius: 2,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.16),
            blurRadius: 72,
            spreadRadius: 8,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 64,
                width: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: titleColor,
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: softWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$city, $district',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _HeroPill(
                icon: Icons.workspace_premium_rounded,
                label: 'Level $level',
              ),
              _HeroPill(
                icon: Icons.local_fire_department_rounded,
                label: '$points Punkte',
              ),
              _HeroPill(
                icon: Icons.card_giftcard_rounded,
                label: '$freeCouponCredits frei',
              ),
              _HeroPill(
                icon: Icons.bookmark_rounded,
                label: '$savedCount gespeichert',
              ),
              _HeroPill(icon: Icons.bolt_rounded, label: '$activeCount aktiv'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

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
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.96)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
