import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';

class UserBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;
  
  const UserBottomNavigationBar({super.key, required this.currentIndex, this.onTap});

  @override
  Widget build(BuildContext context) {
    final int unreadCount = context.watch<ChatProvider>().totalUnread;
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);
    const Color waGrey = Color(0xFF8696A0);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex == -1 ? 0 : currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? waDarkBg : Colors.white,
        selectedItemColor: currentIndex == -1 ? waGrey : waTeal,
        unselectedItemColor: isDark ? waGrey : Colors.black54,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        iconSize: 26,
        onTap: onTap ?? (index) {},
        items: [
          const BottomNavigationBarItem(
            icon: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(Icons.dashboard_outlined),
            ),
            activeIcon: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(Icons.dashboard),
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Badge(
                label: Text('$unreadCount'),
                isLabelVisible: unreadCount > 0,
                backgroundColor: waTeal,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            activeIcon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Badge(
                label: Text('$unreadCount'),
                isLabelVisible: unreadCount > 0,
                backgroundColor: waTeal,
                child: const Icon(Icons.chat_bubble),
              ),
            ),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(Icons.person_outline),
            ),
            activeIcon: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(Icons.person),
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
