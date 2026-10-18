import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import 'form_helpers.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider);
    final hubs = ref.watch(hubsProvider).value ?? const [];
    final me = ref.watch(currentUserProvider);
    String hubName(String? id) => hubs.where((h) => h.id == id).firstOrNull?.name ?? 'All branches';

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.person_add_alt), label: const Text('Add member')),
      body: team.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(teamProvider)),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
          for (final u in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: u.isAdmin ? context.colors.primaryContainer : context.colors.secondaryContainer,
                  child: Icon(u.isAdmin ? Icons.admin_panel_settings_outlined : Icons.soup_kitchen_outlined, size: 20),
                ),
                title: Text(u.name, style: TextStyle(decoration: u.isActive ? null : TextDecoration.lineThrough)),
                subtitle: Text('${u.email}\n${u.isAdmin ? 'Admin' : 'Staff · ${hubName(u.hubId)}'}${u.isActive ? '' : ' · deactivated'}'),
                isThreeLine: true,
                trailing: u.id == me?.id ? const Pill('You') : const Icon(Icons.chevron_right),
                onTap: () => _edit(context, ref, u),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AppUser? u) async {
    final hubs = ref.read(hubsProvider).value ?? const [];
    final name = TextEditingController(text: u?.name);
    final email = TextEditingController(text: u?.email);
    final phone = TextEditingController(text: u?.phone);
    final password = TextEditingController();
    var role = u?.role ?? UserRole.staff;
    String? hubId = u?.hubId ?? hubs.firstOrNull?.id;
    var active = u?.isActive ?? true;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(u == null ? 'Add team member' : 'Edit ${u.name}'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null),
                  const SizedBox(height: 12),
                  if (u == null) ...[
                    TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => (v ?? '').contains('@') ? null : 'Enter an email'),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: u == null ? 'Password' : 'New password (leave blank to keep)'),
                    validator: (v) => (u == null || (v ?? '').isNotEmpty) && (v ?? '').length < 8 ? 'At least 8 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: UserRole.staff, child: Text('Staff — orders & stock')),
                      DropdownMenuItem(value: UserRole.admin, child: Text('Admin — everything')),
                    ],
                    onChanged: (v) => set(() => role = v ?? role),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: hubId,
                    decoration: InputDecoration(labelText: 'Branch', helperText: role == UserRole.staff ? 'Staff only see this branch' : null),
                    items: [
                      if (role == UserRole.admin) const DropdownMenuItem<String?>(value: null, child: Text('All branches')),
                      for (final h in hubs) DropdownMenuItem<String?>(value: h.id, child: Text(h.name)),
                    ],
                    onChanged: (v) => set(() => hubId = v),
                  ),
                  if (u != null)
                    SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: const Text('Can sign in')),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => formKey.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final api = ref.read(apiProvider);
    await runSave(context, () async {
      if (u == null) {
        await api.createTeamMember(email: email.text.trim(), password: password.text, name: name.text.trim(), phone: phone.text.trim().isEmpty ? null : phone.text.trim(), role: role, hubId: hubId);
      } else {
        await api.updateTeamMember(u.id, {
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'role': role.wire,
          'hubId': hubId,
          'isActive': active,
          if (password.text.isNotEmpty) 'password': password.text,
        });
      }
      ref.invalidate(teamProvider);
    });
  }
}
