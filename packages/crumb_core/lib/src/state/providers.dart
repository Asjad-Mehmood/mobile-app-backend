import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/realtime.dart';
import '../models/models.dart';
import 'storage.dart';

/// Overridden in each app's `main()` with an opened [AppStorage].
final storageProvider = Provider<AppStorage>((ref) => throw UnimplementedError('Override storageProvider in main()'));

/// The API server URL (build-time default, changeable in Settings).
final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() => ref.read(storageProvider).serverUrl;

  Future<void> set(String? url) async {
    await ref.read(storageProvider).setServerUrl(url);
    state = ref.read(storageProvider).serverUrl;
  }
}

/// Signed-in user + token. `null` data = signed out.
class Session {
  const Session(this.token, this.user);
  final String token;
  final AppUser user;
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final storage = ref.read(storageProvider);
    final baseUrl = ref.watch(serverUrlProvider);
    final token = await storage.readToken();
    if (token == null) return null;
    try {
      final user = await ApiClient(baseUrl: baseUrl, token: token).me();
      return Session(token, user);
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.status == 403) {
        await storage.writeToken(null);
        return null;
      }
      // Offline at launch: keep the token, retry when the user refreshes.
      rethrow;
    }
  }

  ApiClient get _anon => ApiClient(baseUrl: ref.read(serverUrlProvider));

  Future<AppUser> signIn(String email, String password, {bool Function(AppUser)? allow, String? deniedMessage}) async {
    final r = await _anon.login(email.trim(), password);
    if (allow != null && !allow(r.user)) {
      throw ApiException(403, 'FORBIDDEN', deniedMessage ?? "This account can't sign in here.");
    }
    await ref.read(storageProvider).writeToken(r.token);
    state = AsyncData(Session(r.token, r.user));
    return r.user;
  }

  Future<AppUser> register({required String email, required String password, required String name, String? phone}) async {
    final r = await _anon.register(email: email.trim(), password: password, name: name.trim(), phone: phone?.trim());
    await ref.read(storageProvider).writeToken(r.token);
    state = AsyncData(Session(r.token, r.user));
    return r.user;
  }

  void updateUser(AppUser user) {
    final s = state.value;
    if (s != null) state = AsyncData(Session(s.token, user));
  }

  Future<void> signOut() async {
    await ref.read(storageProvider).writeToken(null);
    state = const AsyncData(null);
  }
}

/// Current user, or null when signed out / still loading.
final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(sessionProvider).value?.user);

/// API client bound to the current server and token.
final apiProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final token = ref.watch(sessionProvider.select((s) => s.value?.token));
  return ApiClient(
    baseUrl: baseUrl,
    token: token,
    onUnauthorized: () => Future.microtask(() => ref.read(sessionProvider.notifier).signOut()),
  );
});

/// Live connection to the server; reconnects whenever the server or user changes.
final realtimeProvider = Provider<RealtimeClient>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final token = ref.watch(sessionProvider.select((s) => s.value?.token));
  final client = RealtimeClient(baseUrl: baseUrl, token: token)..connect();
  ref.onDispose(client.close);
  return client;
});

final realtimeStateProvider = StreamProvider<RealtimeState>((ref) {
  final rt = ref.watch(realtimeProvider);
  return rt.states.startWith(rt.state);
});

final syncEventsProvider = StreamProvider<SyncEvent>((ref) => ref.watch(realtimeProvider).events);

/// Business settings (fees, cake options, windows). Refreshed on `settings.updated`.
final configProvider = FutureProvider<BusinessSettings>((ref) async {
  ref.watch(serverUrlProvider);
  return ref.read(apiProvider).config();
});

final hubsProvider = FutureProvider<List<Hub>>((ref) async {
  ref.watch(serverUrlProvider);
  return ref.read(apiProvider).hubs();
});

/// Theme mode stored per device.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values.byName(ref.read(storageProvider).getString('theme_mode') ?? 'system');

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(storageProvider).setString('theme_mode', mode.name);
  }
}

/// Mixin-free helper: invalidate shared providers for events every app cares about.
void handleSharedSyncEvent(Ref ref, SyncEvent e) {
  switch (e.type) {
    case 'settings.updated':
      ref.invalidate(configProvider);
    case 'hubs.updated':
      ref.invalidate(hubsProvider);
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

/// Re-checks a periodic clock — used by countdowns and slot validity.
final clockProvider = StreamProvider<DateTime>((ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()));

/// Brings realtime back after the app resumes from the background.
class RealtimeLifecycle extends ConsumerStatefulWidget {
  const RealtimeLifecycle({super.key, required this.child, this.onResume});
  final Widget child;
  final VoidCallback? onResume;

  @override
  ConsumerState<RealtimeLifecycle> createState() => _RealtimeLifecycleState();
}

class _RealtimeLifecycleState extends ConsumerState<RealtimeLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(realtimeProvider).nudge();
      // Anything missed while the socket was asleep gets re-fetched.
      unawaited(Future(() => widget.onResume?.call()));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
