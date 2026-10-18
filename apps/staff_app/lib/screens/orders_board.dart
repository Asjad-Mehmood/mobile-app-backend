import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/data.dart';
import 'order_detail_screen.dart';
import 'shell.dart';

/// Live kitchen board: orders move through the bake stages as staff tap them on.
class OrdersBoard extends ConsumerWidget {
  const OrdersBoard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(staffOrdersProvider);
    final scope = ref.watch(orderScopeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: const [LiveIndicator(), HubFilterButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'active', label: Text('In progress')),
                ButtonSegment(value: 'today', label: Text('Today')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {scope},
              onSelectionChanged: (s) => ref.read(orderScopeProvider.notifier).set(s.first),
            ),
          ),
        ),
      ),
      body: orders.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(staffOrdersProvider)),
        data: (list) {
          if (list.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(staffOrdersProvider),
              child: ListView(children: const [
                SizedBox(height: 120),
                EmptyState(icon: Icons.done_all_rounded, title: 'All caught up', message: 'New orders appear here instantly.'),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(staffOrdersProvider);
              await ref.read(staffOrdersProvider.future).then((_) {}, onError: (_) {});
            },
            child: LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 420).floor().clamp(1, 3);
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 210, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: list.length,
                itemBuilder: (_, i) => OrderTicket(order: list[i]),
              );
            }),
          );
        },
      ),
    );
  }
}

class OrderTicket extends ConsumerStatefulWidget {
  const OrderTicket({super.key, required this.order});
  final Order order;

  @override
  ConsumerState<OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends ConsumerState<OrderTicket> {
  bool _busy = false;

  Future<void> _advance() async {
    final next = widget.order.status.next;
    if (next == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setOrderStatus(widget.order.id, next);
      ref.invalidate(staffOrdersProvider);
      ref.invalidate(newOrdersCountProvider);
    } catch (e) {
      if (mounted) context.toast(errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final next = o.status.next;
    final isNew = o.status == OrderStatus.confirmed;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isNew ? context.colors.primary : context.bakery.cardBorder, width: isNew ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(o.fulfillmentType == FulfillmentType.delivery ? Icons.delivery_dining : Icons.storefront, size: 20, color: context.colors.primary),
              const SizedBox(width: 6),
              Text(o.id, style: context.text.titleSmall),
              const Spacer(),
              StatusChip(o.status, type: o.fulfillmentType),
            ]),
            const SizedBox(height: 6),
            Text('${dayLabelFor(o.slot.date)} · ${o.slot.label}', style: context.text.titleMedium),
            Text('${o.customer?.name ?? 'Customer'} · ${o.hubName}', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                o.productLines.map((l) => '${l.quantity}× ${l.productName}${l.customization != null ? ' (custom)' : ''}').join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium,
              ),
            ),
            Row(children: [
              Text(money(o.pricing.total), style: context.text.titleSmall),
              const Spacer(),
              if (next != null)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _advance,
                  icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward, size: 18),
                  label: Text(next.titleFor(o.fulfillmentType)),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
