import 'package:flutter/material.dart';
import 'dart:async';
import '../../newsfeeds/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/chat/socket_service.dart';
import '../admin/dashboard_screen.dart';
import '../user/user_dashboard_screen.dart';
import '../user/user_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final AuthService _authService = AuthService();

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
    // Wait for animation to show for a bit
    await Future.delayed(const Duration(seconds: 3));
    
    if (!mounted) return;

    final user = await _authService.getUser();
    if (user != null) {
      // User is logged in, connect socket in background
      SocketService().connect();
    }

    // Always go to News Home first
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
