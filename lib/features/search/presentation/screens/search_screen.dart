import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../domain/models/deal_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchControllerProvider).query,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(searchControllerProvider.notifier).updateQuery(_controller.text);
    Navigator.of(context).pushNamed(
      AppRoutes.searchResults,
      arguments: SearchResultsArgs(_controller.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(categoryCountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Suchen')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListView(
          children: <Widget>[
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: context.t('Business, Kategorie, Stadt oder Deal'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('Kategorien', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.25,
              children: DealCategory.values.map((category) {
                return InkWell(
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.categoryFeed,
                    arguments: CategoryFeedArgs(category),
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          category.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${counts[category] ?? 0} aktive Deals',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Schnelleinstiege',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  <String>[
                    'Nur heute',
                    'Brunch',
                    'Date Night',
                    'Beauty',
                    'Bremen',
                  ].map((term) {
                    return ActionChip(
                      label: Text(term),
                      onPressed: () {
                        _controller.text = term;
                        _submit();
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
