import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../api_constants.dart';
import '../auth_service.dart';

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  IO.Socket? socket;
  final AuthService _authService = AuthService();
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool get isConnected => socket?.connected ?? false;
  bool _isRefreshing = false;
  Completer<IO.Socket?>? _connectCompleter;

  Future<IO.Socket?> connect() async {
    if (_connectCompleter != null) return _connectCompleter!.future;
    
    if (socket != null && socket!.connected) return socket;

    _connectCompleter = Completer<IO.Socket?>();

    try {
      final token = await _authService.getAccessToken();
      if (token == null) {
        _connectCompleter!.complete(null);
        _connectCompleter = null;
        return null;
      }

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
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .setExtraHeaders({'Connection': 'upgrade', 'Upgrade': 'websocket'})
            .setQuery({'pingTimeout': '60000', 'pingInterval': '25000'})
            .enableForceNew()
            .enableReconnection()
            .setReconnectionDelay(2000)
            .setReconnectionAttempts(999999)
            .build()
          ..addAll({
            'forceNew': true,
            'force new connection': true,
          }),
      );

      _setupBasicListeners(socketUrl);
      
      _connectCompleter!.complete(socket);
      _connectCompleter = null;
      return socket;
    } catch (e) {
      _connectCompleter!.completeError(e);
      _connectCompleter = null;
      return null;
    }
  }

  void _setupBasicListeners(String socketUrl) {
    if (socket == null) return;

    // Re-attach all registered listeners
    _listeners.forEach((event, handlers) {
      for (var h in handlers) {
        socket!.off(event);
        socket!.on(event, h);
      }
    });

    socket!.onConnect((_) {
      print('✅ [Socket] Connected to $socketUrl');
      _connectionStatusController.add(true);
    });

    socket!.onDisconnect((reason) {
      print('❌ [Socket] Disconnected: $reason');
      _connectionStatusController.add(false);
    });

    socket!.onConnectError((err) async {
      print('🔴 [Socket] Connect Error: $err');

      if (_isRefreshing) return;

      final errStr = err.toString().toLowerCase();
      bool isTokenError = 
          errStr.contains('token') || 
          errStr.contains('auth') ||
          errStr.contains('expired') ||
          (err is Map && (
            err['message']?.toString().toLowerCase().contains('token') == true ||
            err['message']?.toString().toLowerCase().contains('expired') == true ||
            err['error']?.toString().toLowerCase().contains('token') == true
          ));

      if (isTokenError) {
        _isRefreshing = true;
        print('🔄 [Socket] Auth error. Refreshing token...');

        // Wait a bit before refresh to avoid spam
        await Future.delayed(const Duration(milliseconds: 1000));
        
        final newToken = await _authService.refreshAccessToken();

        if (newToken != null) {
          print('✅ [Socket] Token refreshed. Re-initializing socket...');
          try {
            if (socket != null && socket!.io.options != null) {
              socket!.io.options!['auth'] = {'token': newToken};
            }
          } catch (_) {}
          // Fully dispose and reconnect to ensure the NEW token is used
          socket?.dispose();
          socket = null;
          connect();
        } else {
          print('❌ [Socket] Token refresh failed. User might need to re-login.');
        }
        
        _isRefreshing = false;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 [Socket] App Lifecycle State Changed: $state');
    if (state == AppLifecycleState.resumed) {
      print('📱 [Socket] App resumed: checking/forcing reconnection...');
      if (socket == null || !socket!.connected) {
        connect();
      }
    }
  }
}
