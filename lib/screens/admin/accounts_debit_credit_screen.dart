import 'package:flutter/material.dart';
import '../../services/admin/admin_dashboard_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'package:intl/intl.dart';

class AccountsDebitCreditScreen extends StatefulWidget {
  const AccountsDebitCreditScreen({super.key});

  @override
  State<AccountsDebitCreditScreen> createState() =>
      _AccountsDebitCreditScreenState();
}

class _AccountsDebitCreditScreenState extends State<AccountsDebitCreditScreen> {
  final AdminDashboardService _dashboardService = AdminDashboardService();

  List<dynamic> _employees = [];
  Map<String, dynamic> _summary = {
    'totalCredits': 0,
    'totalDebits': 0,
    'totalValue': 0,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dashboardService.getAccountsData(filter: 'all');
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _employees = response['employees'] as List? ?? [];
            if (response['summary'] != null) {
              _summary = response['summary'] as Map<String, dynamic>;
            }
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
          _showError(response['message'] ?? 'Failed to load ledger');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  Future<void> _onRefresh() async {
    await _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      title: 'Accounts',
      currentIndex: -1,
      onRefresh: _onRefresh,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : Column(
              children: [
                _buildSummaryHeader(cardBg, textColor),
                Expanded(
                  child: _employees.isEmpty
                      ? Center(child: Text('No entries found.', style: TextStyle(color: subTextColor)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _employees.length,
                          itemBuilder: (context, index) => _buildTransactionCard(_employees[index], cardBg, textColor, subTextColor),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader(Color cardBg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildStatItem('Total Credits', _summary['totalCredits'], const Color(0xFF25D366)),
            const SizedBox(width: 12),
            _buildStatItem('Total Debits', _summary['totalDebits'], Colors.orange),
            const SizedBox(width: 12),
            _buildStatItem('Total Value', _summary['totalValue'], textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, dynamic value, Color color) {
    final curFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.withOpacity(0.7), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(curFormat.format(value ?? 0), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(dynamic tx, Color cardBg, Color textColor, Color subTextColor) {
    final dateStr = tx['updatedAt'] ?? tx['createdAt'];
    final date = dateStr != null ? DateTime.parse(dateStr).toLocal() : DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.05)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF00A884).withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.list_alt, color: Color(0xFF00A884), size: 20),
        ),
        title: Text(tx['name'] ?? 'Employee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
        subtitle: Text('ID: ${tx['employeeId']} • ${DateFormat('dd MMM HH:mm').format(date)}', style: TextStyle(color: subTextColor, fontSize: 11)),
        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: subTextColor.withOpacity(0.5)),
        onTap: () => _showAuditDetails(tx),
      ),
    );
  }

  void _showAuditDetails(dynamic tx) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color itemBg = isDark ? const Color(0xFF202C33) : Colors.grey[50]!;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.4) : Colors.black54;

    final Map<String, dynamic> dData = tx['dynamicData'] ?? {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(color: modalBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black12, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            Row(
              children: [
                CircleAvatar(backgroundColor: const Color(0xFF00A884).withOpacity(0.1), child: const Icon(Icons.history_edu, color: Color(0xFF00A884))),
                const SizedBox(width: 16),
                Text('Snapshot Receipt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
            Divider(color: isDark ? Colors.white10 : Colors.black12, height: 32),
            Expanded(
              child: ListView(
                children: [
                  _buildAuditTile('Staff Name', tx['name'], itemBg, textColor, subTextColor),
                  _buildAuditTile('Employee ID', tx['employeeId'], itemBg, textColor, subTextColor),
                  _buildSectionLabel('CALCULATION SUMMARY', const Color(0xFF25D366)),
                  _buildAuditTile('Your Credits', NumberFormat.currency(symbol: '₹', locale: 'en_IN').format(tx['userTotalCredits'] ?? 0), itemBg, textColor, subTextColor, isAccent: true),
                  _buildAuditTile('Your Debits', NumberFormat.currency(symbol: '₹', locale: 'en_IN').format(tx['userTotalDebits'] ?? 0), itemBg, textColor, subTextColor, isAccent: true),
                  _buildAuditTile('Your Net Value', NumberFormat.currency(symbol: '₹', locale: 'en_IN').format(tx['userTotalValue'] ?? 0), itemBg, textColor, subTextColor, isAccent: true),
                  _buildSectionLabel('TRANSACTION (C1-C10)', const Color(0xFF00A884)),
                  _buildAuditTile('Type (C2)', tx['transactionType'], itemBg, textColor, subTextColor),
                  _buildAuditTile('Account (C4)', tx['accountName'], itemBg, textColor, subTextColor),
                  _buildAuditTile('Credits (C5)', tx['credits']?.toString(), itemBg, textColor, subTextColor),
                  _buildAuditTile('Units (C6)', tx['units']?.toString(), itemBg, textColor, subTextColor),
                  _buildAuditTile('Billable (C7)', tx['billableUnits']?.toString(), itemBg, textColor, subTextColor),
                  _buildAuditTile('Total Value (C8)', tx['totalValue']?.toString(), itemBg, textColor, subTextColor),
                  _buildAuditTile('Debits (C9)', tx['impact']?.toString(), itemBg, textColor, subTextColor),
                  _buildAuditTile('Status (C10)', tx['transactionStatus'], itemBg, textColor, subTextColor),
                  if (dData.isNotEmpty) ...[
                    _buildSectionLabel('DYNAMIC DATA (C11+)', isDark ? Colors.white24 : Colors.black26),
                    ...dData.entries.map((e) => _buildAuditTile(e.key, e.value.toString(), itemBg, textColor, subTextColor)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Back to Ledger', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
    );
  }

  Widget _buildAuditTile(String label, String? value, Color itemBg, Color textColor, Color subTextColor, {bool isAccent = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: itemBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: textColor.withOpacity(0.05))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: subTextColor, fontSize: 13))),
          const SizedBox(width: 12),
          Text(value ?? '—', style: TextStyle(fontWeight: FontWeight.bold, color: isAccent ? const Color(0xFF25D366) : textColor, fontSize: 13)),
        ],
      ),
    );
  }
}
