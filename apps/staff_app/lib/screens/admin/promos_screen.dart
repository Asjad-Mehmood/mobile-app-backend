import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import 'form_helpers.dart';

const _types = {'PERCENT_OFF': 'Percent off', 'FIXED_OFF': 'Rupees off', 'FREE_DELIVERY': 'Free delivery'};

class PromosScreen extends ConsumerWidget {
  const PromosScreen({super.key});

  String _describe(Promo p) => switch (p.type) {
        'PERCENT_OFF' => '${p.value}% off${p.maxDiscount != null ? ' (max ${money(p.maxDiscount!)})' : ''}',
        'FIXED_OFF' => '${money(p.value)} off',
        _ => 'Free delivery',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(promosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Promo codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PromoEditor())),
        icon: const Icon(Icons.add),
        label: const Text('New code'),
      ),
      body: promos.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(promosProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.local_offer_outlined, title: 'No promo codes yet')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final p in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(p.code, style: TextStyle(fontWeight: FontWeight.w700, decoration: p.isActive ? null : TextDecoration.lineThrough)),
                      subtitle: Text([
                        _describe(p),
                        if (p.minSpend > 0) 'min ${money(p.minSpend)}',
                        if (p.expiresAt != null) 'until ${dateTimeLabel(p.expiresAt)}',
                      ].join(' · ')),
                      trailing: Switch(
                        value: p.isActive,
                        onChanged: (v) => runSave(context, () async {
                          await ref.read(apiProvider).updatePromo(Promo.fromJson({...p.toJson(), 'code': p.code, 'isActive': v, 'expiresAt': p.expiresAt?.toUtc().toIso8601String()}));
                          ref.invalidate(promosProvider);
                        }),
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromoEditor(promo: p))),
                    ),
                  ),
              ]),
      ),
    );
  }
}

class PromoEditor extends ConsumerStatefulWidget {
  const PromoEditor({super.key, this.promo});
  final Promo? promo;

  @override
  ConsumerState<PromoEditor> createState() => _PromoEditorState();
}

class _PromoEditorState extends ConsumerState<PromoEditor> {
  final _form = GlobalKey<FormState>();
  late final p = widget.promo;
  late final _code = TextEditingController(text: p?.code);
  late final _desc = TextEditingController(text: p?.description);
  late final _value = TextEditingController(text: '${p?.value ?? 10}');
  late final _min = TextEditingController(text: '${p?.minSpend ?? 0}');
  late final _max = TextEditingController(text: p?.maxDiscount == null ? '' : '${p!.maxDiscount}');
  late String _type = p?.type ?? 'PERCENT_OFF';
  late bool _active = p?.isActive ?? true;
  late DateTime? _expires = p?.expiresAt;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final draft = Promo(
      code: _code.text.trim().toUpperCase(),
      description: _desc.text.trim(),
      type: _type,
      value: _type == 'FREE_DELIVERY' ? 0 : int.parse(_value.text),
      minSpend: int.tryParse(_min.text) ?? 0,
      maxDiscount: _type == 'PERCENT_OFF' ? int.tryParse(_max.text) : null,
      isActive: _active,
      expiresAt: _expires,
    );
    final api = ref.read(apiProvider);
    final ok = await runSave(context, () async {
      p == null ? await api.createPromo(draft) : await api.updatePromo(draft);
      ref.invalidate(promosProvider);
    });
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(p == null ? 'New promo code' : p!.code),
          actions: [Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _save, child: const Text('Save')))],
        ),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FormSection('Code', children: [
              TextFormField(
                controller: _code,
                enabled: p == null,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'EIDMUBARAK'),
                validator: (v) => RegExp(r'^[A-Za-z0-9]{3,20}$').hasMatch((v ?? '').trim()) ? null : '3–20 letters or numbers',
              ),
              TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'What customers see'), validator: (v) => (v ?? '').trim().length < 3 ? 'Describe the offer' : null),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              if (_type != 'FREE_DELIVERY') IntField(controller: _value, label: _type == 'PERCENT_OFF' ? 'Percent' : 'Amount', suffix: _type == 'PERCENT_OFF' ? '%' : null, prefix: _type == 'FIXED_OFF' ? 'Rs' : null, min: 1),
              if (_type == 'PERCENT_OFF')
                TextFormField(controller: _max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum discount (optional)', prefixText: 'Rs ')),
              IntField(controller: _min, label: 'Minimum order', prefix: 'Rs'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expires'),
                subtitle: Text(_expires == null ? 'Never' : dateTimeLabel(_expires)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_expires != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _expires = null)),
                  IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: _expires ?? DateTime.now().add(const Duration(days: 30)));
                      if (d != null) setState(() => _expires = DateTime(d.year, d.month, d.day, 23, 59));
                    },
                  ),
                ]),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active')),
            ]),
          ]),
        ),
      );
}
