import 'package:flutter/material.dart';
import '../../newsfeeds/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/chat/socket_service.dart';
import '../../main.dart' show appInitFuture;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    _checkSession();
  }

  Future<void> _checkSession() async {
    // Run both simultaneously:
    // 1. appInitFuture  — Firebase init + AuthService.init() (started in main())
    // 2. 800ms minimum — so the logo animation feels intentional, not a flash
    // The splash is ALREADY visible while this work happens — zero black screen.
    await Future.wait([
      appInitFuture,
      Future.delayed(const Duration(milliseconds: 800)),
    ]);

    if (!mounted) return;

    // AuthService.init() is now complete — user is in memory, no extra network call
    final user = AuthService.userNotifier.value;
    if (user != null) {
      // Already logged in — connect socket in background (non-blocking)
      SocketService().connect();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  //test
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo/logo.png',
                width: 150,
                height: 150,
              ),
              const SizedBox(height: 24),
              const Text(
                'Daily News',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A73E8),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A73E8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
