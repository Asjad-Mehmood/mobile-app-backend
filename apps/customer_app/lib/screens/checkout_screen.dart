import 'dart:async';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/cart.dart';
import '../state/data.dart';
import '../state/prefs.dart';
import 'widgets.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  List<SlotDay>? _days;
  Object? _slotsError;
  int _dayIndex = 0;
  SlotOption? _slot;
  PaymentMethod _payment = PaymentMethod.cash;
  String? _promo;
  bool _redeem = false;
  final Set<String> _addOns = {};
  final _promoCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  Quote? _quote;
  bool _quoting = false;
  Object? _quoteError;
  int _quoteSeq = 0;
  Timer? _debounce;
  bool _placing = false;
  String _slotKey = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadSlots);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _promoCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  List<CartItemInput> get _items => ref.read(cartProvider).map((l) => l.toInput()).toList();

  Future<void> _loadSlots() async {
    final prefs = ref.read(fulfillmentProvider);
    _slotKey = '${prefs.type.wire}|${ref.read(cartProvider).map((l) => l.productId).join(',')}';
    setState(() {
      _slotsError = null;
      _days = null;
    });
    try {
      final days = await ref.read(apiProvider).slots(prefs.type, _items);
      if (!mounted) return;
      setState(() {
        _days = days;
        // Keep the selection if still offered; otherwise start on the first day with a free window.
        final keep = _slot == null ? null : days.expand((d) => d.options).where((o) => o.date == _slot!.date && o.startMinute == _slot!.startMinute && o.available).firstOrNull;
        _slot = keep;
        final firstOpen = days.indexWhere((d) => d.hasAvailable);
        _dayIndex = keep != null ? days.indexWhere((d) => d.date == keep.date) : (firstOpen < 0 ? 0 : firstOpen);
      });
      _requote(now: true);
    } catch (e) {
      if (mounted) setState(() => _slotsError = e);
    }
  }

  CheckoutInput _input() {
    final prefs = ref.read(fulfillmentProvider);
    return CheckoutInput(
      hubId: prefs.hubId ?? '',
      fulfillmentType: prefs.type,
      items: _items,
      slotDate: _slot?.date,
      slotStartMinute: _slot?.startMinute,
      deliveryAddress: prefs.isDelivery ? prefs.address : null,
      deliveryLat: prefs.isDelivery ? prefs.lat : null,
      deliveryLng: prefs.isDelivery ? prefs.lng : null,
      paymentMethod: _payment,
      promoCode: _promo,
      redeemReward: _redeem,
      addOns: _addOns.toList(),
      customerNote: _noteCtl.text,
    );
  }

  void _requote({bool now = false}) {
    _debounce?.cancel();
    _debounce = Timer(now ? Duration.zero : const Duration(milliseconds: 350), () async {
      if (ref.read(cartProvider).isEmpty) return;
      final seq = ++_quoteSeq;
      setState(() => _quoting = true);
      try {
        final q = await ref.read(apiProvider).quote(_input());
        if (!mounted || seq != _quoteSeq) return;
        ref.read(cartProvider.notifier).syncPrices(q.lineUnitPrices);
        setState(() {
          _quote = q;
          _quoteError = null;
          if (q.loyalty.rewardsAvailable == 0) _redeem = false;
        });
      } catch (e) {
        if (mounted && seq == _quoteSeq) setState(() => _quoteError = e);
      } finally {
        if (mounted && seq == _quoteSeq) setState(() => _quoting = false);
      }
    });
  }

  Future<void> _place() async {
    setState(() => _placing = true);
    try {
      final order = await ref.read(apiProvider).placeOrder(_input());
      HapticFeedback.mediumImpact();
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myOrdersProvider);
      ref.invalidate(catalogProvider);
      if (mounted) context.go('/track/${order.id}?new=1');
    } on ApiException catch (e) {
      if (!mounted) return;
      context.toast(e.message, error: true);
      // Slots or stock may have moved on — refresh both.
      if (e.code.startsWith('SLOT') || e.code.contains('STOCK') || e.status == 409) _loadSlots();
      _requote(now: true);
    } catch (e) {
      if (mounted) context.toast(errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final prefs = ref.watch(fulfillmentProvider);
    final config = ref.watch(configProvider).value;
    final hubs = ref.watch(hubsProvider).value ?? const [];
    final hub = hubs.where((h) => h.id == prefs.hubId).firstOrNull;

    // Reload windows when fulfilment or cart contents change underneath us.
    ref.listen(fulfillmentProvider, (a, b) {
      if (a?.type != b.type || a?.hubId != b.hubId || a?.address != b.address) _loadSlots();
    });
    ref.listen(syncEventsProvider, (_, next) {
      final e = next.value;
      if (e == null) return;
      if (e.type == 'stock.updated' && e.hubId == prefs.hubId || e.type == 'settings.updated' || e.type == 'promos.updated' || e.type == 'catalog.updated') {
        _requote();
      }
    });
    final key = '${prefs.type.wire}|${lines.map((l) => l.productId).join(',')}';
    if (_days != null && key != _slotKey) Future.microtask(_loadSlots);

    if (lines.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Checkout')), body: const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Your cart is empty'));
    }
    final hasCake = lines.any((l) => l.cake != null);
    final q = _quote;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        // ── Fulfilment ──
        BakeryCard(
          onTap: () => context.push('/fulfillment'),
          child: Row(children: [
            Icon(prefs.isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded, color: context.colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(prefs.isDelivery ? 'Home delivery' : 'Store pickup', style: context.text.titleMedium),
                Text(prefs.isDelivery ? '${prefs.address ?? 'Add an address'} · from ${hub?.name ?? ''}' : hub == null ? '' : '${hub.name} · ${hub.address}',
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ]),
            ),
            Text('Change', style: context.text.labelMedium?.copyWith(color: context.colors.primary)),
          ]),
        ),

        // ── Time slot ──
        SectionHeader(prefs.isDelivery ? 'Delivery time' : 'Pickup time', padding: const EdgeInsets.only(top: 20, bottom: 8)),
        if (_slotsError != null)
          ErrorRetry(error: _slotsError!, onRetry: _loadSlots)
        else if (_days == null)
          const Padding(padding: EdgeInsets.all(20), child: LoadingView())
        else ...[
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _days!.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(_days![i].label), selected: i == _dayIndex, onSelected: (_) => setState(() => _dayIndex = i)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          for (final o in _days![_dayIndex].options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SlotTile(
                option: o,
                selected: _slot?.date == o.date && _slot?.startMinute == o.startMinute,
                onTap: () {
                  setState(() => _slot = o);
                  _requote(now: true);
                },
              ),
            ),
          if (lines.any((l) => l.cake != null)) const InfoRow(icon: Icons.cake_outlined, text: "Custom cakes need 24 hours' notice, so earlier windows are closed."),
        ],

        // ── Add-ons ──
        if (hasCake && config != null && config.addOns.isNotEmpty) ...[
          const SectionHeader('Make it a celebration', padding: EdgeInsets.only(top: 20, bottom: 4)),
          for (final a in config.addOns)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _addOns.contains(a.id),
              title: Text(a.name),
              subtitle: a.description.isEmpty ? null : Text(a.description),
              secondary: Text('+ ${money(a.price)}'),
              onChanged: (v) {
                setState(() => v == true ? _addOns.add(a.id) : _addOns.remove(a.id));
                _requote();
              },
            ),
        ],

        // ── Offers ──
        const SectionHeader('Offers', padding: EdgeInsets.only(top: 20, bottom: 8)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _promoCtl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Promo code',
                errorText: _promo != null ? q?.promoError : null,
                helperText: _promo != null && q?.promoError == null ? q?.promoDescription : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: _promo == null
                ? FilledButton.tonal(
                    onPressed: () {
                      final code = _promoCtl.text.trim().toUpperCase();
                      if (code.isEmpty) return;
                      setState(() => _promo = code);
                      _requote(now: true);
                    },
                    child: const Text('Apply'),
                  )
                : OutlinedButton(
                    onPressed: () {
                      setState(() => _promo = null);
                      _promoCtl.clear();
                      _requote(now: true);
                    },
                    child: const Text('Remove'),
                  ),
          ),
        ]),
        if ((q?.loyalty.rewardsAvailable ?? 0) > 0)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _redeem,
            onChanged: (v) {
              setState(() => _redeem = v);
              _requote(now: true);
            },
            secondary: Icon(Icons.card_giftcard, color: context.bakery.waxSeal),
            title: const Text("Use your Baker's Dozen reward"),
            subtitle: Text(q!.loyalty.rewardValue == null
                ? 'Add a pastry or cookie to claim it free'
                : 'Your cheapest pastry or cookie is free (${money(q.loyalty.rewardValue!)})'),
          ),

        // ── Payment & note ──
        const SectionHeader('Payment', padding: EdgeInsets.only(top: 12, bottom: 4)),
        RadioGroup<PaymentMethod>(
          groupValue: _payment,
          onChanged: (v) => setState(() => _payment = v ?? _payment),
          child: Column(children: [
            for (final m in PaymentMethod.values)
              RadioListTile<PaymentMethod>(contentPadding: EdgeInsets.zero, value: m, title: Text(m.label)),
          ]),
        ),
        const SizedBox(height: 8),
        TextField(controller: _noteCtl, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Note for the bakery (optional)')),

        // ── Summary ──
        const SectionHeader('Summary', padding: EdgeInsets.only(top: 8, bottom: 8)),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text('${l.quantity}× ${l.name}${l.cakeSummary == null ? '' : '\n${l.cakeSummary}'}', style: context.text.bodyMedium)),
              Text(money(l.lineTotal)),
            ]),
          ),
        const Divider(height: 24),
        if (q != null) PricingSummary(pricing: q.pricing, promoCode: q.promoCode) else if (_quoteError != null) Text(errorText(_quoteError!)),
        if (_quoteError != null && q != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(errorText(_quoteError!), style: TextStyle(color: context.colors.error))),
      ]),
      bottomNavigationBar: BottomBar(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (q?.blockingIssue != null && _slot != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(q!.blockingIssue!, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.colors.error)),
            ),
          BakeryButton(
            label: _slot == null ? 'Choose a time' : 'Place order${q == null ? '' : ' · ${money(q.pricing.total)}'}',
            loading: _placing || (_quoting && q == null),
            onPressed: _slot == null || q == null || !q.canPlace || _quoting ? null : _place,
          ),
        ]),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.option, required this.selected, required this.onTap});
  final SlotOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = option.available;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? context.colors.primary : context.bakery.cardBorder, width: selected ? 2 : 1),
          color: selected ? context.colors.primaryContainer.withValues(alpha: 0.35) : context.colors.surfaceContainerLowest,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.schedule, color: selected ? context.colors.primary : context.colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(option.label, style: context.text.titleSmall),
                  if (!enabled && option.reason != null) Text(option.reason!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
