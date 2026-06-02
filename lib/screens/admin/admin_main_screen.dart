import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import 'bulk_user_add_screen.dart';
import 'employee_list_screen.dart';
import 'chat_call_screen.dart';
import 'website_resourses_screen.dart';
import 'transactions_screen.dart';
import 'accounts_debit_credit_screen.dart';
import 'reports_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_common_widgets/admin_bottom_navbar.dart';
import '../../services/chat/socket_service.dart';

class AdminMainScreen extends StatefulWidget {
  final int initialIndex;

  const AdminMainScreen({super.key, this.initialIndex = 0});

  @override
  State<AdminMainScreen> createState() => AdminMainScreenState();

  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<AdminMainScreenState>();
    if (state != null) {
      state.setTab(index);
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => AdminMainScreen(initialIndex: index),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }
}

class AdminMainScreenState extends State<AdminMainScreen> {
  late int _currentIndex;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const BulkUserAddScreen(),
    const EmployeeListScreen(),
    const ChatCallScreen(),
    const WebsiteResourcesScreen(),
    const TransactionsScreen(),
    const AccountsDebitCreditScreen(),
    const ReportsScreen(),
    const AdminSettingsScreen(),
  ];

  void setTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    if (index == 3) {
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

    if (index == 3) {
      debugPrint('📡 [Navigation] Admin tapped Chat tab. Waking socket...');
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
      bottomNavigationBar: _currentIndex < 5
          ? AdminBottomNavBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
            )
          : null,
    );
  }
}
