import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../shared/providers/app_providers.dart';

class BusinessBranchesScreen extends ConsumerWidget {
  const BusinessBranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(ownedBusinessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Filialen & Öffnungszeiten')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: business.branches.map((branch) {
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  branch.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(branch.address),
                const SizedBox(height: AppSpacing.md),
                ...branch.hours.map(
                  (hours) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      hours.isClosed
                          ? '${hours.day}: geschlossen'
                          : '${hours.day}: ${hours.opensAt} - ${hours.closesAt}',
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
