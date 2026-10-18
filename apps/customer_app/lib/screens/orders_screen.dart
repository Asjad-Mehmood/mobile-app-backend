import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/cart.dart';
import '../state/data.dart';
import 'widgets.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  void _reorder(BuildContext context, WidgetRef ref, Order o) {
    final catalog = ref.read(catalogProvider).value;
    final settings = ref.read(configProvider).value;
    final cart = ref.read(cartProvider.notifier);
    var added = 0, skipped = 0;
    for (final l in o.productLines) {
      final p = catalog?.byId(l.productId);
      if (p == null || (p.isSoldOut && !p.isMadeToOrder)) {
        skipped++;
        continue;
      }
      if (l.customization != null && settings != null) {
        final choice = l.customization!.choice;
        for (var i = 0; i < l.quantity; i++) {
          cart.addCake(p, settings, choice, summary: l.customization!.summary);
        }
      } else {
        cart.addProduct(p, quantity: l.quantity, instructions: l.specialInstructions);
      }
      added++;
    }
    if (added == 0) {
      context.toast("Those bakes aren't available right now", error: true);
      return;
    }
    context.toast(skipped > 0 ? 'Added $added items — $skipped not available today' : 'Added to your cart');
    context.push('/cart');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Orders')),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Track your bakes live',
          message: 'Sign in to see your orders and follow them from the oven to your door.',
          action: 'Sign in',
          onAction: () => context.push('/auth'),
        ),
      );
    }
    final orders = ref.watch(myOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Orders'), actions: const [CartAction()]),
      body: orders.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myOrdersProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Your first warm loaf is a tap away.',
              action: 'Browse the bakery',
              onAction: () => context.go('/home'),
            );
          }
          final active = list.where((o) => o.isActive).toList();
          final past = list.where((o) => !o.isActive).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myOrdersProvider.future),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              if (active.isNotEmpty) ...[
                const SectionHeader('In progress', padding: EdgeInsets.only(top: 8, bottom: 8)),
                for (final o in active) _OrderCard(order: o, onTap: () => context.push('/track/${o.id}')),
              ],
              if (past.isNotEmpty) ...[
                const SectionHeader('Past orders', padding: EdgeInsets.only(top: 16, bottom: 8)),
                for (final o in past) _OrderCard(order: o, onTap: () => context.push('/track/${o.id}'), onReorder: () => _reorder(context, ref, o)),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap, this.onReorder});
  final Order order;
  final VoidCallback onTap;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final first = o.productLines.firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BakeryCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          SizedBox.square(dimension: 64, child: ProductImage(url: first?.imageUrl, radius: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(o.id, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant))),
                StatusChip(o.status, type: o.fulfillmentType),
              ]),
              const SizedBox(height: 4),
              Text(o.itemsSummary(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text('${slotLabel(o.slot)} · ${money(o.pricing.total)}', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              if (onReorder != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: onReorder, icon: const Icon(Icons.replay, size: 18), label: const Text('Order again')),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
