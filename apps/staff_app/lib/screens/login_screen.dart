import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.offline = false});
  final bool offline;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your work email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(
            _email.text,
            _password.text,
            allow: (u) => u.isStaffOrAdmin,
            deniedMessage: 'This app is for Crumb & Craft staff. Customers can use the Crumb & Craft app.',
          );
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverUrlProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(28), children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.soup_kitchen_rounded, size: 36, color: context.colors.onPrimaryContainer),
                ),
                const SizedBox(height: 20),
                Text('Crumb & Craft', style: context.text.headlineLarge, textAlign: TextAlign.center),
                Text('Kitchen & admin', style: context.text.titleMedium?.copyWith(color: context.colors.primary), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                if (widget.offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text("Couldn't reach the server to restore your session.", style: TextStyle(color: context.colors.error), textAlign: TextAlign.center),
                  ),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.badge_outlined)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: !_show,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: context.colors.error)),
                ],
                const SizedBox(height: 24),
                BakeryButton(label: 'Sign in', loading: _busy, onPressed: _submit),
                const SizedBox(height: 20),
                TextButton.icon(
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: Text('Server: $server', overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final url = await showServerUrlDialog(context, server);
                    if (url != null) await ref.read(serverUrlProvider.notifier).set(url);
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
