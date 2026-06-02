import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/auth_service.dart';
import '../../../providers/theme_provider.dart';
import '../../login_screen.dart';
import '../admin_main_screen.dart';
import '../../../newsfeeds/home_screen.dart';

class AdminDrawer extends StatefulWidget {
  const AdminDrawer({super.key});

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final int unreadCount = context.watch<ChatProvider>().totalUnread;
    final AuthService authService = AuthService();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subColor = isDark ? Colors.white.withOpacity(0.7) : Colors.black54;

    return Drawer(
      backgroundColor: isDark ? waDarkBg : Colors.white,
      child: Column(
        children: [
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: AuthService.userNotifier,
            builder: (context, user, child) {
              return UserAccountsDrawerHeader(
                accountName: Text(
                  user?['name'] ?? 'Admin User',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                accountEmail: Text(
                  user?['email'] ?? 'admin@user.com',
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: waTeal,
                  backgroundImage: AuthService.getProfileImage(user) != null && AuthService.getProfileImage(user)!.isNotEmpty
                      ? NetworkImage("${AuthService().getFullUrl(AuthService.getProfileImage(user))}?t=${user?['updatedAt'] ?? user?['updated_at'] ?? '1'}")
                      : null,
                  child: (AuthService.getProfileImage(user) == null || AuthService.getProfileImage(user)!.isEmpty)
                      ? Text(
                          user?['name'] != null && user!['name'].toString().isNotEmpty
                              ? user['name'].toString()[0].toUpperCase()
                              : 'A',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
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
                  tabIndex: 0,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.group_add_outlined,
                  title: 'Upload Excel',
                  tabIndex: 1,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.list_alt,
                  title: 'Employee',
                  tabIndex: 2,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: 'Transactions',
                  tabIndex: 5,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Accounts',
                  tabIndex: 6,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.web_outlined,
                  title: 'Website Resources',
                  tabIndex: 4,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.bar_chart_outlined,
                  title: 'Reports',
                  tabIndex: 7,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.chat_outlined,
                  title: 'Chats and Calls',
                  tabIndex: 3,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  tabIndex: 8,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.newspaper_outlined,
                  title: 'Newsfeed',
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
                      activeThumbColor: waTeal,
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
    Widget? destination,
    int? tabIndex,
    int unreadCount = 0,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waTeal = Color(0xFF00A884);

    return ListTile(
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
      onTap: () {
        Navigator.pop(context);
        if (tabIndex != null) {
          AdminMainScreen.switchTab(context, tabIndex);
        } else if (destination != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        }
      },
    );
  }
}
