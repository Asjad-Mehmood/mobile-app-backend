import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../state/cart.dart';
import '../state/data.dart';
import 'widgets.dart';

/// Five-step cake designer: size → sponge → filling → frosting → message & review.
class CakeBuilderScreen extends ConsumerStatefulWidget {
  const CakeBuilderScreen({super.key, required this.productId, this.initial});
  final String productId;
  final CakeChoice? initial;

  @override
  ConsumerState<CakeBuilderScreen> createState() => _CakeBuilderScreenState();
}

class _CakeBuilderScreenState extends ConsumerState<CakeBuilderScreen> {
  static const _steps = ['Size', 'Sponge', 'Filling', 'Frosting', 'Finish'];
  int _step = 0;
  CakeChoice? _choice;
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _choice = widget.initial;
    _message.text = widget.initial?.message ?? '';
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  CakeChoice _defaults(BusinessSettings s) => CakeChoice(
        sizeId: s.cakeSizes.first.id,
        spongeId: s.sponges.first.id,
        fillingId: s.fillings.first.id,
        frostingId: s.frostings.first.id,
        fontId: s.pipingFonts.firstOrNull?.id ?? 'SCRIPT',
      );

  void _set(CakeChoice c) => setState(() => _choice = c);

  Future<void> _save(Product p, BusinessSettings s) async {
    if (!requireSignIn(context, ref, '/cake/${p.id}')) return;
    final ctl = TextEditingController(text: '${p.name} for ${_message.text.trim().isEmpty ? 'a celebration' : _message.text.trim()}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save this design'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(apiProvider).saveCake(p.id, name, _choice!.copyWith(message: _message.text.trim()));
      ref.invalidate(savedCakesProvider);
      if (mounted) context.toast('Saved to your cake designs');
    } catch (e) {
      if (mounted) context.toast(errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final p = ref.watch(productProvider(widget.productId));
    final s = config.value;
    if (s == null || p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: config.hasError
            ? ErrorRetry(error: config.error!, onRetry: () => ref.invalidate(configProvider))
            : (ref.watch(catalogProvider).isLoading || config.isLoading)
                ? const LoadingView()
                : const EmptyState(icon: Icons.cake_outlined, title: 'Cake not available', message: 'This cake is no longer on the menu.'),
      );
    }
    final choice = _choice ??= _defaults(s);
    final price = previewCakePrice(s, p.basePrice, choice.copyWith(message: _message.text));
    final last = _step == _steps.length - 1;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: i <= _step ? () => setState(() => _step = i) : null,
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: i <= _step ? context.colors.primary : context.colors.outlineVariant, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(height: 6),
                        Text(_steps[i], style: context.text.labelSmall?.copyWith(color: i == _step ? context.colors.primary : context.colors.onSurfaceVariant)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(_step), child: _stepBody(s, p, choice)),
        ),
        bottomNavigationBar: BottomBar(
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your cake', style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(money(price.unitPrice), key: ValueKey(price.unitPrice), style: context.text.titleLarge?.copyWith(color: context.colors.primary)),
                ),
              ]),
            ),
            SizedBox(
              width: 180,
              child: BakeryButton(
                label: last ? 'Add to cart' : 'Next',
                icon: last ? Icons.add_shopping_cart : null,
                onPressed: () {
                  if (!last) return setState(() => _step++);
                  final msg = _message.text.trim();
                  if (msg.length > s.maxPipedMessageLength) return context.toast('Keep the message to ${s.maxPipedMessageLength} characters', error: true);
                  final c = choice.copyWith(message: msg);
                  ref.read(cartProvider.notifier).addCake(p, s, c, summary: cakeSummary(s, c));
                  context.toast('Cake added — remember it needs 24 hours\' notice');
                  context.pop();
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepBody(BusinessSettings s, Product p, CakeChoice c) {
    switch (_step) {
      case 0:
        return _OptionList(
          title: 'How many guests?',
          children: [
            for (final size in s.cakeSizes)
              _OptionTile(
                title: size.label,
                subtitle: 'Serves ${size.servings}${size.tiers > 1 ? ' · ${size.tiers} tiers' : ''}',
                trailing: money(previewCakePrice(s, p.basePrice, c.copyWith(sizeId: size.id)).unitPrice),
                selected: c.sizeId == size.id,
                onTap: () => _set(c.copyWith(sizeId: size.id)),
              ),
          ],
        );
      case 1:
        return _priced('Choose the sponge', s.sponges, c.spongeId, s, c, (id) => _set(c.copyWith(spongeId: id)));
      case 2:
        return _priced('Choose a filling', s.fillings, c.fillingId, s, c, (id) => _set(c.copyWith(fillingId: id)));
      case 3:
        return _priced('Choose the frosting', s.frostings, c.frostingId, s, c, (id) => _set(c.copyWith(frostingId: id)));
      default:
        final sponge = s.sponges.where((o) => o.id == c.spongeId).firstOrNull;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Finishing touches', style: context.text.headlineSmall),
          const SizedBox(height: 16),
          TextField(
            controller: _message,
            maxLength: s.maxPipedMessageLength,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Piped message (optional)', hintText: 'e.g. Happy Birthday Ayesha'),
          ),
          const SizedBox(height: 8),
          Text('Piping style', style: context.text.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final f in s.pipingFonts) ChoiceChip(label: Text(f.name), selected: c.fontId == f.id, onSelected: (_) => _set(c.copyWith(fontId: f.id))),
          ]),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.eggless || (sponge?.isEggless ?? false),
            onChanged: (sponge?.isEggless ?? false) ? null : (v) => _set(c.copyWith(eggless: v)),
            title: const Text('Make it eggless'),
            subtitle: Text((sponge?.isEggless ?? false) ? 'This sponge is already eggless' : '+ ${money(s.egglessSurcharge)}'),
          ),
          const Divider(height: 32),
          Text('Your design', style: context.text.titleLarge),
          const SizedBox(height: 8),
          Text(cakeSummary(s, c.copyWith(message: _message.text.trim()))),
          const SizedBox(height: 12),
          const InfoRow(icon: Icons.schedule, text: "Baked fresh to order — choose a collection or delivery time at least 24 hours from now."),
          const SizedBox(height: 16),
          BakeryButton(label: 'Save this design', icon: Icons.bookmark_add_outlined, outlined: true, onPressed: () => _save(p, s)),
        ]);
    }
  }

  Widget _priced(String title, List<PricedOption> options, String selected, BusinessSettings s, CakeChoice c, ValueChanged<String> onPick) {
    final mult = s.cakeSizes.where((x) => x.id == c.sizeId).firstOrNull?.multiplier ?? 1;
    return _OptionList(title: title, children: [
      for (final o in options)
        _OptionTile(
          title: o.name,
          subtitle: [o.description, if (o.allergens.isNotEmpty) 'Contains ${o.allergens.map((a) => a.label.toLowerCase()).join(', ')}'].where((x) => x.isNotEmpty).join(' · '),
          trailing: o.surcharge == 0 ? 'Included' : '+ ${money((o.surcharge * mult).round())}',
          selected: o.id == selected,
          onTap: () => onPick(o.id),
        ),
    ]);
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        Text(title, style: context.text.headlineSmall),
        const SizedBox(height: 16),
        for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
      ]);
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.title, required this.subtitle, required this.trailing, required this.selected, required this.onTap});
  final String title;
  final String subtitle;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? context.colors.primary : context.bakery.cardBorder, width: selected ? 2 : 1),
            color: selected ? context.colors.primaryContainer.withValues(alpha: 0.35) : context.colors.surfaceContainerLowest,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? context.colors.primary : context.colors.outline),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.text.titleMedium),
                    if (subtitle.isNotEmpty) Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(trailing, style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
              ]),
            ),
          ),
        ),
      );
}
