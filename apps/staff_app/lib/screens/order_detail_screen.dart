import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/data.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;

  Future<void> _set(OrderStatus status, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setOrderStatus(widget.orderId, status, reason: reason);
      ref.invalidate(staffOrderProvider(widget.orderId));
      ref.invalidate(staffOrdersProvider);
      ref.invalidate(newOrdersCountProvider);
    } catch (e) {
      if (mounted) context.toast(errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The customer is notified straight away and reserved stock goes back on the shelf.'),
          const SizedBox(height: 12),
          TextField(controller: reason, maxLength: 200, decoration: const InputDecoration(labelText: 'Reason for the customer')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (ok == true) await _set(OrderStatus.cancelled, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
  }

  Future<void> _verifyPickup(Order o) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check pickup code'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Code on the customer\'s phone', hintText: 'PU-1234'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Check')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final entered = ctl.text.trim().toUpperCase().replaceAll(' ', '');
    final code = (o.pickupCode ?? '').toUpperCase();
    if (entered == code || 'PU-$entered' == code) {
      context.toast('Code matches — hand over the order');
      await _set(OrderStatus.completed);
    } else {
      context.toast("That code doesn't match this order", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(staffOrderProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: Text('Order ${widget.orderId}')),
      body: order.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(staffOrderProvider(widget.orderId))),
        data: (o) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(o.statusTitle, style: context.text.headlineSmall)),
              StatusChip(o.status, type: o.fulfillmentType),
            ]),
            const SizedBox(height: 4),
            Text('${o.fulfillmentType.label} · ${dayLabelFor(o.slot.date)} · ${o.slot.label}', style: context.text.titleMedium?.copyWith(color: context.colors.primary)),
            Text('${o.hubName} · placed ${dateTimeLabel(o.createdAt)}', style: context.text.bodySmall),
            const SizedBox(height: 16),
            BakeryCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.customer?.name ?? 'Customer', style: context.text.titleMedium),
                if (o.customer != null) Text(o.customer!.email, style: context.text.bodySmall),
                if (o.deliveryAddress != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.location_on_outlined, size: 18), const SizedBox(width: 6), Expanded(child: Text(o.deliveryAddress!))]),
                ],
                if (o.customerNote != null) ...[
                  const SizedBox(height: 8),
                  Text('“${o.customerNote}”', style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (o.customer?.phone != null)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri(scheme: 'tel', path: o.customer!.phone)),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(o.customer!.phone!),
                    ),
                  if (o.deliveryAddress != null)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(o.deliveryAddress!)}'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Map'),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Items', style: context.text.titleLarge),
            const SizedBox(height: 8),
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 36, child: Text('${l.quantity}×', style: context.text.titleMedium)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.productName, style: context.text.titleSmall),
                      if (l.customization != null) ...[
                        Text(l.customization!.summary, style: context.text.bodySmall),
                        if (l.customization!.pipedMessage.isNotEmpty)
                          Text('Pipe: “${l.customization!.pipedMessage}” (${l.customization!.pipingFont.toLowerCase()})',
                              style: context.text.bodySmall?.copyWith(color: context.colors.primary)),
                      ],
                      if (l.specialInstructions != null) Text('Note: ${l.specialInstructions}', style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                    ]),
                  ),
                  Text(money(l.lineTotal)),
                ]),
              ),
            const Divider(height: 24),
            PricingSummary(pricing: o.pricing, promoCode: o.promoCode),
            Text(o.paymentMethod.label, style: context.text.bodySmall),
            if (o.pickupCode != null) Text('Pickup code ${o.pickupCode}', style: context.text.bodySmall),
            const SizedBox(height: 16),
            Text('History', style: context.text.titleLarge),
            for (final h in o.statusHistory)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 18),
                title: Text(h.status.titleFor(o.fulfillmentType)),
                subtitle: h.reason == null ? null : Text(h.reason!),
                trailing: Text(dateTimeLabel(h.at)),
              ),
            const SizedBox(height: 80),
          ]);
        },
      ),
      bottomNavigationBar: order.value == null || order.value!.status.isFinished
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  OutlinedButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  if (order.value!.status == OrderStatus.ready && order.value!.fulfillmentType == FulfillmentType.pickup) ...[
                    IconButton.filledTonal(
                      tooltip: 'Check pickup code',
                      onPressed: _busy ? null : () => _verifyPickup(order.value!),
                      icon: const Icon(Icons.qr_code_2),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: BakeryButton(
                      loading: _busy,
                      label: order.value!.status.next!.titleFor(order.value!.fulfillmentType),
                      icon: Icons.arrow_forward,
                      onPressed: () => _set(order.value!.status.next!),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
