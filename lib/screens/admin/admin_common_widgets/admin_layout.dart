import 'package:flutter/material.dart';
import 'admin_drawer.dart';
import 'admin_bottom_navbar.dart';

class AdminLayout extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final int currentIndex;
  final Future<void> Function()? onRefresh;
  final List<Widget>? extraActions;
  final Widget? floatingActionButton;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  final Color? backgroundColor;
  final Color? foregroundColor;

  const AdminLayout({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    required this.currentIndex,
    this.onRefresh,
    this.extraActions,
    this.floatingActionButton,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
  }) : assert(title != null || titleWidget != null);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waDarkBg = const Color(0xFF111B21);
    final Color waTeal = const Color(0xFF00A884);
    final Color currentBg = isDark ? waDarkBg : Colors.grey[100]!;
    final Color appBarBg = isDark ? waDarkBg : waTeal;
    final Color textCol = isDark ? Colors.white.withOpacity(0.9) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor ?? currentBg,
      appBar: AppBar(
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        title: titleWidget ??
            Text(
              title ?? '',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: foregroundColor ?? textCol,
                letterSpacing: 0.5,
              ),
            ),
        backgroundColor: appBarBg,
        elevation: 0.5,
        shadowColor: Colors.black.withOpacity(0.3),
        foregroundColor: foregroundColor ?? Colors.white,
        actions: [if (extraActions != null) ...extraActions!],
        bottom: bottom,
      ),
      drawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavBar(currentIndex: currentIndex),
      floatingActionButton: floatingActionButton,
      body: onRefresh != null
          ? RefreshIndicator(
              onRefresh: onRefresh!,
              color: waTeal,
              backgroundColor: isDark ? const Color(0xFF202C33) : Colors.white,
              child: body,
            )
          : body,
    );
  }
}
