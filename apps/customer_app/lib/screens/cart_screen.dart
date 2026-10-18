import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../state/cart.dart';
import '../state/data.dart';
import 'widgets.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final catalog = ref.watch(catalogProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          if (lines.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Empty your cart?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Empty')),
                    ],
                  ),
                );
                if (ok == true) ref.read(cartProvider.notifier).clear();
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: lines.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message: 'Fresh bakes are waiting — add something warm.',
              action: 'Browse the bakery',
              onAction: () => context.go('/home'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final l = lines[i];
                final product = catalog?.byId(l.productId);
                final unavailable = catalog != null && (product == null || product.isSoldOut);
                final maxQty = product == null || product.isMadeToOrder ? 10 : product.stock.remainingBatchStock.clamp(1, 50);
                return Dismissible(
                  key: ValueKey(l.key),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: context.colors.errorContainer, borderRadius: BorderRadius.circular(16)),
                    child: Icon(Icons.delete_outline, color: context.colors.onErrorContainer),
                  ),
                  onDismissed: (_) => ref.read(cartProvider.notifier).remove(l.key),
                  child: BakeryCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox.square(dimension: 72, child: ProductImage(url: l.imageUrl, radius: 12)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.name, style: context.text.titleSmall),
                          if (l.cakeSummary != null) Text(l.cakeSummary!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                          if (l.instructions != null) Text('Note: ${l.instructions}', style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                          if (unavailable)
                            Text(product == null ? 'No longer on the menu' : 'Sold out today — choose a later day at checkout',
                                style: context.text.bodySmall?.copyWith(color: context.colors.error)),
                          const SizedBox(height: 8),
                          Row(children: [
                            QuantitySelector(
                              compact: true,
                              value: l.quantity,
                              min: 0,
                              max: maxQty,
                              onChanged: (v) => ref.read(cartProvider.notifier).setQuantity(l.key, v),
                            ),
                            const Spacer(),
                            Text(money(l.lineTotal), style: context.text.titleSmall),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : BottomBar(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: Text('Subtotal', style: context.text.titleMedium)),
                  Text(money(subtotal), style: context.text.titleMedium),
                ]),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Packaging, delivery and offers are added at checkout.', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                ),
                const SizedBox(height: 12),
                BakeryButton(
                  label: 'Checkout',
                  icon: Icons.lock_outline,
                  onPressed: () {
                    if (requireSignIn(context, ref, '/checkout')) context.push('/checkout');
                  },
                ),
              ]),
            ),
    );
  }
}
