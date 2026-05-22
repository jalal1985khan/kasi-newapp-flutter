import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'user_dashboard_screen.dart';
import 'user_chat_call_screen.dart';
import 'user_profile_screen.dart';
import 'common_widgets/user_bottom_navigationbar.dart';
import '../../services/chat/socket_service.dart';

class UserMainScreen extends StatefulWidget {
  final int initialIndex;
  
  const UserMainScreen({super.key, this.initialIndex = 0});

  @override
  State<UserMainScreen> createState() => UserMainScreenState();

  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<UserMainScreenState>();
    if (state != null) {
      state.setTab(index);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => UserMainScreen(initialIndex: index)),
      );
    }
  }
}

class UserMainScreenState extends State<UserMainScreen> {
  late int _currentIndex;
  
  final List<Widget> _screens = [
    const UserDashboardScreen(),
    const UserChatCallScreen(),
    const UserProfileScreen(),
  ];

  void setTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    if (index == 1) {
      SocketService().connect(force: true);
    }
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();

    if (index == 1) {
      debugPrint('📡 [Navigation] User tapped Chat tab. Waking socket...');
      SocketService().connect(force: true);
    }

    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: UserBottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
