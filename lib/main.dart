import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/news_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/general_pages/splash_screen.dart';
import 'screens/special_widgets/call_overlay.dart';
import 'screens/special_widgets/group_call_overlay.dart';
import 'services/chat/socket_service.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/update/app_update_manager.dart';
import 'utils/premium_widgets.dart';

import 'package:audio_session/audio_session.dart';

/// Global navigator key — lets SocketService show call UI from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Shared future that completes once Firebase + AuthService are ready.
/// Splash screen awaits this while it is already visible — no black screen.
late final Future<void> appInitFuture;

void main() {
  // Must be synchronous — no async, no awaits before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Kick off all heavy init work as a future (non-blocking)
  appInitFuture = _initializeApp();

  // Show the UI IMMEDIATELY — splash renders with zero delay
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NewsProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const MyApp(),
    ),
  );

  // Wire all global event handlers after runApp
  _wireGlobalHandlers();

  // Start background services once init completes
  appInitFuture.then((_) => _initBackgroundServices()).catchError((e) {
    debugPrint('⚠️ [App Init] Error: $e');
  });
}

/// Sequential inits that must complete before the app navigates away from splash.
Future<void> _initializeApp() async {
  await Firebase.initializeApp();
  await AuthService().init();
}

/// Global event handlers — wired once, work everywhere.
void _wireGlobalHandlers() {
  // Incoming 1-to-1 call
  SocketService().setIncomingCallHandler((data) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    
    IncomingCallOverlayManager.showGlobal(
      overlay,
      callerName: data['callerName'] ?? 'Unknown',
      callerId:   data['callerId']  ?? '',
      callerImage: data['callerImage'] ?? '',
      callId:     data['callId']    ?? '',
      roomName:   data['roomName']  ?? '',
    );
  });

  // Incoming group call
  SocketService().setIncomingGroupCallHandler((data) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    if (GroupCallOverlayManager.isActive) return;
    IncomingGroupCallOverlayManager.showGlobal(
      overlay,
      callId:      data['callId']      ?? '',
      groupId:     data['groupId']     ?? '',
      groupName:   data['groupName']   ?? 'Group Call',
      hostName:    data['hostName']    ?? 'Host',
      hostImage:   data['hostImage']   ?? '',
      memberCount: data['memberCount'] ?? 2,
    );
  });

  // Forced logout (company deactivated)
  SocketService().setForceLogoutHandler((message) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // 1. Show non-cancelable alert dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User must press the button
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Access Restricted'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () async {
                // 2. Clear credentials and navigate out
                Navigator.of(dialogContext).pop(); // Close dialog
                await AuthService().logout();
                if (navigatorKey.currentState != null) {
                  navigatorKey.currentState!.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const SplashScreen()),
                    (route) => false,
                  );
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  });
}

/// Heavy services initialized after UI is shown — never blocks splash screen.
void _initBackgroundServices() {
  // FCM: permissions + token sync (network call — fire and forget)
  FCMService().init().catchError((e) {
    debugPrint('⚠️ [FCM] Background init failed: $e');
  });

  // AudioSession: VOIP audio routing config for call feature
  AudioSession.instance.then((session) {
    session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      androidWillPauseWhenDucked: true,
    ));
  }).catchError((e) {
    debugPrint('⚠️ [AudioSession] Background init failed: $e');
  });

  // OTA Update: poll server on every cold start, works regardless of login state.
  // Small delay lets the navigator settle so the dialog has a valid context.
  Future.delayed(const Duration(milliseconds: 1500), () {
    AppUpdateManager().checkAndShow();
  });

  // Real-time update push via socket: fired when admin publishes a new release.
  // Registered globally so it works on ANY screen, logged-in or not.
  SocketService().on('app:update_available', (data) {
    if (data != null && data['release'] != null) {
      AppUpdateManager().showFromRelease(
        Map<String, dynamic>.from(data['release'] as Map),
      );
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'Daily News',
      debugShowCheckedModeBanner: false,
      scrollBehavior: PremiumScrollBehavior(),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A884),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        splashColor: Colors.black.withOpacity(0.05),
        highlightColor: Colors.transparent,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A884),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF111B21),
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.transparent,
      ),
      home: const SplashScreen(),
      navigatorKey: navigatorKey,
    );
  }
}
