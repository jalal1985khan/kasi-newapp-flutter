import 'package:flutter/material.dart';
import '../../services/admin/admin_dashboard_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../../services/auth_service.dart';
import 'package:intl/intl.dart';
import 'call_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AdminDashboardService _dashboardService = AdminDashboardService();

  Map<String, dynamic>? _stats;
  List<dynamic> _recentUploads = [];
  bool _isLoading = true;
  String? _errorMessage;
  // Read name synchronously from in-memory notifier — already populated before runApp
  String _adminName = AuthService.userNotifier.value?['name'] ?? 'Admin';

  @override
  void initState() {
    super.initState();
    // No _loadProfile() needed — name is already available synchronously above
    _fetchDashboardData();
  }


  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await _dashboardService.getDashboardData();

    if (mounted) {
      if (response['success'] == true) {
        setState(() {
          _stats = response['stats'];
          _recentUploads = _stats?['recentUploads'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error fetching data';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _fetchDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      showBottomNav: false,
      title: 'Dashboard',
      currentIndex: 0,
      onRefresh: _onRefresh,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : _errorMessage != null
          ? _buildErrorView()
          : _buildDashboardBody(),
    );
  }

  Widget _buildErrorView() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchDashboardData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody() {

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(textColor, subTextColor),
          const SizedBox(height: 24),
          Text(
            'Performance Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatsGrid(cardBg, textColor, subTextColor),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRecentUploadsList(cardBg, textColor, subTextColor),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textColor, Color subTextColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back,',
          style: TextStyle(color: subTextColor, fontSize: 16),
        ),
        Text(
          _adminName,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(Color cardBg, Color textColor, Color subTextColor) {
    final curFormat = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 0,
      locale: 'en_IN',
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDashboardCard(
                title: 'Employees',
                value: _stats?['totalEmployees']?.toString() ?? '0',
                subtitle: '${_stats?['activeEmployees'] ?? 0} Active',
                icon: Icons.people_alt,
                color: Colors.blue,
                cardBg: cardBg,
                textColor: textColor,
                subTextColor: subTextColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CallHistoryScreen(),
                    ),
                  );
                },
                child: _buildDashboardCard(
                  title: 'Call Logs',
                  value: 'History',
                  subtitle: 'View Activity',
                  icon: Icons.history_rounded,
                  color: Colors.purple,
                  cardBg: cardBg,
                  textColor: textColor,
                  subTextColor: subTextColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDashboardCard(
                title: 'Total Credits',
                value: curFormat.format(_stats?['totalCredits'] ?? 0),
                subtitle: 'Collective C5',
                icon: Icons.trending_up,
                color: const Color(0xFF25D366),
                cardBg: cardBg,
                textColor: textColor,
                subTextColor: subTextColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDashboardCard(
                title: 'Total Debits',
                value: curFormat.format(_stats?['totalDebits'] ?? 0),
                subtitle: 'Collective C9',
                icon: Icons.trending_down,
                color: Colors.orange,
                cardBg: cardBg,
                textColor: textColor,
                subTextColor: subTextColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.05)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: subTextColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentUploadsList(Color cardBg, Color textColor, Color subTextColor) {
    if (_recentUploads.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Center(
          child: Text(
            'No recent activity detected.',
            style: TextStyle(color: subTextColor),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentUploads.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final upload = _recentUploads[index];
        final date = DateTime.parse(upload['createdAt']).toLocal();
        return _buildUploadCard(upload, date, cardBg, textColor, subTextColor);
      },
    );
  }

  Widget _buildUploadCard(Map<String, dynamic> upload, DateTime date, Color cardBg, Color textColor, Color subTextColor) {
    final bool isDone = upload['status'] == 'done';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.05)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isDone ? const Color(0xFF25D366) : Colors.orange).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDone ? Icons.check_circle_outline : Icons.history,
              color: isDone ? const Color(0xFF25D366) : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upload['fileName'] ?? 'Unknown File',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                Text(
                  DateFormat('MMM dd • hh:mm a').format(date),
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildStatusBadge(upload['status'] ?? 'pending'),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${upload['processedRows'] ?? 0}',
                    style: const TextStyle(
                      color: Color(0xFF25D366),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' / ',
                    style: TextStyle(color: subTextColor, fontSize: 10),
                  ),
                  Text(
                    '${upload['failedRows'] ?? 0}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final bool isDone = status == 'done';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isDone ? const Color(0xFF25D366) : Colors.orange).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDone ? const Color(0xFF25D366) : Colors.orange).withOpacity(0.2),
        ),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: isDone ? const Color(0xFF25D366) : Colors.orange,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
