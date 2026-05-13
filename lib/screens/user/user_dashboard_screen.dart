import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'common_widgets/user_layout.dart';
import '../../services/employee/employee_service.dart';
import '../../models/employee_me_response.dart';
import 'package:intl/intl.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final EmployeeService _employeeService = EmployeeService();
  late Future<EmployeeMeResponse> _employeeFuture = _employeeService.getEmployeeMe();
  bool _isDownloading = false;
  final Map<int, GlobalKey> _recordKeys = {};

  @override
  void initState() {
    super.initState();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _employeeFuture = _employeeService.getEmployeeMe();
    });
    await _employeeFuture;
  }

  Future<void> _captureAndSaveRecord(int index, User user) async {
    final key = _recordKeys[index];
    if (key == null) return;

    setState(() => _isDownloading = true);
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception("Could not find capture boundary");

      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Failed to encode image");

      final pngBytes = byteData.buffer.asUint8List();

      String? downloadPath;
      if (Platform.isAndroid) {
        downloadPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadPath);
        if (!await dir.exists()) {
          downloadPath = (await getExternalStorageDirectory())?.path;
        }
      } else {
        downloadPath = (await getApplicationDocumentsDirectory()).path;
      }

      if (downloadPath == null) throw Exception("Could not determine download path");

      final fileName = 'record_${index + 1}_${user.name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('$downloadPath/$fileName');
      await file.writeAsBytes(pngBytes);
      await Gal.putImage(file.path);

      _showSuccessDialog('Record saved to Device Storage: $fileName');
    } catch (e) {
      _showErrorDialog(e.toString());
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202C33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF25D366), size: 64),
            const SizedBox(height: 16),
            const Text('Success!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Color(0xFF00A884)))),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202C33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text('Error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Color(0xFF00A884)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UserLayout(
      title: 'Dashboard',
      currentIndex: 0,
      onRefresh: _onRefresh,
      body: FutureBuilder<EmployeeMeResponse>(
        future: _employeeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final user = snapshot.data?.user;
          final records = snapshot.data?.records ?? [];
          final tCredits = snapshot.data?.totalCredits ?? 0;
          final tDebits = snapshot.data?.totalDebits ?? 0;
          final tValue = snapshot.data?.totalValue ?? 0;

          if (user == null) {
            return const Center(child: Text('User profile not found', style: TextStyle(color: Colors.white)));
          }

          final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: const Color(0xFF00A884),
            backgroundColor: const Color(0xFF202C33),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildUserHeader(user),
                  const SizedBox(height: 16),
                  
                  // Financial Summary row
                  Row(
                    children: [
                      _buildSummaryCard('Credits', cur.format(tCredits), const Color(0xFF25D366), Icons.arrow_downward),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Debits', cur.format(tDebits), Colors.orange, Icons.arrow_upward),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Value', cur.format(tValue), Colors.blue, Icons.account_balance_wallet),
                    ],
                  ),

                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    records.length > 1 
                      ? 'Batch Records (${records.length} items)' 
                      : 'Latest Batch Details'
                  ),
                  const SizedBox(height: 16),
                  if (records.isEmpty) 
                    Center(child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Text('No data found in your latest batch', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    ))
                  else
                    ...List.generate(records.length, (idx) {
                      final record = records[idx];
                      _recordKeys[idx] ??= GlobalKey();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF202C33),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                            unselectedWidgetColor: Colors.white54,
                            colorScheme: const ColorScheme.dark(primary: Color(0xFF00A884)),
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: (record.credits > 0) ? const Color(0xFF25D366).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                              child: Icon(
                                (record.credits > 0) ? Icons.add : Icons.remove,
                                color: (record.credits > 0) ? const Color(0xFF25D366) : Colors.orange,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              record.accountName ?? 'Record #${idx + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            ),
                            subtitle: Text(
                              '${DateFormat('dd MMM').format(DateTime.parse(record.updatedAt))} • ${record.transactionStatus ?? "Processed"}',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: _isDownloading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884)))
                                : const Icon(Icons.download_rounded, size: 20, color: Color(0xFF00A884)),
                              onPressed: _isDownloading ? null : () => _captureAndSaveRecord(idx, user),
                            ),
                            childrenPadding: const EdgeInsets.all(0),
                            children: [
                              RepaintBoundary(
                                key: _recordKeys[idx],
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  color: const Color(0xFF202C33),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('SNAPSHOT RECEIPT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00A884), letterSpacing: 1.5)),
                                      const SizedBox(height: 12),
                                      _receiptRow('Transaction ID', record.id.length > 8 ? record.id.substring(record.id.length - 8).toUpperCase() : record.id),
                                      _receiptRow('Type (C2)', record.transactionType ?? 'N/A'),
                                      _receiptRow('Account (C4)', record.accountName ?? 'N/A'),
                                      Divider(height: 24, color: Colors.white.withOpacity(0.05)),
                                      Row(
                                        children: [
                                          Expanded(child: _receiptStat('CREDITS (C5)', cur.format(record.credits), const Color(0xFF25D366))),
                                          Expanded(child: _receiptStat('DEBITS (C9)', cur.format(record.impact), Colors.orange)),
                                          Expanded(child: _receiptStat('TOTAL (C8)', cur.format(record.totalValue), Colors.blue)),
                                        ],
                                      ),
                                      Divider(height: 24, color: Colors.white.withOpacity(0.05)),
                                      _receiptRow('Units (C6)', record.units?.toString() ?? '0'),
                                      _receiptRow('Billable Units (C7)', record.billableUnits?.toString() ?? '0'),
                                      _receiptRow('Status (C10)', record.transactionStatus ?? 'Processed'),
                                      
                                      if (record.data.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        Text('ADDITIONAL DATA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4))),
                                        const SizedBox(height: 8),
                                        ...record.data.entries.take(5).map((e) => _receiptRow(e.key, e.value.toString())),
                                      ],
                                      Divider(height: 24, color: Colors.white.withOpacity(0.05)),
                                      Center(child: Text('Downloaded: ${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.3)))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF202C33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _receiptStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildUserHeader(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00A884), Color(0xFF008C6F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Employee ID: ${user.employeeId ?? "N/A"}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white));
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text('Oops!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _onRefresh,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
