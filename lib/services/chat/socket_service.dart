import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../api_constants.dart';
import '../auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final AuthService _authService = AuthService();

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

    print('Connecting to Socket Server at: $socketUrl');

    socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .setExtraHeaders({'Connection': 'upgrade', 'Upgrade': 'websocket'})
          .build(),
    );

    // Re-attach all registered listeners
    _listeners.forEach((event, handlers) {
      for (var h in handlers) {
        socket!.off(event); // Clear any internal duplicates
        socket!.on(event, h);
      }
    });

    socket!.onConnect((_) => print('Socket Connected to $socketUrl'));
    socket!.onDisconnect((_) => print('Socket Disconnected'));

    bool isRefreshing = false;

    socket!.onConnectError((err) async {
      print('Socket Connect Error: $err');

      if (isRefreshing) return; // Prevent multiple simultaneous refreshes

      // If the error is about an expired token, try to refresh it and reconnect
      bool isTokenError =
          err.toString().contains('Invalid or expired token') ||
          (err is Map && err['message']?.toString().contains('token') == true);

      if (isTokenError) {
        isRefreshing = true;
        print(
          '🔄 [Socket] Expired token detected. Refreshing key before retry...',
        );

        // 1. Temporarily stop the socket to prevent instant retries
        socket?.disconnect();

        // 2. Fetch the new token
        final newToken = await _authService.getAccessToken();

        if (newToken != null && socket != null) {
          // 3. Update the auth options
          var options = socket!.io.options;
          if (options != null) {
            options['auth'] = {'token': newToken};
            print('✅ [Socket] Key refreshed. Reconnecting now...');

            // 4. Wait a tiny bit for the socket to settle, then connect
            Future.delayed(const Duration(milliseconds: 500), () {
              socket?.connect();
              isRefreshing = false;
            });
          }
        } else {
          isRefreshing = false;
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
    _listeners.putIfAbsent(event, () => []).add(handler);
    socket?.on(event, handler);
  }

  void off(String event) {
    _listeners.remove(event);
    socket?.off(event);
  }
}
