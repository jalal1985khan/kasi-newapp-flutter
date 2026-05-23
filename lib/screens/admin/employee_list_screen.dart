import 'package:flutter/material.dart';
import '../../services/admin/admin_employee_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'package:intl/intl.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final AdminEmployeeService _employeeService = AdminEmployeeService();

  List<dynamic> _employees = [];
  bool _isLoading = true;
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees({int page = 1}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _employeeService.getEmployees(page: page);
      if (mounted) {
        setState(() {
          if (response['success'] == true) {
            _employees = response['employees'] as List? ?? [];
            _currentPage = response['page'] ?? 1;
            _totalPages = response['totalPages'] ?? 1;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showError('Error loading employees: $e');
      }
    }
  }

  void _showError(String msg) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text('Status Update', style: TextStyle(color: textColor)),
          ],
        ),
        content: Text(msg, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00A884))),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await _fetchEmployees();
  }
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      showBottomNav: false,
      title: 'Employees',
      currentIndex: 2,
      onRefresh: _onRefresh,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : Column(
              children: [
                Expanded(
                  child: _employees.isEmpty
                      ? Center(child: Text('No employees found.', style: TextStyle(color: subTextColor)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _employees.length,
                          itemBuilder: (context, index) =>
                              _buildEmployeeCard(_employees[index], isDark, textColor, subTextColor),
                        ),
                ),
                if (_totalPages > 1) _buildPagination(isDark, textColor),
              ],
            ),
    );
  }

  Widget _buildEmployeeCard(dynamic emp, bool isDark, Color textColor, Color subTextColor) {
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    return InkWell(
      onTap: () => _showEmployeeDetails(emp['_id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textColor.withOpacity(0.05)),
          boxShadow: [
            if (!isDark)
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF00A884).withOpacity(0.1),
              child: Text(
                emp['name'] != null ? emp['name'][0].toUpperCase() : 'E',
                style: const TextStyle(
                  color: Color(0xFF00A884),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emp['name'] ?? 'Unknown Employee',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${emp['employeeId'] ?? 'N/A'}',
                    style: TextStyle(color: subTextColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showEmployeeDetails(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: _employeeService.getEmployeeDetails(userId),
        builder: (context, snapshot) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildBottomSheetContainer(
              modalBg,
              isDark,
              const Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
            );
          }

          final Color textColor = isDark ? Colors.white : Colors.black87;
          final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;
          
          final user = snapshot.data?['user'] ?? {};
          final records = (snapshot.data?['records'] as List?) ?? [];

          return _buildBottomSheetContainer(
            modalBg,
            isDark,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPopupHeader(user, textColor, subTextColor),
                Divider(height: 32, color: textColor.withOpacity(0.1)),
                Text(
                  'Batch Data (${records.length} rows)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: records.isEmpty
                      ? Center(child: Text('No batch data found.', style: TextStyle(color: subTextColor)))
                      : ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (context, idx) {
                            final record = records[idx];
                            final dData = record['dynamicData'] as Map? ?? {};
                            final cur = NumberFormat.currency(symbol: '₹', locale: 'en_IN');
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFF00A884), borderRadius: BorderRadius.circular(4)),
                                        child: Text('RECORD #${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(record['transactionStatus'] ?? 'SYNCED', style: TextStyle(color: textColor.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                  _buildDynamicInfoRow('ID (C1)', record['employeeId'], textColor, subTextColor),
                                  _buildDynamicInfoRow('Name (C3)', record['name'], textColor, subTextColor),
                                  _buildDynamicInfoRow('Type (C2)', record['transactionType'], textColor, subTextColor),
                                  _buildDynamicInfoRow('Account (C4)', record['accountName'], textColor, subTextColor),
                                  _buildDynamicInfoRow('Credits (C5)', cur.format(record['credits'] ?? 0), textColor, subTextColor, isHero: true),
                                  _buildDynamicInfoRow('Total Value (C8)', cur.format(record['totalValue'] ?? 0), textColor, subTextColor, isHero: true),
                                  _buildDynamicInfoRow('Impact (C9)', cur.format(record['impact'] ?? 0), textColor, subTextColor, isHero: true),
                                  _buildDynamicInfoRow('Units (C6)', record['units']?.toString(), textColor, subTextColor),
                                  _buildDynamicInfoRow('Billable (C7)', record['billableUnits']?.toString(), textColor, subTextColor),
                                
                                if (dData.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.only(top: 16, bottom: 8),
                                    child: Text('METADATA (C11+)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  ),
                                    ...dData.entries.map((e) => 
                                      _buildDynamicInfoRow(e.key.toString(), e.value.toString(), textColor, subTextColor)
                                    ).toList(),
                                ],
                                const SizedBox(height: 24),
                              ],
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDynamicInfoRow(String label, String? value, Color textColor, Color subTextColor, {bool isHero = false}) {
    if (value == null || value.isEmpty || value == 'null') value = '—';
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isHero ? const Color(0xFF00A884).withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(bottom: BorderSide(color: textColor.withOpacity(0.02))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: isHero ? const Color(0xFF00A884) : subTextColor,
                fontSize: 11,
                fontWeight: isHero ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isHero ? textColor : textColor.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheetContainer(Color modalBg, bool isDark, Widget child) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildPopupHeader(dynamic user, Color textColor, Color subTextColor) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: const Color(0xFF00A884).withOpacity(0.1),
          child: Text(
            user['name'] != null ? user['name'][0].toUpperCase() : 'E',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00A884),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['name'] ?? 'N/A',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Text(
                'ID: ${user['employeeId'] ?? 'N/A'} • ${user['username'] ?? ''}',
                style: TextStyle(color: subTextColor, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(bool isDark, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111B21) : Colors.white,
        border: Border(top: BorderSide(color: textColor.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: _currentPage > 1
                ? () => _fetchEmployees(page: _currentPage - 1)
                : null,
            icon: const Icon(Icons.arrow_back, color: Color(0xFF00A884)),
            label: const Text('Prev', style: TextStyle(color: Color(0xFF00A884))),
          ),
          Text(
            '$_currentPage / $_totalPages',
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor.withOpacity(0.7)),
          ),
          TextButton.icon(
            onPressed: _currentPage < _totalPages
                ? () => _fetchEmployees(page: _currentPage + 1)
                : null,
            icon: const Icon(Icons.arrow_forward, color: Color(0xFF00A884)),
            label: const Text('Next', style: TextStyle(color: Color(0xFF00A884))),
          ),
        ],
      ),
    );
  }
}
