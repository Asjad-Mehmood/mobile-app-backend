import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import 'form_helpers.dart';

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hubs = ref.watch(adminHubsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BranchEditor())),
        icon: const Icon(Icons.add),
        label: const Text('New branch'),
      ),
      body: hubs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(adminHubsProvider)),
        data: (list) => ListView(padding: const EdgeInsets.all(12), children: [
          for (final h in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.storefront, color: h.isActive ? context.colors.primary : context.colors.outline),
                title: Text(h.name),
                subtitle: Text('${h.address}\nDelivers within ${h.deliveryRadiusKm.toStringAsFixed(0)} km${h.isActive ? '' : ' · closed'}'),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BranchEditor(hub: h))),
              ),
            ),
        ]),
      ),
    );
  }
}

class BranchEditor extends ConsumerStatefulWidget {
  const BranchEditor({super.key, this.hub});
  final Hub? hub;

  @override
  ConsumerState<BranchEditor> createState() => _BranchEditorState();
}

class _BranchEditorState extends ConsumerState<BranchEditor> {
  final _form = GlobalKey<FormState>();
  late final h = widget.hub;
  late final _name = TextEditingController(text: h?.name);
  late final _id = TextEditingController(text: h?.id);
  late final _address = TextEditingController(text: h?.address);
  late final _lat = TextEditingController(text: h == null ? '' : '${h!.latitude}');
  late final _lng = TextEditingController(text: h == null ? '' : '${h!.longitude}');
  late final _radius = TextEditingController(text: '${h?.deliveryRadiusKm.toStringAsFixed(0) ?? 15}');
  late final _sort = TextEditingController(text: '${h?.sortOrder ?? 0}');
  late bool _active = h?.isActive ?? true;

  @override
  void initState() {
    super.initState();
    if (h == null) _name.addListener(() => _id.text = 'hub-${slugify(_name.text)}');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final draft = Hub(
      id: h?.id ?? _id.text.trim(),
      name: _name.text.trim(),
      address: _address.text.trim(),
      latitude: double.parse(_lat.text),
      longitude: double.parse(_lng.text),
      deliveryRadiusKm: double.parse(_radius.text),
      isActive: _active,
      sortOrder: int.tryParse(_sort.text) ?? 0,
    );
    final api = ref.read(apiProvider);
    final ok = await runSave(context, () async {
      h == null ? await api.createHub(draft.id, draft) : await api.updateHub(draft.id, draft);
      ref.invalidate(adminHubsProvider);
      ref.invalidate(hubsProvider);
    });
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(h == null ? 'New branch' : h!.name),
          actions: [Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _save, child: const Text('Save')))],
        ),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FormSection('Branch', children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null),
              if (h == null)
                TextFormField(
                  controller: _id,
                  decoration: const InputDecoration(labelText: 'ID'),
                  validator: (v) => RegExp(r'^[a-z0-9][a-z0-9-]{1,59}$').hasMatch(v ?? '') ? null : 'Use lowercase letters, numbers and dashes',
                ),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), validator: (v) => (v ?? '').trim().length < 3 ? 'Enter the address' : null),
              Row(children: [
                Expanded(child: DecimalField(controller: _lat, label: 'Latitude')),
                const SizedBox(width: 12),
                Expanded(child: DecimalField(controller: _lng, label: 'Longitude')),
              ]),
              Text('Tip: long-press the shop in Google Maps to copy its coordinates.', style: context.text.bodySmall),
              DecimalField(controller: _radius, label: 'Delivery radius', suffix: 'km'),
              IntField(controller: _sort, label: 'Sort order'),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Open for orders')),
            ]),
          ]),
        ),
      );
}
