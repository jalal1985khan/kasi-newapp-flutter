import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';
import '../dashboard_screen.dart';
import '../bulk_user_add_screen.dart';
import '../website_resourses_screen.dart';
import '../employee_list_screen.dart';
import '../chat_call_screen.dart';
import '../../status_screen.dart';

class AdminBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const AdminBottomNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final int unreadCount = context.watch<ChatProvider>().totalUnread;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);
    final Color waGrey = isDark ? const Color(0xFF8696A0) : Colors.black54;
    final Color navBg = isDark ? waDarkBg : Colors.white;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex < 0 ? 0 : currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: navBg,
        selectedItemColor: currentIndex < 0 ? waGrey : waTeal,
        unselectedItemColor: waGrey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        iconSize: 24,
        onTap: (index) {
          if (index == currentIndex) return;

          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const DashboardScreen(),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
            case 1:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const BulkUserAddScreen(),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
            case 2:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const EmployeeListScreen(),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
            case 3:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const ChatCallScreen(),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
            case 4:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const WebsiteResourcesScreen(),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
            case 5:
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const StatusScreen(isAdmin: true),
                  transitionDuration: Duration.zero,
                ),
              );
              break;
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.dashboard_outlined)),
            activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.dashboard)),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.upload_file_outlined)),
            activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.upload_file)),
            label: 'Excel',
          ),
          const BottomNavigationBarItem(
            icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.people_outline)),
            activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.people)),
            label: 'Users',
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
            icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.web_outlined)),
            activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.web)),
            label: 'Web',
          ),
          const BottomNavigationBarItem(
            icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.circle_outlined)),
            activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.circle)),
            label: 'Status',
          ),
        ],
      ),
    );
  }
}
