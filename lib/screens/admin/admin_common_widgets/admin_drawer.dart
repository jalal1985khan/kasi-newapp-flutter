import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/auth_service.dart';
import '../../../providers/theme_provider.dart';
import '../../login_screen.dart';
import '../bulk_user_add_screen.dart';
import '../employee_list_screen.dart';
import '../accounts_debit_credit_screen.dart';
import '../website_resourses_screen.dart';
import '../reports_screen.dart';
import '../chat_call_screen.dart';
import '../admin_settings_screen.dart';
import '../transactions_screen.dart';
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
          FutureBuilder<Map<String, dynamic>?>(
            future: authService.getUser(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return UserAccountsDrawerHeader(
                accountName: Text(
                  user?['name'] ?? 'Admin User',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                accountEmail: Text(
                  user?['email'] ?? 'admin@user.com',
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: waTeal,
                  backgroundImage: (user?['profileImage'] != null && user!['profileImage'].toString().isNotEmpty)
                      ? NetworkImage(user['profileImage'])
                      : null,
                  child: (user?['profileImage'] == null || user!['profileImage'].toString().isEmpty)
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
                  icon: Icons.group_add_outlined,
                  title: 'Upload Excel',
                  destination: const BulkUserAddScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.list_alt,
                  title: 'Employee',
                  destination: const EmployeeListScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: 'Transactions',
                  destination: const TransactionsScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Accounts',
                  destination: const AccountsDebitCreditScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.web_outlined,
                  title: 'Website Resources',
                  destination: const WebsiteResourcesScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.bar_chart_outlined,
                  title: 'Reports',
                  destination: const ReportsScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.chat_outlined,
                  title: 'Chats and Calls',
                  destination: const ChatCallScreen(),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  destination: const AdminSettingsScreen(),
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => destination),
        );
      },
    );
  }
}
