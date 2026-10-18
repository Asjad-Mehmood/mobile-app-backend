import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import 'form_helpers.dart';

/// Fees, timing, loyalty and cake option prices. Saved settings re-price every app instantly.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(adminSettingsProvider);
    return settings.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text('Business settings')), body: const LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(title: const Text('Business settings')), body: ErrorRetry(error: e, onRetry: () => ref.invalidate(adminSettingsProvider))),
      data: (s) => _SettingsForm(key: ValueKey(s.raw.hashCode), settings: s),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({super.key, required this.settings});
  final BusinessSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late final BusinessSettings s = widget.settings;
  late final Map<String, TextEditingController> _num = {
    for (final k in const [
      'packagingFee',
      'cakeBoxFee',
      'deliveryFee',
      'freeDeliveryThreshold',
      'pickupPrepMinutes',
      'deliveryPrepMinutes',
      'leadTimeHours',
      'bookingDays',
      'stampsPerReward',
      'stampQualifyingTotal',
      'egglessSurcharge',
    ])
      k: TextEditingController(text: '${s.raw[k] ?? 0}'),
  };
  late final _name = TextEditingController(text: s.bakeryName);
  late final Map<String, List<TextEditingController>> _opt = {
    'sponges': [for (final o in s.sponges) TextEditingController(text: '${o.surcharge}')],
    'fillings': [for (final o in s.fillings) TextEditingController(text: '${o.surcharge}')],
    'frostings': [for (final o in s.frostings) TextEditingController(text: '${o.surcharge}')],
  };
  late final _addOns = [for (final a in s.addOns) TextEditingController(text: '${a.price}')];
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    List<Json> priced(String key, List<PricedOption> list) =>
        [for (var i = 0; i < list.length; i++) list[i].copyWith(surcharge: int.parse(_opt[key]![i].text)).toJson()];
    final patch = <String, dynamic>{
      'bakeryName': _name.text.trim(),
      for (final e in _num.entries) e.key: int.parse(e.value.text),
      'sponges': priced('sponges', s.sponges),
      'fillings': priced('fillings', s.fillings),
      'frostings': priced('frostings', s.frostings),
      'addOns': [for (var i = 0; i < s.addOns.length; i++) s.addOns[i].copyWith(price: int.parse(_addOns[i].text)).toJson()],
    };
    await runSave(context, () async {
      await ref.read(apiProvider).updateSettings(patch);
      ref.invalidate(adminSettingsProvider);
      ref.invalidate(configProvider);
    }, done: 'Settings saved — all apps updated');
    if (mounted) setState(() => _saving = false);
  }

  Widget _n(String key, String label, {String? prefix, String? suffix, int min = 0}) => IntField(controller: _num[key]!, label: label, prefix: prefix, suffix: suffix, min: min);

  Widget _row(List<Widget> children) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: children[i])],
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          FormSection('Bakery', children: [TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Bakery name'))]),
          FormSection('Fees', children: [
            _row([_n('packagingFee', 'Packaging', prefix: 'Rs'), _n('cakeBoxFee', 'Per cake box', prefix: 'Rs')]),
            _row([_n('deliveryFee', 'Delivery fee', prefix: 'Rs'), _n('freeDeliveryThreshold', 'Free delivery from', prefix: 'Rs')]),
          ]),
          FormSection('Timing', children: [
            _row([_n('pickupPrepMinutes', 'Pickup prep', suffix: 'min'), _n('deliveryPrepMinutes', 'Delivery prep', suffix: 'min')]),
            _row([_n('leadTimeHours', 'Cake notice', suffix: 'hours'), _n('bookingDays', 'Days bookable ahead', min: 1)]),
          ]),
          FormSection("Baker's Dozen loyalty", children: [
            _row([_n('stampsPerReward', 'Stamps per reward', min: 1), _n('stampQualifyingTotal', 'Stamp for orders over', prefix: 'Rs')]),
          ]),
          FormSection('Cake options (price for ½ kg — scales with size)', children: [
            _n('egglessSurcharge', 'Eggless surcharge', prefix: 'Rs'),
            for (final (key, title, list) in [('sponges', 'Sponges', s.sponges), ('fillings', 'Fillings', s.fillings), ('frostings', 'Frostings', s.frostings)]) ...[
              Text(title, style: context.text.titleSmall),
              for (var i = 0; i < list.length; i++) IntField(controller: _opt[key]![i], label: list[i].name, prefix: '+ Rs'),
            ],
          ]),
          if (s.addOns.isNotEmpty)
            FormSection('Celebration add-ons', children: [
              for (var i = 0; i < s.addOns.length; i++) IntField(controller: _addOns[i], label: s.addOns[i].name, prefix: 'Rs'),
            ]),
        ]),
      ),
    );
  }
}
