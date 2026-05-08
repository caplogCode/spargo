import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/compact_deal_card.dart';

class CategoryFeedScreen extends ConsumerWidget {
  const CategoryFeedScreen({super.key, required this.category});

  final DealCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref
        .watch(dealsProvider)
        .where((deal) => deal.category == category)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: deals.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final deal = deals[index];
          final business = ref.read(businessByIdProvider(deal.businessId));
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
    );
  }
}
