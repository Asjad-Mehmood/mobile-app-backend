import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A change pushed by the server (`catalog.updated`, `stock.updated`, `order.updated`, ...).
class SyncEvent {
  const SyncEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;

  String? get orderId => data['orderId'] as String?;
  String? get hubId => data['hubId'] as String?;
  String? get status => data['status'] as String?;
  List<String> get productIds => (data['productIds'] as List? ?? const []).map((e) => '$e').toList();

  bool get isOrder => type.startsWith('order.');
  bool get isNewOrder => type == 'order.created';
}

enum RealtimeState { connecting, live, offline }

/// Keeps a WebSocket to the server open, reconnecting with backoff, and turns
/// messages into [SyncEvent]s. Both apps refresh their data from these events.
class RealtimeClient {
  RealtimeClient({required String baseUrl, this.token}) : _url = _wsUrl(baseUrl, token);

  final String? token;
  final Uri _url;
  final _events = StreamController<SyncEvent>.broadcast();
  final _state = StreamController<RealtimeState>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _ping;
  int _attempt = 0;
  bool _closed = false;
  RealtimeState _current = RealtimeState.connecting;

  Stream<SyncEvent> get events => _events.stream;
  Stream<RealtimeState> get states => _state.stream;
  RealtimeState get state => _current;

  static Uri _wsUrl(String baseUrl, String? token) {
    final http = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      path: '${http.path}/ws',
      queryParameters: token == null ? null : {'token': token},
    );
  }

  void _set(RealtimeState s) {
    if (_current == s) return;
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  void connect() {
    if (_closed) return;
    _set(RealtimeState.connecting);
    try {
      final channel = WebSocketChannel.connect(_url);
      _channel = channel;
      _sub = channel.stream.listen(_onMessage, onError: (_) => _scheduleReconnect(), onDone: _scheduleReconnect, cancelOnError: true);
      channel.ready.then((_) {
        _attempt = 0;
        _set(RealtimeState.live);
        _ping?.cancel();
        _ping = Timer.periodic(const Duration(seconds: 30), (_) => _safeSend('ping'));
      }, onError: (_) => _scheduleReconnect());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _safeSend(String m) {
    try {
      _channel?.sink.add(m);
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    try {
      final j = jsonDecode('$raw');
      if (j is! Map<String, dynamic>) return;
      final type = j['type'] as String? ?? '';
      if (type == 'ping') {
        _safeSend('ping');
        return;
      }
      if (type == 'pong' || type == 'hello') return;
      _events.add(SyncEvent(type, j));
    } catch (_) {}
  }

  void _scheduleReconnect() {
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (_closed) return;
    _set(RealtimeState.offline);
    _retry?.cancel();
    final seconds = min(30, pow(2, _attempt).toInt());
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), connect);
  }

  /// Reconnect immediately (e.g. when the app returns to the foreground).
  void nudge() {
    if (_closed || _current == RealtimeState.live) return;
    _retry?.cancel();
    _attempt = 0;
    connect();
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _events.close();
    await _state.close();
  }
}
