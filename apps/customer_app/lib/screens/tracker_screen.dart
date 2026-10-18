import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/data.dart';
import 'widgets.dart';

/// Live order tracker — moves the moment the kitchen updates the order.
class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key, required this.orderId, this.justPlaced = false});
  final String orderId;
  final bool justPlaced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final live = ref.watch(realtimeStateProvider).value == RealtimeState.live;
    final hubs = ref.watch(hubsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Order $orderId'),
        leading: justPlaced ? IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => context.go('/orders')) : null,
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: LiveDot(live: live))],
      ),
      body: order.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(orderProvider(orderId))),
        data: (o) {
          final hub = hubs.where((h) => h.id == o.hubId).firstOrNull;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(orderProvider(orderId).future),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              if (justPlaced && o.status == OrderStatus.confirmed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: BakeryCard(
                    color: context.colors.tertiaryContainer,
                    child: Row(children: [
                      const Icon(Icons.celebration_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Thank you! Your order is with the head baker.', style: context.text.titleSmall)),
                    ]),
                  ),
                ),
              Text(o.statusTitle, style: context.text.headlineMedium),
              const SizedBox(height: 4),
              Text(o.status.description, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('${o.fulfillmentType.label} · ${slotLabel(o.slot)}', style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
              const SizedBox(height: 20),
              if (o.status == OrderStatus.cancelled)
                BakeryCard(
                  color: context.colors.errorContainer,
                  child: Text(
                    o.statusHistory.lastWhere((h) => h.status == OrderStatus.cancelled, orElse: () => StatusEntry(status: o.status, at: DateTime.now())).reason ??
                        'This order was cancelled.',
                    style: TextStyle(color: context.colors.onErrorContainer),
                  ),
                )
              else
                _Timeline(order: o),
              if (o.fulfillmentType == FulfillmentType.pickup && o.pickupCode != null && !o.status.isFinished) ...[
                const SectionHeader('Show this at the counter', padding: EdgeInsets.only(top: 24, bottom: 12)),
                Center(child: PickupQr(data: '${o.id}|${o.pickupCode}')),
                const SizedBox(height: 10),
                Center(child: Text(o.pickupCode!, style: context.text.headlineSmall?.copyWith(letterSpacing: 2))),
                if (hub != null)
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.directions_outlined),
                      label: Text('Directions to ${hub.name}'),
                      onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${hub.latitude},${hub.longitude}'),
                          mode: LaunchMode.externalApplication),
                    ),
                  ),
              ],
              if (o.fulfillmentType == FulfillmentType.delivery && o.deliveryAddress != null) ...[
                const SizedBox(height: 16),
                InfoRow(icon: Icons.location_on_outlined, text: o.deliveryAddress!),
              ],
              const SectionHeader('Your order', padding: EdgeInsets.only(top: 24, bottom: 8)),
              for (final l in o.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l.quantity}× ${l.productName}', style: context.text.bodyMedium),
                        if (l.customization != null) Text(l.customization!.summary, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                        if (l.specialInstructions != null) Text('Note: ${l.specialInstructions}', style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                      ]),
                    ),
                    Text(money(l.lineTotal)),
                  ]),
                ),
              const Divider(height: 24),
              PricingSummary(pricing: o.pricing, promoCode: o.promoCode),
              const SizedBox(height: 8),
              InfoRow(icon: Icons.payments_outlined, text: o.paymentMethod.label),
              if (o.stampsEarned > 0) InfoRow(icon: Icons.verified_outlined, text: 'This order earns ${o.stampsEarned} stamp on your Baker\'s Dozen card', color: context.bakery.waxSeal),
              if (o.status == OrderStatus.confirmed) ...[
                const SizedBox(height: 20),
                BakeryButton(
                  label: 'Cancel order',
                  outlined: true,
                  icon: Icons.cancel_outlined,
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Cancel this order?'),
                        content: const Text("You can cancel until the baker starts mixing. Any reserved bakes go back on the shelf."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel order')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await ref.read(apiProvider).cancelOrder(o.id);
                      ref.invalidate(orderProvider(o.id));
                      ref.invalidate(myOrdersProvider);
                    } catch (e) {
                      if (context.mounted) context.toast(errorText(e), error: true);
                    }
                  },
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final stages = OrderStatus.trackerStages;
    final current = order.status == OrderStatus.completed ? stages.length : stages.indexOf(order.status);
    return Column(children: [
      for (var i = 0; i < stages.length; i++)
        _TimelineRow(
          title: stages[i].titleFor(order.fulfillmentType),
          time: order.statusHistory.where((h) => h.status == stages[i]).firstOrNull?.at,
          done: i < current,
          active: i == current,
          last: i == stages.length - 1,
        ),
      if (order.status == OrderStatus.completed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InfoRow(icon: Icons.check_circle, text: '${order.statusTitle} — enjoy your bake!', color: context.bakery.success),
        ),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.title, this.time, required this.done, required this.active, required this.last});
  final String title;
  final DateTime? time;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = done || active ? c.primary : c.outlineVariant;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: active ? 26 : 22,
              height: active ? 26 : 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.primary : (active ? c.primaryContainer : c.surface),
                border: Border.all(color: color, width: 2),
              ),
              child: done ? Icon(Icons.check, size: 14, color: c.onPrimary) : (active ? Icon(Icons.local_fire_department, size: 14, color: c.primary) : null),
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? c.primary : c.outlineVariant)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22, top: 2),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    style: (active ? context.text.titleMedium : context.text.bodyLarge)?.copyWith(color: done || active ? c.onSurface : c.onSurfaceVariant)),
              ),
              if (time != null) Text(timeLabel(time), style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}
