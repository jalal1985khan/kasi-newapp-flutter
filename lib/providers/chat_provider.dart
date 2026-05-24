import 'package:flutter/material.dart';
import '../services/chat/chat_service.dart';
import '../services/chat/socket_service.dart';
import '../services/event_bus.dart';

class ChatProvider with ChangeNotifier {
  int _totalUnread = 0;
  int get totalUnread => _totalUnread;

  final ChatService _chatService = ChatService();
  final SocketService _socketService = SocketService();

  ChatProvider() {
    _init();
  }

  void _init() {
    // Initial fetch
    refreshUnread();

    // Listen for socket events that should trigger a refresh
    _socketService.on('message:receive', (_) => refreshUnread());
    _socketService.on('group:message:receive', (_) => refreshUnread());
    _socketService.on('group:message:new', (_) => refreshUnread());
    _socketService.on('conversation:update', (_) => refreshUnread());
    _socketService.on('group:update', (_) => refreshUnread());

    // Listen to FCM explicitly
    EventBus().stream.listen((event) {
      if (event == 'fcm_refresh') {
        refreshUnread();
      }
    });
    
    // Also refresh when connection is re-established
    _socketService.connectionStatus.listen((connected) {
      if (connected) refreshUnread();
    });
  }

  Future<void> refreshUnread() async {
    try {
      final count = await _chatService.getTotalUnreadCount();
      _totalUnread = count;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
    }
  }

  void setTotalUnread(int count) {
    _totalUnread = count;
    notifyListeners();
  }
}
