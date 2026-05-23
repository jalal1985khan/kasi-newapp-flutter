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
  
  final TextEditingController _nameSearchController = TextEditingController();
  final TextEditingController _idSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<EmployeeReport> _allEmployees = [];
  List<EmployeeReport> _filteredEmployees = [];
  int _displayedCount = 15;

  double _totalCredits = 0;
  double _totalDebits = 0;
  double _totalValue = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _nameSearchController.dispose();
    _idSearchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_displayedCount < _filteredEmployees.length) {
        setState(() {
          _displayedCount = (_displayedCount + 15).clamp(0, _filteredEmployees.length);
        });
      }
    }
  }

  void _applyFilters() {
    final nameQuery = _nameSearchController.text.toLowerCase().trim();
    final idQuery = _idSearchController.text.toLowerCase().trim();

    setState(() {
      _filteredEmployees = _allEmployees.where((emp) {
        final matchesName = emp.name.toLowerCase().contains(nameQuery);
        final matchesId = emp.employeeId.toLowerCase().contains(idQuery);
        return matchesName && matchesId;
      }).toList();
      _displayedCount = 15;
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final response = await ReportService.getBulkReport();
    if (mounted && response != null) {
      setState(() {
        _allEmployees = response.employees;
        _totalCredits = response.totalCredits;
        _totalDebits = response.totalDebits;
        _totalValue = response.totalValue;
        _isLoading = false;
      });
      _applyFilters();
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
      if (mounted) {
        setState(() {
          _currentDownloadingEmployee = null;
        });
      }
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
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'OPEN',
                textColor: Colors.white,
                onPressed: () async {
                  try {
                    await Gal.open();
                  } catch (e) {
                    debugPrint('Error opening gallery: $e');
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;
    const Color waTeal = Color(0xFF00A884);
    final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

    return AdminLayout(
      showBottomNav: false,
      title: 'Reports',
      currentIndex: 3,
      onRefresh: _onRefresh,
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: waTeal))
              : SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Premium Summary & Search Header
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                          boxShadow: [
                            if (!isDark)
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _summaryStat('TOTAL CREDITS', cur.format(_totalCredits), const Color(0xFF25D366), subTextColor),
                                _summaryStat('TOTAL DEBITS', cur.format(_totalDebits), Colors.orange, subTextColor),
                                _summaryStat('TOTAL VALUE', cur.format(_totalValue), textColor, subTextColor),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Divider(height: 1, thickness: 0.8, color: isDark ? Colors.white10 : Colors.black12),
                            const SizedBox(height: 16),
                            // Search Controls Row
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF111B21) : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _nameSearchController,
                                      onChanged: (_) => _applyFilters(),
                                      style: TextStyle(color: textColor, fontSize: 13),
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(Icons.person_outline, size: 18, color: waTeal),
                                        hintText: 'Search Name...',
                                        hintStyle: TextStyle(color: subTextColor.withOpacity(0.5), fontSize: 13),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF111B21) : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _idSearchController,
                                      onChanged: (_) => _applyFilters(),
                                      style: TextStyle(color: textColor, fontSize: 13),
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(Icons.badge_outlined, size: 18, color: waTeal),
                                        hintText: 'Search ID...',
                                        hintStyle: TextStyle(color: subTextColor.withOpacity(0.5), fontSize: 13),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_filteredEmployees.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 80),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 48, color: subTextColor.withOpacity(0.4)),
                              const SizedBox(height: 12),
                              Text(
                                'No matching records found',
                                style: TextStyle(color: subTextColor, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _displayedCount < _filteredEmployees.length
                              ? _displayedCount + 1
                              : _filteredEmployees.length,
                          itemBuilder: (context, index) {
                            if (index == _displayedCount) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: waTeal, strokeWidth: 2),
                                  ),
                                ),
                              );
                            }

                            final employee = _filteredEmployees[index];
                            final Color avatarBg = waTeal.withOpacity(0.08);

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200]!,
                                  width: 1,
                                ),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    // Initials Avatar + Name & ID + Download Action
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: avatarBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              getInitials(employee.name),
                                              style: const TextStyle(
                                                color: waTeal,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                employee.name,
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'ID: ${employee.employeeId}',
                                                  style: TextStyle(
                                                    color: subTextColor,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: waTeal.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: _currentDownloadingEmployee == employee
                                                ? const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: CircularProgressIndicator(color: waTeal, strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.file_download_outlined, color: waTeal, size: 18),
                                          ),
                                          onPressed: _currentDownloadingEmployee != null
                                              ? null
                                              : () => _handleDownload(employee),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Divider(height: 1, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
                                    const SizedBox(height: 14),
                                    // Row 2: Credit / Debit / Value Row
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _statCol('CREDITS (C5)', cur.format(employee.credit), const Color(0xFF25D366)),
                                        _statCol('DEBITS (C9)', cur.format(employee.debit), Colors.orange),
                                        _statCol('VALUE (C8)', cur.format(employee.totalValue), textColor),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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

  Widget _statCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.withOpacity(0.8),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '??';
    final parts = clean.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '??';
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}
