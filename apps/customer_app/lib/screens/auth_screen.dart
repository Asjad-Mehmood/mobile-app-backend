import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      if (_register) {
        await session.register(email: _email.text, password: _password.text, name: _name.text, phone: _phone.text);
      } else {
        await session.signIn(_email.text, _password.text);
      }
      if (!mounted) return;
      final next = widget.next;
      if (context.canPop()) context.pop();
      if (next != null && next.isNotEmpty) {
        context.push(next);
      }
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
            Text(_register ? 'Join Crumb & Craft' : 'Welcome back', style: context.text.headlineLarge),
            const SizedBox(height: 8),
            Text(
              _register ? 'Create an account to order, track your bakes live and collect stamps.' : 'Sign in to order, track your bakes and collect stamps.',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            if (_register) ...[
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 14),
            if (_register) ...[
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(labelText: 'Mobile (optional)', hintText: '03xx xxxxxxx'),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? 'At least 8 characters' : null,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => (v ?? '').length < (_register ? 8 : 1) ? (_register ? 'Use at least 8 characters' : 'Enter your password') : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: 24),
            BakeryButton(label: _register ? 'Create account' : 'Sign in', loading: _busy, onPressed: _submit),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _register = !_register;
                _error = null;
              }),
              child: Text(_register ? 'Already have an account? Sign in' : 'New here? Create an account'),
            ),
          ]),
        ),
      ),
    );
  }
}
