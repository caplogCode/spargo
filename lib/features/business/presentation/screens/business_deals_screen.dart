import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/business_models.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../theme/app_colors.dart';

class BusinessDealsScreen extends ConsumerWidget {
  const BusinessDealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(ownedBusinessProvider);
    final canPublish = ref.watch(ownedBusinessCanPublishProvider);
    final deals = ref.watch(businessDealsProvider(business.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Gutscheine'),
        actions: <Widget>[
          IconButton(
            onPressed: canPublish
                ? () => Navigator.of(context).pushNamed(AppRoutes.createDeal)
                : () => _showVerificationBlocked(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          if (!canPublish) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F6),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Text(
                business.verificationStatus ==
                        BusinessVerificationStatus.rejected
                    ? 'Dein Business wurde abgelehnt. Bitte korrigiere die Angaben und reiche es erneut ein.'
                    : 'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor neue Gutscheine live gehen.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (deals.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Text(
                'Noch kein Gutschein angelegt. Erstelle deinen ersten Gutschein direkt aus dem Dashboard oder \u00fcber das Plus oben rechts.',
              ),
            ),
          ...List<Widget>.generate(deals.length, (index) {
            final deal = deals[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == deals.length - 1 ? 0 : AppSpacing.md,
              ),
              child: ListTile(
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.editDeal,
                  arguments: BusinessDealEditorArgs(dealId: deal.id),
                ),
                contentPadding: const EdgeInsets.all(AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                tileColor: Theme.of(context).colorScheme.surface,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: deal.imageUrl.trim().isEmpty
                        ? Container(
                            color: const Color(0xFFFFEEF2),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.local_offer_rounded,
                              color: AppColors.primary,
                            ),
                          )
                        : Image.network(
                            deal.imageUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: const Color(0xFFFFEEF2),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.local_offer_rounded,
                                  color: AppColors.primary,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                title: Text(
                  deal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_dealTypeLabel(deal.type)} \u00b7 ${deal.availabilityLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.of(context).pushNamed(
                        AppRoutes.editDeal,
                        arguments: BusinessDealEditorArgs(dealId: deal.id),
                      );
                      return;
                    }
                    if (value == 'delete') {
                      _confirmDeleteDeal(context, ref, business, deal);
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                    PopupMenuItem(value: 'delete', child: Text('Löschen')),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('${deal.savingsPercent}%'),
                      const SizedBox(width: 4),
                      const Icon(Icons.more_vert_rounded),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _dealTypeLabel(DealType type) {
    switch (type) {
      case DealType.percentage:
        return 'Rabatt';
      case DealType.exclusive:
        return 'Exklusiv';
      case DealType.limitedTime:
        return 'Zeitfenster';
      case DealType.twoForOne:
        return '2-f\u00fcr-1';
      case DealType.happyHour:
        return 'Happy Hour';
      case DealType.event:
        return 'Event Deal';
      case DealType.newcomer:
        return 'Neukundenaktion';
    }
  }

  void _showVerificationBlocked(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Dieses Business braucht noch eine saubere E-Mail-, Domain- oder Google-Business-Zuordnung, bevor neue Gutscheine live gehen.',
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDeal(
    BuildContext context,
    WidgetRef ref,
    Business business,
    Deal deal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gutschein löschen?'),
        content: Text(
          '"${deal.title}" wird aus dem Feed entfernt. Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(repositoryProvider)
          .deleteBusinessDeal(business: business, dealId: deal.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gutschein wurde gelöscht.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gutschein konnte nicht gelöscht werden: $error'),
        ),
      );
    }
  }
}
