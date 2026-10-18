import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Integer field (rupees, minutes, counts).
class IntField extends StatelessWidget {
  const IntField({super.key, required this.controller, required this.label, this.prefix, this.suffix, this.min = 0, this.helper});
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;
  final int min;
  final String? helper;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, prefixText: prefix == null ? null : '$prefix ', suffixText: suffix, helperText: helper),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          if (n == null) return 'Enter a number';
          if (n < min) return 'At least $min';
          return null;
        },
      );
}

class DecimalField extends StatelessWidget {
  const DecimalField({super.key, required this.controller, required this.label, this.suffix});
  final TextEditingController controller;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a number' : null,
      );
}

class FormSection extends StatelessWidget {
  const FormSection(this.title, {super.key, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: context.text.titleLarge),
          const SizedBox(height: 12),
          for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ]),
      );
}

/// Runs a save with a spinner-free toast on failure; returns true on success.
Future<bool> runSave(BuildContext context, Future<void> Function() action, {String done = 'Saved'}) async {
  try {
    await action();
    if (context.mounted) context.toast(done);
    return true;
  } catch (e) {
    if (context.mounted) context.toast(errorText(e), error: true);
    return false;
  }
}

/// "Butter Croissant" → "butter-croissant"
String slugify(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
