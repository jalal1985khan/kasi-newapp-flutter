import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/auth_service.dart';
import '../../../providers/theme_provider.dart';
import '../../login_screen.dart';
import '../user_dashboard_screen.dart';
import '../user_profile_screen.dart';
import '../user_chat_call_screen.dart';
import '../../../newsfeeds/home_screen.dart';
import '../../../utils/premium_widgets.dart';
import 'package:flutter/services.dart';

class UserDrawer extends StatefulWidget {
  const UserDrawer({super.key});

  @override
  State<UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<UserDrawer> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final int unreadCount = context.watch<ChatProvider>().totalUnread;
    final AuthService authService = AuthService();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Drawer(
      backgroundColor: isDark ? waDarkBg : Colors.white,
      child: Column(
        children: [
          FutureBuilder<Map<String, dynamic>?>(
            future: authService.getUser(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return UserAccountsDrawerHeader(
                accountName: Text(
                  user?['name'] ?? 'User',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                accountEmail: Text(
                  user?['email'] ?? 'user@mail.com',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: isDark ? waTeal : Colors.white,
                  child: Text(
                    user?['name'] != null && user!['name'].toString().isNotEmpty
                        ? user['name'].toString()[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : waTeal,
                    ),
                  ),
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202C33) : waTeal,
                ),
              );
            },
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildNavItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  title: 'Dashboard',
                  destination: const UserDashboardScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.chat_outlined,
                  title: 'Chats and Calls',
                  destination: const UserChatCallScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.person_outline,
                  title: 'Profile',
                  destination: const UserProfileScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.home_outlined,
                  title: 'News Feed',
                  destination: const HomeScreen(),
                ),
                Divider(color: isDark ? Colors.white10 : Colors.black12),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SwitchListTile(
                      title: Text('Dark Mode', style: TextStyle(color: textColor, fontSize: 16)),
                      secondary: Icon(
                        themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        color: themeProvider.isDarkMode ? Colors.tealAccent : Colors.orangeAccent,
                      ),
                      value: themeProvider.isDarkMode,
                      onChanged: (val) {
                        themeProvider.toggleTheme();
                      },
                      activeColor: waTeal,
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12),
          ListTile(
            leading: _isLoggingOut
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  )
                : const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              _isLoggingOut ? 'Logging out...' : 'Logout',
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            onTap: () async {
              setState(() {
                _isLoggingOut = true;
              });
              await authService.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget destination,
    int unreadCount = 0,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waTeal = Color(0xFF00A884);
    return SoftTouchWrapper(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => destination,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: ListTile(
        leading: Icon(icon, color: isDark ? Colors.white70 : Colors.black54),
        title: Text(
          title,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
        ),
        trailing: (title == 'Chats and Calls' && unreadCount > 0)
            ? Badge(
                label: Text('$unreadCount'),
                backgroundColor: waTeal,
                child: const SizedBox.shrink(),
              )
            : null,
      ),
    );
  }
}
