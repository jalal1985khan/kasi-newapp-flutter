import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/news_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/general_pages/splash_screen.dart';
import 'screens/special_widgets/call_overlay.dart';
import 'services/chat/socket_service.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'utils/premium_widgets.dart';

import 'package:audio_session/audio_session.dart';

/// Global navigator key — lets SocketService show call UI from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Audio Session for VOIP
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.defaultToSpeaker,
    avAudioSessionMode: AVAudioSessionMode.voiceChat,
    avAudioSessionRouteSharingPolicy:
        AVAudioSessionRouteSharingPolicy.defaultPolicy,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      flags: AndroidAudioFlags.none,
      usage: AndroidAudioUsage.voiceCommunication,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
    androidWillPauseWhenDucked: true,
  ));
  
  // 1. Initialize Firebase Core
  await Firebase.initializeApp();

  // 2. Initialize FCM (Permissions + Listeners + Token sync)
  await FCMService().init();

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

  // Wire incoming-call socket events globally
  SocketService().setIncomingCallHandler((data) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    
    IncomingCallOverlayManager.showGlobal(
      overlay,
      callerName: data['callerName'] ?? 'Unknown',
      callerId:   data['callerId']  ?? '',
      callId:     data['callId']    ?? '',
      roomName:   data['roomName']  ?? '',
    );
  });

  // Wire forced-logout events globally 
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
