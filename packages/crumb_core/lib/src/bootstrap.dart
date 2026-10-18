import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'state/storage.dart';
import 'theme/theme.dart';

/// Starts an app safely: draws a splash on the very first frame, opens storage with a
/// time limit, and shows any startup or build error as readable text instead of a black screen.
void bootstrapCrumbApp(Widget app) {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _startupError.value ??= details.exceptionAsString();
    };
    ErrorWidget.builder = (details) => _ErrorText(details.exceptionAsString());
    runApp(_Boot(app: app));
  }, (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    _startupError.value ??= '$error';
  });
}

final _startupError = ValueNotifier<String?>(null);

class _Boot extends StatefulWidget {
  const _Boot({required this.app});
  final Widget app;

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppStorage? _storage;
  bool _appShown = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    _startupError.value = null;
    try {
      final storage = await AppStorage.open().timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _storage = storage);
    } catch (e) {
      _startupError.value = "Couldn't open the app's storage: $e";
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _startupError,
      builder: (context, error, _) {
        // Errors after the app is running are shown by the app itself (ErrorWidget / toasts).
        if (error != null && !_appShown) {
          return _Plain(child: _ErrorText(error, onRetry: () {
            setState(() => _storage = null);
            _open();
          }));
        }
        final storage = _storage;
        if (storage == null) return const _Plain(child: _Splash());
        _appShown = true;
        return ProviderScope(overrides: [storageProvider.overrideWithValue(storage)], child: widget.app);
      },
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: bakeryLightTheme,
        darkTheme: bakeryDarkTheme,
        home: Scaffold(body: SafeArea(child: child)),
      );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bakery_dining_rounded, size: 64, color: context.colors.primary),
          const SizedBox(height: 16),
          Text('Crumb & Craft', style: context.text.headlineMedium),
          const SizedBox(height: 24),
          const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        ]),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFFDF9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            const Icon(Icons.error_outline_rounded, color: Color(0xFFC84B31), size: 40),
            const SizedBox(height: 12),
            const Text('Something went wrong while starting',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF2A1F1B))),
            const SizedBox(height: 8),
            const Text('Please send a screenshot of this screen to the developer.', style: TextStyle(color: Color(0xFF52443C))),
            const SizedBox(height: 16),
            SelectableText(message, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF2A1F1B))),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}
