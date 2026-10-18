import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/cart.dart';
import '../state/data.dart';
import 'widgets.dart';

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int _qty = 1;
  int _image = 0;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final p = ref.watch(productProvider(widget.productId));
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: catalog.isLoading
            ? const LoadingView()
            : catalog.hasError
                ? ErrorRetry(error: catalog.error!, onRetry: () => ref.invalidate(catalogProvider))
                : const EmptyState(icon: Icons.no_food_outlined, title: 'No longer on the menu', message: 'This bake has been taken off the menu.'),
      );
    }
    final now = DateTime.now();
    final maxQty = p.isMadeToOrder ? 10 : p.stock.remainingBatchStock.clamp(0, 50);
    final qty = _qty.clamp(1, maxQty < 1 ? 1 : maxQty);
    final fav = ref.watch(favoritesProvider).value?.contains(p.id) ?? false;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          actions: [
            if (ref.watch(currentUserProvider) != null)
              IconButton(
                tooltip: 'Favourite',
                onPressed: () => ref.read(favoritesProvider.notifier).toggle(p.id),
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? context.bakery.waxSeal : null),
              ),
            const CartAction(),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(children: [
              Positioned.fill(
                child: PageView(
                  onPageChanged: (i) => setState(() => _image = i),
                  children: [
                    if (p.imageUrls.isEmpty) const ProductImage(radius: 0),
                    for (final url in p.imageUrls) ProductImage(url: url, radius: 0),
                  ],
                ),
              ),
              if (p.imageUrls.length > 1)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < p.imageUrls.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: i == _image ? 1 : 0.5)),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          sliver: SliverList.list(children: [
            Text(p.category.label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.colors.primary, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Text(p.name, style: context.text.headlineMedium),
            if (p.subtitle.isNotEmpty) Text(p.subtitle, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text(money(p.basePrice), style: context.text.headlineSmall?.copyWith(color: context.colors.primary)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in p.dietaryTags) DietaryTagChip(t),
              for (final a in p.allergens) AllergenBadge(a),
            ]),
            const SizedBox(height: 16),
            _StockPanel(product: p, now: now),
            const SizedBox(height: 16),
            Text(p.description, style: context.text.bodyLarge),
            if (p.crumbNotes != null && p.crumbNotes!.isNotEmpty) ...[
              const SectionHeader('Crumb notes', padding: EdgeInsets.only(top: 20, bottom: 6)),
              Text(p.crumbNotes!, style: context.text.bodyMedium),
            ],
            if (p.reheatingTip != null && p.reheatingTip!.isNotEmpty) ...[
              const SectionHeader("Baker's tip", padding: EdgeInsets.only(top: 20, bottom: 6)),
              InfoRow(icon: Icons.microwave_outlined, text: p.reheatingTip!),
            ],
            if (p.nutrition != null) ...[
              SectionHeader('Nutrition · ${p.nutrition!.servingSize}', padding: const EdgeInsets.only(top: 20, bottom: 6)),
              _NutritionTable(n: p.nutrition!),
            ],
            if (!p.isSoldOut) ...[
              const SectionHeader('Special instructions', padding: EdgeInsets.only(top: 20, bottom: 6)),
              TextField(
                controller: _notes,
                maxLength: 200,
                decoration: const InputDecoration(hintText: 'e.g. Please slice the loaf'),
              ),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: BottomBar(
        child: p.isSoldOut
            ? BakeryButton(label: p.stock.isBaking(now) ? 'Baking now — check back soon' : 'Sold out today', onPressed: null)
            : Row(children: [
                QuantitySelector(value: qty, max: maxQty < 1 ? 1 : maxQty, onChanged: (v) => setState(() => _qty = v)),
                const SizedBox(width: 14),
                Expanded(
                  child: BakeryButton(
                    label: 'Add · ${money(p.basePrice * qty)}',
                    icon: Icons.add_shopping_cart,
                    onPressed: () {
                      ref.read(cartProvider.notifier).addProduct(p, quantity: qty, instructions: _notes.text);
                      context.toast('${p.name} added to your cart');
                      context.pop();
                    },
                  ),
                ),
              ]),
      ),
    );
  }
}

class _StockPanel extends StatelessWidget {
  const _StockPanel({required this.product, required this.now});
  final Product product;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = product.stock;
    return BakeryCard(
      color: context.colors.surfaceContainerLow,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoRow(icon: Icons.schedule, text: product.bakeSchedule.label),
        if (product.isMadeToOrder)
          const InfoRow(icon: Icons.cake_outlined, text: "Baked to order — needs 24 hours' notice")
        else ...[
          InfoRow(
            icon: Icons.inventory_2_outlined,
            text: s.remainingBatchStock > 0 ? '${s.remainingBatchStock} left from batch #${s.currentBatchNumber}' : 'Sold out at this bakery today',
            color: s.remainingBatchStock == 0 ? context.colors.error : (s.remainingBatchStock <= 5 ? context.bakery.warning : null),
          ),
          if (s.isBaking(now)) Padding(padding: const EdgeInsets.only(top: 6), child: LiveBakeCountdown(readyAt: s.nextBatchReadyAt!, label: 'Next batch out in')),
        ],
      ]),
    );
  }
}

class _NutritionTable extends StatelessWidget {
  const _NutritionTable({required this.n});
  final Nutrition n;

  @override
  Widget build(BuildContext context) {
    String g(double v) => '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)} g';
    final rows = [('Calories', '${n.calories} kcal'), ('Fat', g(n.fatGrams)), ('Carbohydrates', g(n.carbsGrams)), ('Sugar', g(n.sugarGrams)), ('Protein', g(n.proteinGrams))];
    return Column(children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(k)), Text(v, style: context.text.titleSmall)]),
        ),
    ]);
  }
}
