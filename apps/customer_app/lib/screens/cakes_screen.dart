import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/data.dart';
import 'widgets.dart';

class CakesScreen extends ConsumerWidget {
  const CakesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final saved = ref.watch(savedCakesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Artisanal cakes'), actions: const [CartAction()]),
      body: catalog.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (cat) {
          final cakes = cat.products.where((p) => p.isCustomizableCake).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(savedCakesProvider);
              ref.invalidate(catalogProvider);
              await ref.read(catalogProvider.future).then((_) {}, onError: (_) {});
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text('Design your own celebration cake — sized, flavoured and piped just for you. Baked fresh with 24 hours\' notice.',
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              if (saved.isNotEmpty) ...[
                const SectionHeader('Your saved designs', padding: EdgeInsets.only(top: 20, bottom: 8)),
                for (final s in saved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BakeryCard(
                      onTap: () => context.push('/cake/${s.productId}', extra: s.customization.choice),
                      child: Row(children: [
                        Icon(Icons.bookmark_rounded, color: context.colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: context.text.titleMedium),
                            Text(s.customization.summary, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Delete design',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await ref.read(apiProvider).deleteSavedCake(s.id);
                              ref.invalidate(savedCakesProvider);
                            } catch (e) {
                              if (context.mounted) context.toast(errorText(e), error: true);
                            }
                          },
                        ),
                      ]),
                    ),
                  ),
              ],
              const SectionHeader('Start a new cake', padding: EdgeInsets.only(top: 20, bottom: 8)),
              if (cakes.isEmpty) const EmptyState(icon: Icons.cake_outlined, title: 'No cakes on the menu right now'),
              for (final p in cakes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: BakeryCard(
                    padding: EdgeInsets.zero,
                    onTap: () => context.push('/cake/${p.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ProductImage(url: p.imageUrl, radius: 0, aspectRatio: 16 / 9),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(p.name, style: context.text.titleLarge)),
                            Text('From ${money(p.basePrice)}', style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
                          ]),
                          const SizedBox(height: 4),
                          Text(p.subtitle, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.dietaryTags) DietaryTagChip(t)]),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
