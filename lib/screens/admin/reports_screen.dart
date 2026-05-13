import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../../services/admin/report_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  EmployeeReport? _currentDownloadingEmployee;
  List<EmployeeReport> _employees = [];
  double _totalCredits = 0;
  double _totalDebits = 0;
  double _totalValue = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final response = await ReportService.getBulkReport();
    if (mounted && response != null) {
      setState(() {
        _employees = response.employees;
        _totalCredits = response.totalCredits;
        _totalDebits = response.totalDebits;
        _totalValue = response.totalValue;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  Future<void> _handleDownload(EmployeeReport employee) async {
    setState(() {
      _currentDownloadingEmployee = employee;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _captureAndSave();
      setState(() {
        _currentDownloadingEmployee = null;
      });
    });
  }

  Future<void> _captureAndSave() async {
    try {
      if (await Permission.storage.request().isDenied &&
          await Permission.photos.request().isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission required to save images')),
          );
        }
        return;
      }

      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List? pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes != null) {
        await Gal.putImageBytes(pngBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Report for ${_currentDownloadingEmployee?.name} saved!'),
              backgroundColor: const Color(0xFF25D366),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return AdminLayout(
      title: 'Reports',
      currentIndex: 3,
      onRefresh: _onRefresh,
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: waTeal))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Premium Summary Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                          boxShadow: [
                            if (!isDark)
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _summaryStat('TOTAL CREDITS', cur.format(_totalCredits), const Color(0xFF25D366), subTextColor),
                            _summaryStat('TOTAL DEBITS', cur.format(_totalDebits), Colors.orange, subTextColor),
                            _summaryStat('TOTAL VALUE', cur.format(_totalValue), textColor, subTextColor),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_employees.isEmpty)
                        Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No report records found', style: TextStyle(color: subTextColor))))
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                cardTheme: CardThemeData(color: cardBg, elevation: 0),
                                dividerColor: isDark ? Colors.white10 : Colors.black12,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF202C33) : Colors.grey[200]),
                                columns: const [
                                  DataColumn(label: Text('NAME', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('EMP ID', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('CREDITS (C5)', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('DEBITS (C9)', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('VALUE (C8)', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('DOWNLOAD', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold))),
                                ],
                                rows: _employees.map((employee) => DataRow(
                                  cells: [
                                    DataCell(Text(employee.name, style: TextStyle(fontWeight: FontWeight.bold, color: textColor))),
                                    DataCell(Text(employee.employeeId, style: TextStyle(color: subTextColor))),
                                    DataCell(Text(cur.format(employee.credit), style: const TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold))),
                                    DataCell(Text(cur.format(employee.debit), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                                    DataCell(Text(cur.format(employee.totalValue), style: TextStyle(fontWeight: FontWeight.w500, color: subTextColor))),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(Icons.file_download_outlined, color: waTeal),
                                        onPressed: () => _handleDownload(employee),
                                      ),
                                    ),
                                  ],
                                )).toList(),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),

          // Hidden Report Generator (Premium Invoice Style)
          if (_currentDownloadingEmployee != null)
            Positioned(
              left: -2000, 
              top: 0,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  width: 600,
                  padding: const EdgeInsets.all(40),
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('OFFICIAL STATUS REPORT', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                              Text('Generated: ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.verified_user, color: Colors.blue, size: 40),
                          ),
                        ],
                      ),
                      const Divider(height: 60, thickness: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _reportLabel('EMPLOYEE DETAILS'),
                                Text(_currentDownloadingEmployee!.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text('ID: ${_currentDownloadingEmployee!.employeeId}', style: const TextStyle(fontSize: 14)),
                                if (_currentDownloadingEmployee!.email != null) Text(_currentDownloadingEmployee!.email!),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _reportLabel('CATEGORY / ACCOUNT'),
                                Text(_currentDownloadingEmployee!.accountDetail ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            _invoiceRow('Staff Credits (C5)', cur.format(_currentDownloadingEmployee!.credit), isTotal: true, color: Colors.green[800]!),
                            const SizedBox(height: 16),
                            _invoiceRow('Operational Debits (C9)', cur.format(_currentDownloadingEmployee!.debit), isTotal: true, color: Colors.orange[800]!),
                            const SizedBox(height: 16),
                            _invoiceRow('Net Settled Value (C8)', cur.format(_currentDownloadingEmployee!.totalValue)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 60),
                      const Center(
                        child: Text(
                          'THIS IS A SYSTEM GENERATED SECURE REPORT. NO SIGNATURE REQUIRED.',
                          style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color, Color subTextColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: subTextColor, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _reportLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  Widget _invoiceRow(String label, String value, {bool isTotal = false, Color color = Colors.black}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
