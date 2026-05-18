import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:news_cover/services/api_constants.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:news_cover/services/chat/socket_service.dart';

/**
 * FCM Service — Handles push notifications for Android & iOS.
 */
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localMsg = FlutterLocalNotificationsPlugin();
  final _storage = const FlutterSecureStorage();

  // ─────────────────────────────────────────────────────────────────────────────
  // Initial Setup
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      // 1. Request permission (iOS/Android 13+)
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // 3. Initialize Local Notifications (for showing foreground heads-up)
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit     = DarwinInitializationSettings();
      await _localMsg.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (resp) {
          // Handle tapping notification while app is open
          print('Notification tapped: ${resp.payload}');
          print('📡 [FCM] Local notification tapped. Waking socket...');
          SocketService().connect(force: true);
        },
      );

      // 4. Handle Foreground messages (manually show notification)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
        print('📡 [FCM] Foreground notification received. Waking socket...');
        SocketService().connect(force: true);
      });

      // 4b. Handle Background messages click
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📡 [FCM] App opened from background via notification. Waking socket...');
        SocketService().connect(force: true);
      });

      // 4c. Check if app launched from terminated state via notification click
      _fcm.getInitialMessage().then((RemoteMessage? initialMessage) {
        if (initialMessage != null) {
          print('📡 [FCM] App launched from terminated state via notification. Waking socket...');
          SocketService().connect(force: true);
        }
      });

      // 5. Setup Background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // 6. Token refresh listener
      _fcm.onTokenRefresh.listen((token) {
        syncToken(token);
      });

      // 7. Sync current token if already logged in
      final token = await _fcm.getToken();
      if (token != null) {
        await syncToken(token);
      }
    } catch (e) {
      print('⚠️ [FCM] Initialization failed (Firebase may not be available on this device): $e');
      // Continue app execution even if FCM fails
    }
  }

  /// Get the current registration token from Firebase.
  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Sync Token with Backend API
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> syncToken(String fcmToken) async {
    try {
      final jwtToken = await _storage.read(key: 'accessToken');
      if (jwtToken == null) return; // Not logged in yet
      
      final dio = Dio();
      dio.options.headers['Authorization'] = 'Bearer $jwtToken';

      // POST to our existing API endpoint
      final response = await dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.registerFcm}',
        data: {'fcmToken': fcmToken},
      );

      if (response.data['success'] == true) {
        print('✅ [FCM] Token synced with backend');
      }
    } catch (e) {
      print('❌ [FCM] Token sync failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Foreground Heads-up
  // ─────────────────────────────────────────────────────────────────────────────
  void _showLocalNotification(RemoteMessage message) {
    if (message.notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    
    final details = NotificationDetails(android: androidDetails);

    _localMsg.show(
      message.notification.hashCode,
      message.notification?.title,
      message.notification?.body,
      details,
      payload: message.data.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Handler (Top-level function outside class)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}
