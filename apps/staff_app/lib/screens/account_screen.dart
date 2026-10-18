import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final hubs = ref.watch(hubsProvider).value ?? const [];
    final hub = hubs.where((h) => h.id == user.hubId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: context.colors.primaryContainer, child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase())),
          title: Text(user.name, style: context.text.titleLarge),
          subtitle: Text('${user.email}\n${user.isAdmin ? 'Admin' : 'Staff'}${hub != null ? ' · ${hub.name}' : user.isAdmin ? ' · all branches' : ''}'),
          isThreeLine: true,
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Appearance'),
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Server'),
          subtitle: Text(ref.watch(serverUrlProvider)),
          onTap: () async {
            final url = await showServerUrlDialog(context, ref.read(serverUrlProvider));
            if (url != null) await ref.read(serverUrlProvider.notifier).set(url);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password_outlined),
          title: const Text('Change password'),
          onTap: () async {
            final current = TextEditingController(), next = TextEditingController();
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Change password'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
                  const SizedBox(height: 12),
                  TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')),
                ]),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
                ],
              ),
            );
            if (ok != true) return;
            try {
              await ref.read(apiProvider).changePassword(current.text, next.text);
              if (context.mounted) context.toast('Password changed');
            } catch (e) {
              if (context.mounted) context.toast(errorText(e), error: true);
            }
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout, color: context.colors.error),
          title: Text('Sign out', style: TextStyle(color: context.colors.error)),
          onTap: () => ref.read(sessionProvider.notifier).signOut(),
        ),
      ]),
    );
  }
}
