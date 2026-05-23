import 'package:flutter/material.dart';
import '../../services/admin/admin_dashboard_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'package:intl/intl.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final AdminDashboardService _dashboardService = AdminDashboardService();
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  String _filter = 'all';
  double _totalCredits = 0;
  double _totalDebits = 0;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);
    final response = await _dashboardService.getAccountsData(filter: _filter);
    if (mounted) {
      if (response['success'] == true) {
        setState(() {
          _transactions = response['employees'] ?? [];
          _totalCredits = (response['totalCredits'] ?? 0).toDouble();
          _totalDebits = (response['totalDebits'] ?? 0).toDouble();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Error fetching transactions')),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    await _fetchTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      showBottomNav: false,
      title: 'Transactions',
      currentIndex: -1,
      onRefresh: _onRefresh,
      body: Column(
        children: [
          _buildSummaryHeader(cardBg, textColor, subTextColor),
          _buildFilterSection(isDark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
                : _transactions.isEmpty
                ? Center(child: Text('No transactions found.', style: TextStyle(color: subTextColor)))
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) => _buildTransactionCard(_transactions[index], cardBg, textColor, subTextColor),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(Color cardBg, Color textColor, Color subTextColor) {
    final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('TOTAL CREDITS', cur.format(_totalCredits), Icons.trending_up, const Color(0xFF25D366), textColor, subTextColor),
          _buildSummaryItem('TOTAL DEBITS', cur.format(_totalDebits), Icons.trending_down, Colors.orange, textColor, subTextColor),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color, Color textColor, Color subTextColor) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: subTextColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildFilterSection(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildFilterButton('All Activity', 'all', isDark),
          const SizedBox(width: 8),
          _buildFilterButton('Credits Only', 'credit', isDark),
          const SizedBox(width: 8),
          _buildFilterButton('Debits Only', 'debit', isDark),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String label, String value, bool isDark) {
    final isSelected = _filter == value;
    final Color waTeal = const Color(0xFF00A884);
    return InkWell(
      onTap: () {
        setState(() => _filter = value);
        _fetchTransactions();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? waTeal : (isDark ? const Color(0xFF202C33) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : (isDark ? Colors.white10 : Colors.black12)),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildTransactionCard(dynamic tx, Color cardBg, Color textColor, Color subTextColor) {
    final dateStr = tx['date'] ?? tx['createdAt'];
    final date = dateStr != null ? DateTime.parse(dateStr).toLocal() : DateTime.now();
    final bool isDebit = tx['transactionType']?.toLowerCase() == 'debit';

    return InkWell(
      onTap: () => _showTransactionDetails(tx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textColor.withOpacity(0.05)),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (isDebit ? Colors.orange : const Color(0xFF25D366)).withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(isDebit ? Icons.trending_down : Icons.trending_up, color: isDebit ? Colors.orange : const Color(0xFF25D366), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx['name'] ?? 'Staff Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                  Text('${tx['employeeId'] ?? 'N/A'} • ${DateFormat('dd MMM yyyy').format(date)}', style: TextStyle(fontSize: 11, color: subTextColor)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(isDebit ? '-${tx['impact'] ?? 0}' : '+${tx['credits'] ?? 0}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDebit ? Colors.orange : const Color(0xFF25D366))),
                Text('₹${tx['totalValue'] ?? 0}', style: TextStyle(color: subTextColor, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDetails(dynamic tx) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.grey[50]!;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(color: modalBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black12, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            _buildPopupHeader(tx, textColor, subTextColor),
            Divider(color: isDark ? Colors.white10 : Colors.black12, height: 32),
            Expanded(
              child: ListView(
                children: [
                  _buildSectionLabel('Identity & Type', const Color(0xFF00A884)),
                  _buildDetailTile('Employee ID (C1)', tx['employeeId'], cardBg, textColor, subTextColor),
                  _buildDetailTile('Name (C3)', tx['name'], cardBg, textColor, subTextColor),
                  _buildDetailTile('Type (C2)', tx['transactionType']?.toString().toUpperCase(), cardBg, textColor, subTextColor),
                  _buildDetailTile('Account (C4)', tx['accountName'], cardBg, textColor, subTextColor),
                  
                  _buildSectionLabel('Financial Math', const Color(0xFF25D366)),
                  _buildDetailTile('Credits (C5)', cur.format(tx['credits'] ?? 0), cardBg, textColor, subTextColor, isBright: true),
                  _buildDetailTile('Total Value (C8)', cur.format(tx['totalValue'] ?? 0), cardBg, textColor, subTextColor, isBright: true),
                  _buildDetailTile('Debits/Impact (C9)', cur.format(tx['impact'] ?? 0), cardBg, textColor, subTextColor, isBright: true),
                  
                  _buildSectionLabel('Operational Units', Colors.blueAccent),
                  _buildDetailTile('Units (C6)', tx['units']?.toString(), cardBg, textColor, subTextColor),
                  _buildDetailTile('Billable Units (C7)', tx['billableUnits']?.toString(), cardBg, textColor, subTextColor),
                  
                  _buildSectionLabel('Processing & Metadata', isDark ? Colors.white38 : Colors.black38),
                  _buildDetailTile('Status (C10)', tx['transactionStatus']?.toString().toUpperCase(), cardBg, textColor, subTextColor, isStatus: true),
                  _buildDetailTile('Sync Source', tx['isEdited'] == true ? 'Manual Correction' : 'Original Batch Sync', cardBg, textColor, subTextColor),
                  
                  if (tx['dynamicData'] != null && (tx['dynamicData'] as Map).isNotEmpty) ...[
                    _buildSectionLabel('Snapshot Data (C11+)', isDark ? Colors.white24 : Colors.black26),
                    ...(tx['dynamicData'] as Map).entries.map((e) => _buildDetailTile(e.key, e.value.toString(), cardBg, textColor, subTextColor)).toList(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Close Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
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
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
    );
  }

  Widget _buildPopupHeader(dynamic tx, Color textColor, Color subTextColor) {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFF00A884).withOpacity(0.1),
          child: Text(tx['name'] != null ? tx['name'][0].toUpperCase() : 'S', style: const TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tx['name'] ?? 'Staff Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Text('ID: ${tx['employeeId'] ?? 'N/A'} • ${tx['transactionType'] ?? ''}', style: TextStyle(color: subTextColor, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailTile(String label, String? value, Color cardBg, Color textColor, Color subTextColor, {bool isStatus = false, bool isBright = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: textColor.withOpacity(0.05))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: subTextColor, fontSize: 13)),
          if (isStatus)
            _buildTinyBadge(value ?? 'N/A')
          else
            Text(value ?? '-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isBright ? const Color(0xFF00A884) : textColor)),
        ],
      ),
    );
  }

  Widget _buildTinyBadge(String text) {
    final bool isPositive = text == 'SENT' || text == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: (isPositive ? const Color(0xFF25D366) : Colors.orange).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: isPositive ? const Color(0xFF25D366) : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
