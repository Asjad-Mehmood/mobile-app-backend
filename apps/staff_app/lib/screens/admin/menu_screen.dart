import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import 'form_helpers.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(adminProductsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductEditor())),
        icon: const Icon(Icons.add),
        label: const Text('New product'),
      ),
      body: products.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(adminProductsProvider)),
        data: (list) {
          final byCat = {for (final c in ProductCategory.values) c: list.where((p) => p.category == c).toList()};
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminProductsProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
              for (final entry in byCat.entries)
                if (entry.value.isNotEmpty) ...[
                  SectionHeader(entry.key.label, padding: const EdgeInsets.fromLTRB(4, 12, 4, 6)),
                  for (final p in entry.value)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: SizedBox.square(dimension: 48, child: ProductImage(url: p.imageUrl, radius: 8)),
                        title: Text(p.name, style: TextStyle(decoration: p.isListed ? null : TextDecoration.lineThrough)),
                        subtitle: Text('${money(p.basePrice)} · ${p.isListed ? p.bakeSchedule.label : 'Hidden from customers'}'),
                        trailing: Switch(
                          value: p.isListed,
                          onChanged: (v) => runSave(context, () async {
                            await ref.read(apiProvider).updateProduct(Product.fromJson({...p.toAdminJson(), 'id': p.id, 'isListed': v}));
                            ref.invalidate(adminProductsProvider);
                          }, done: v ? '${p.name} is on the menu' : '${p.name} hidden'),
                        ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductEditor(product: p))),
                      ),
                    ),
                ],
            ]),
          );
        },
      ),
    );
  }
}

class ProductEditor extends ConsumerStatefulWidget {
  const ProductEditor({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final Product? p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _id = TextEditingController(text: p?.id);
  late final _subtitle = TextEditingController(text: p?.subtitle);
  late final _desc = TextEditingController(text: p?.description);
  late final _notes = TextEditingController(text: p?.crumbNotes);
  late final _tip = TextEditingController(text: p?.reheatingTip);
  late final _price = TextEditingController(text: '${p?.basePrice ?? ''}');
  late final _images = TextEditingController(text: p?.imageUrls.join('\n'));
  late final _sort = TextEditingController(text: '${p?.sortOrder ?? 0}');
  late ProductCategory _category = p?.category ?? ProductCategory.pastry;
  late BakeSchedule _schedule = p?.bakeSchedule ?? BakeSchedule.morning;
  late final Set<Allergen> _allergens = {...?p?.allergens};
  late final Set<DietaryTag> _tags = {...?p?.dietaryTags};
  late bool _cake = p?.isCustomizableCake ?? false;
  late bool _listed = p?.isListed ?? true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (p == null) _name.addListener(() => _id.text = slugify(_name.text));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final draft = Product(
      id: p?.id ?? _id.text.trim(),
      name: _name.text.trim(),
      subtitle: _subtitle.text.trim(),
      description: _desc.text.trim(),
      crumbNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      reheatingTip: _tip.text.trim().isEmpty ? null : _tip.text.trim(),
      basePrice: int.parse(_price.text),
      category: _category,
      imageUrls: _images.text.split(RegExp(r'\s+')).where((u) => u.startsWith('http')).toList(),
      allergens: _allergens,
      dietaryTags: _tags,
      bakeSchedule: _schedule,
      isCustomizableCake: _cake,
      nutrition: p?.nutrition,
      sortOrder: int.tryParse(_sort.text) ?? 0,
      isListed: _listed,
    );
    final api = ref.read(apiProvider);
    final ok = await runSave(context, () async {
      if (p == null) {
        await api.createProduct(draft.id, draft);
      } else {
        await api.updateProduct(draft);
      }
      ref.invalidate(adminProductsProvider);
    }, done: p == null ? '${draft.name} added to the menu' : 'Saved');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'New product' : 'Edit ${p!.name}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          FormSection('Basics', children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null),
            if (p == null)
              TextFormField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'ID (used in links)', helperText: 'Lowercase letters, numbers and dashes'),
                validator: (v) => RegExp(r'^[a-z0-9][a-z0-9-]{1,59}$').hasMatch(v ?? '') ? null : 'Use lowercase letters, numbers and dashes',
              ),
            TextFormField(controller: _subtitle, decoration: const InputDecoration(labelText: 'Short description')),
            IntField(controller: _price, label: _cake ? 'Base price (½ kg)' : 'Price', prefix: 'Rs'),
            DropdownButtonFormField<ProductCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in ProductCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            DropdownButtonFormField<BakeSchedule>(
              initialValue: _schedule,
              decoration: const InputDecoration(labelText: 'Bake schedule'),
              items: [for (final s in BakeSchedule.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) => setState(() => _schedule = v ?? _schedule),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _cake, onChanged: (v) => setState(() => _cake = v), title: const Text('Custom cake (opens the cake designer)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _listed, onChanged: (v) => setState(() => _listed = v), title: const Text('Show on the menu')),
          ]),
          FormSection('Description', children: [
            TextFormField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Full description')),
            TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Crumb notes (taste & texture)')),
            TextFormField(controller: _tip, maxLines: 2, decoration: const InputDecoration(labelText: "Baker's reheating tip")),
          ]),
          FormSection('Allergens & dietary', children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in Allergen.values)
                FilterChip(label: Text('Contains ${a.label.toLowerCase()}'), selected: _allergens.contains(a), onSelected: (v) => setState(() => v ? _allergens.add(a) : _allergens.remove(a))),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in DietaryTag.values) FilterChip(label: Text(t.label), selected: _tags.contains(t), onSelected: (v) => setState(() => v ? _tags.add(t) : _tags.remove(t))),
            ]),
          ]),
          FormSection('Photos', children: [
            TextFormField(controller: _images, maxLines: 3, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image URLs (one per line)')),
            if (_images.text.trim().isNotEmpty) SizedBox(height: 120, child: ProductImage(url: _images.text.trim().split(RegExp(r'\s+')).first)),
          ]),
          FormSection('Ordering', children: [IntField(controller: _sort, label: 'Sort order', helper: 'Lower numbers show first')]),
        ]),
      ),
    );
  }
}
