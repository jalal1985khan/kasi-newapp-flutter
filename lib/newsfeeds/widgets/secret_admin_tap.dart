import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../screens/login_screen.dart';
import '../../services/auth_service.dart';
import '../../screens/admin/admin_main_screen.dart';
import '../../screens/user/user_main_screen.dart';

class SecretAdminTap extends StatefulWidget {
  const SecretAdminTap({super.key});

  @override
  State<SecretAdminTap> createState() => _SecretAdminTapState();
}

class _SecretAdminTapState extends State<SecretAdminTap> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  static const int _requiredTaps = 5;
  final AuthService _authService = AuthService();
  String _appVersion = 'v8.0.1';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (e) {
      debugPrint('Error loading app version in SecretAdminTap: $e');
    }
  }

  void _handleTap() async {
    final now = DateTime.now();

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    if (_tapCount >= _requiredTaps) {
      _tapCount = 0;
      
      final user = await _authService.getUser();
      if (!mounted) return;

      if (user != null) {
        final role = user['role'];
        if (role == 'super_admin' || role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminMainScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => UserMainScreen(initialIndex: 0)),
          );
        }
      } else {
        // Not logged in, go to login page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            _appVersion,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

