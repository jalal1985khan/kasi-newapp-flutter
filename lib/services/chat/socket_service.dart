import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../api_constants.dart';
import '../auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final AuthService _authService = AuthService();
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool get isConnected => socket?.connected ?? false;
  bool _isRefreshing = false;

  Future<IO.Socket?> connect() async {
    if (socket != null && socket!.connected) return socket;

    final token = await _authService.getAccessToken();
    if (token == null) return null;

    String socketUrl = ApiConstants.socketUrl.trim();
    if (socketUrl.endsWith('/')) {
      socketUrl = socketUrl.substring(0, socketUrl.length - 1);
    }

    bool isLocal =
        socketUrl.contains('localhost') ||
        socketUrl.contains('127.0.0.1') ||
        RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(socketUrl);

    if (isLocal && !socketUrl.contains(':3001')) {
      socketUrl = '$socketUrl:3001';
    }

    if (socket != null) {
      socket!.dispose();
      socket = null;
    }

    socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket']) // Force websocket for stability
          .setAuth({'token': token})
          .setExtraHeaders({'Connection': 'upgrade', 'Upgrade': 'websocket'})
          .setQuery({'pingTimeout': '60000', 'pingInterval': '25000'})
          .build(),
    );

    // Re-attach all registered listeners
    _listeners.forEach((event, handlers) {
      for (var h in handlers) {
        socket!.off(event); // Clear any internal duplicates
        socket!.on(event, h);
      }
    });

    socket!.onConnect((_) {
      print('Socket Connected to $socketUrl');
      _connectionStatusController.add(true);
    });
    socket!.onDisconnect((_) {
      print('Socket Disconnected');
      _connectionStatusController.add(false);
    });

    socket!.onConnectError((err) async {
      print('Socket Connect Error: $err (Type: ${err.runtimeType})');

      if (_isRefreshing) return;

      final errStr = err.toString().toLowerCase();
      bool isTokenError = 
          errStr.contains('token') || 
          errStr.contains('auth') ||
          (err is Map && (
            err['message']?.toString().toLowerCase().contains('token') == true ||
            err['error']?.toString().toLowerCase().contains('token') == true
          ));

      if (isTokenError) {
        _isRefreshing = true;
        print('🔄 [Socket] Auth/Token error detected. Refreshing key...');

        socket?.disconnect();
        final newToken = await _authService.getAccessToken();

        if (newToken != null && socket != null) {
          var options = socket!.io.options;
          if (options != null) {
            options['auth'] = {'token': newToken};
            print('✅ [Socket] Key refreshed. Reconnecting...');

            Future.delayed(const Duration(milliseconds: 1000), () {
              socket?.connect();
              _isRefreshing = false;
            });
          }
        } else {
          _isRefreshing = false;
        }
      }
    });

    socket!.on('call:incoming', (data) {
      if (_onIncomingCall != null) _onIncomingCall!(data);
    });

    socket!.on('company:logout', (data) {
      if (_onForceLogout != null) {
        String msg = data['message'] ?? 'Your session has ended.';
        _onForceLogout!(msg);
      }
    });

    return socket;
  }

  final Map<String, List<Function(dynamic)>> _listeners = {};

  Function(dynamic)? _onIncomingCall;
  void setIncomingCallHandler(Function(dynamic) handler) {
    _onIncomingCall = handler;
  }

  Function(String)? _onForceLogout;
  void setForceLogoutHandler(Function(String) handler) {
    _onForceLogout = handler;
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
  }

  void emit(String event, dynamic data) {
    if (socket != null && socket!.connected) {
      socket!.emit(event, data);
    } else {
      connect().then((s) => s?.emit(event, data));
    }
  }

  void on(String event, Function(dynamic) handler) {
    // Only add if this specific handler instance isn't already registered for this event
    final handlers = _listeners.putIfAbsent(event, () => []);
    if (!handlers.contains(handler)) {
      handlers.add(handler);
      socket?.on(event, handler);
    }
  }

  void off(String event, [Function(dynamic)? handler]) {
    if (handler != null) {
      // Remove specific handler
      _listeners[event]?.remove(handler);
      socket?.off(event, handler);
    } else {
      // Remove all handlers for this event
      _listeners.remove(event);
      socket?.off(event);
    }
  }

  void clearListeners() {
    _listeners.forEach((event, handlers) {
      socket?.off(event);
    });
    _listeners.clear();
  }
}
