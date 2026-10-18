import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/data.dart';
import '../state/prefs.dart';
import 'widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ProductCategory? _category;
  final Set<Allergen> _freeFrom = {};
  final Set<DietaryTag> _tags = {};
  bool _favoritesOnly = false;
  String _query = '';

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'GOOD MORNING' : (h < 17 ? 'GOOD AFTERNOON' : 'GOOD EVENING');
  }

  bool get _filtered => _category != null || _freeFrom.isNotEmpty || _tags.isNotEmpty || _favoritesOnly || _query.isNotEmpty;

  void _clear() => setState(() {
        _category = null;
        _freeFrom.clear();
        _tags.clear();
        _favoritesOnly = false;
        _query = '';
      });

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final prefs = ref.watch(fulfillmentProvider);
    final hubs = ref.watch(hubsProvider).value ?? const [];
    final hubName = hubs.where((h) => h.id == prefs.hubId).firstOrNull?.name;
    final favs = ref.watch(favoritesProvider).value ?? const {};
    final live = ref.watch(realtimeStateProvider).value == RealtimeState.live;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(favoritesProvider);
          ref.invalidate(catalogProvider);
          await ref.read(catalogProvider.future).then((_) {}, onError: (_) {});
        },
        child: CustomScrollView(slivers: [
          SliverAppBar(
            floating: true,
            titleSpacing: 16,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_greeting(), style: context.text.labelSmall?.copyWith(color: context.colors.primary, letterSpacing: 1.4)),
              const Text('Crumb & Craft'),
            ]),
            actions: [
              Padding(padding: const EdgeInsets.only(right: 4), child: LiveDot(live: live, showLabel: false)),
              const CartAction(),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: BakeryCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: () => context.push('/fulfillment'),
                child: Row(children: [
                  Icon(prefs.isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded, color: context.colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      prefs.isDelivery ? 'Delivery · ${prefs.address ?? 'your address'}' : 'Pickup · ${hubName ?? 'choose a bakery'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                  ),
                  Text('Change', style: context.text.labelMedium?.copyWith(color: context.colors.primary)),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search croissants, sourdough, cakes…'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                children: [
                  _chip('All', _category == null, () => setState(() => _category = null)),
                  for (final c in ProductCategory.values) _chip(c.label, _category == c, () => setState(() => _category = _category == c ? null : c)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                children: [
                  if (ref.watch(currentUserProvider) != null)
                    _filter('Favourites', _favoritesOnly, () => setState(() => _favoritesOnly = !_favoritesOnly), icon: Icons.favorite),
                  for (final a in [Allergen.gluten, Allergen.dairy, Allergen.nuts, Allergen.eggs])
                    _filter('${switch (a) { Allergen.nuts => 'Nut', Allergen.eggs => 'Egg', _ => a.label }}-free', _freeFrom.contains(a), () => setState(() => _freeFrom.contains(a) ? _freeFrom.remove(a) : _freeFrom.add(a))),
                  for (final t in DietaryTag.values) _filter(t.label, _tags.contains(t), () => setState(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t))),
                ],
              ),
            ),
          ),
          ...catalog.when(
            loading: () => [const SliverFillRemaining(child: LoadingView())],
            error: (e, _) => [SliverFillRemaining(child: ErrorRetry(error: e, onRetry: () => ref.invalidate(catalogProvider)))],
            data: (cat) {
              final now = DateTime.now();
              final products = cat.products.where((p) {
                if (_category != null && p.category != _category) return false;
                if (_freeFrom.any((a) => p.allergens.contains(a))) return false;
                if (!_tags.every(p.dietaryTags.contains)) return false;
                if (_favoritesOnly && !favs.contains(p.id)) return false;
                if (_query.isNotEmpty && !'${p.name} ${p.subtitle} ${p.description}'.toLowerCase().contains(_query)) return false;
                return true;
              }).toList();
              final baking = cat.products.where((p) => p.stock.isBaking(now)).toList();
              return [
                if (!_filtered && baking.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('Fresh out of the oven')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: baking.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => SizedBox(
                          width: 280,
                          child: BakeryCard(
                            padding: const EdgeInsets.all(10),
                            onTap: () => context.push('/product/${baking[i].id}'),
                            child: Row(children: [
                              SizedBox.square(dimension: 64, child: ProductImage(url: baking[i].imageUrl, radius: 12)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(baking[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                                  const SizedBox(height: 6),
                                  LiveBakeCountdown(readyAt: baking[i].stock.nextBatchReadyAt!, label: 'Out in'),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: SectionHeader(
                    _filtered ? '${products.length} matching bakes' : "Today's bake",
                    trailing: _filtered ? TextButton(onPressed: _clear, child: const Text('Clear')) : null,
                  ),
                ),
                if (products.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Nothing matches yet',
                      message: 'No bakes fit those filters right now. Try removing one.',
                      action: 'Clear filters',
                      onAction: _clear,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 292, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      delegate: SliverChildBuilderDelegate((_, i) => ProductCard(product: products[i]), childCount: products.length),
                    ),
                  ),
              ];
            },
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()));

  Widget _filter(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final signedIn = ref.watch(currentUserProvider) != null;
    final fav = ref.watch(favoritesProvider).value?.contains(p.id) ?? false;
    final now = DateTime.now();
    final low = !p.isMadeToOrder && p.stock.remainingBatchStock > 0 && p.stock.remainingBatchStock <= 5;

    return BakeryCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push(p.isCustomizableCake ? '/cake/${p.id}' : '/product/${p.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: ProductImage(url: p.imageUrl, radius: 0)),
            if (p.isSoldOut)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Text(p.stock.isBaking(now) ? 'Baking now' : 'Sold out today', style: context.text.titleSmall?.copyWith(color: Colors.white)),
                ),
              ),
            if (signedIn)
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.read(favoritesProvider.notifier).toggle(p.id).catchError((Object e) {
                    if (context.mounted) context.toast(errorText(e), error: true);
                  }),
                  icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? context.bakery.waxSeal : null, size: 20),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(p.isCustomizableCake ? 'From ${money(p.basePrice)}' : money(p.basePrice), style: context.text.titleSmall?.copyWith(color: context.colors.primary))),
              if (p.stock.isBaking(now))
                Icon(Icons.local_fire_department_rounded, size: 18, color: context.colors.primary)
              else if (low)
                Text('${p.stock.remainingBatchStock} left', style: context.text.labelSmall?.copyWith(color: context.bakery.warning))
              else if (p.isMadeToOrder)
                Text('24 h', style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
