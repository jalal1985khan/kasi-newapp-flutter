import 'package:flutter/material.dart';
import '../../screens/login_screen.dart';

class SecretAdminTap extends StatefulWidget {
  const SecretAdminTap({super.key});

  @override
  State<SecretAdminTap> createState() => _SecretAdminTapState();
}

class _SecretAdminTapState extends State<SecretAdminTap> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  static const int _requiredTaps = 5; // Number of taps required

  void _handleTap() {
    final now = DateTime.now();

    // Reset if more than 2 seconds between taps
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    if (_tapCount >= _requiredTaps) {
      _tapCount = 0;
      // Navigate to admin login
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'v1.0.0', // Innocent looking text
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
