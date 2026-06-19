import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Lifecycle of the single WebSocket connection to the Sarthi backend.
enum WsConnectionState { disconnected, connecting, connected }

/// A thin, transport-only wrapper around one WebSocket connection to the Go
/// backend.
///
/// Per the project's layered architecture this lives in the **data layer**: its
/// only jobs are to open/close the socket, encode outgoing maps as JSON, decode
/// incoming frames, and surface two broadcast streams. It holds no business
/// logic and no UI state — view models (and Repositories) listen to it and
/// decide what messages mean.
///
/// Example:
/// ```dart
/// final ws = WebSocketService(uri: Uri.parse('ws://10.0.2.2:8080/ws/driver'));
/// ws.connect();
/// ws.messages.listen((msg) => print('offer: $msg'));
/// ws.send({'type': 'location', 'lat': 12.97, 'lng': 77.60});
/// ```
class WebSocketService {
  WebSocketService({required this.uri});

  /// Backend WS endpoint. On the Android emulator the host machine is reachable
  /// at `10.0.2.2`, e.g. `ws://10.0.2.2:8080/ws/driver`.
  final Uri uri;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<WsConnectionState> _state =
      StreamController<WsConnectionState>.broadcast();

  WsConnectionState _current = WsConnectionState.disconnected;

  /// Decoded JSON objects pushed by the server (ride offers, ride status, …).
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Connection-state transitions, so the UI can show "Connecting…" etc.
  Stream<WsConnectionState> get connectionState => _state.stream;

  /// The latest known connection state (without listening to the stream).
  WsConnectionState get currentState => _current;

  /// Opens the socket. No-op if already connecting or connected; use
  /// [reconnect] to force a fresh connection.
  void connect() {
    if (_current != WsConnectionState.disconnected) return;
    _setState(WsConnectionState.connecting);
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _setState(WsConnectionState.connected);
    } catch (error) {
      _onError(error);
    }
  }

  /// Sends a JSON-encodable payload. Silently drops the message when not
  /// connected — callers that need delivery guarantees should buffer upstream.
  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || _current != WsConnectionState.connected) return;
    channel.sink.add(jsonEncode(payload));
  }

  /// Closes the current socket (if any) and opens a new one.
  Future<void> reconnect() async {
    await _teardownSocket();
    _setState(WsConnectionState.disconnected);
    connect();
  }

  /// Releases every resource. The instance must not be reused afterwards.
  Future<void> dispose() async {
    await _teardownSocket();
    await _messages.close();
    await _state.close();
  }

  void _onData(dynamic raw) {
    if (raw is! String) return; // backend speaks JSON text frames
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _messages.add(decoded);
      }
    } on FormatException {
      // Ignore malformed frames rather than crashing the listen loop.
    }
  }

  void _onError(Object error) => _setState(WsConnectionState.disconnected);

  void _onDone() => _setState(WsConnectionState.disconnected);

  void _setState(WsConnectionState next) {
    _current = next;
    if (!_state.isClosed) _state.add(next);
  }

  Future<void> _teardownSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }
}
