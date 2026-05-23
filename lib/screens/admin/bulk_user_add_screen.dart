import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import '../../utils/download_utils.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import '../../services/admin/admin_upload_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'dart:developer' as dev;

class BulkUserAddScreen extends StatefulWidget {
  const BulkUserAddScreen({super.key});

  @override
  State<BulkUserAddScreen> createState() => _BulkUserAddScreenState();
}

class _BulkUserAddScreenState extends State<BulkUserAddScreen> {
  final AdminUploadService _uploadService = AdminUploadService();

  PlatformFile? _pickedFile;
  List<String> _tableHeaders = [];
  List<List<String>> _tableRows = [];
  bool _isParsingFile = false;
  bool _isUploading = false;
  bool _isDownloadingSample = false;
  String? _dialogFeedbackMessage;
  bool _isFeedbackError = false;
  static const int _maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _pickedFile = null;
      _tableHeaders = [];
      _tableRows = [];
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.size > _maxFileSizeBytes) {
          _showDialog(
            title: 'File Too Large',
            message: 'The selected file exceeds the 10 MB limit.',
            isError: true,
          );
          return;
        }

        setState(() {
          _pickedFile = file;
          _isParsingFile = true;
        });

        await _parseExcel(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isParsingFile = false);
    }
  }

  Future<void> _parseExcel(PlatformFile file) async {
    try {
      final bytes = await File(file.path!).readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);

      if (decoder.tables.isNotEmpty) {
        final table = decoder.tables.values.first;
        if (table.rows.isNotEmpty) {
          setState(() {
            _tableHeaders = table.rows.first.map((e) => e?.toString() ?? '').toList();
            _tableRows = table.rows.skip(1).map((row) => row.map((e) => e?.toString() ?? '').toList()).toList();
          });
        }
      }
    } catch (e) {
      _showDialog(title: 'Parsing Error', message: 'Could not read Excel content: $e', isError: true);
    }
  }

  Future<void> _uploadFile() async {
    if (_pickedFile == null) return;
    setState(() => _isUploading = true);
    try {
      final response = await _uploadService.uploadExcel(_pickedFile!.path!);
      if (mounted) {
        if (response['success'] == true) {
          _showDialog(title: 'Upload Successful', message: response['message'] ?? 'Upload complete.', isError: false);
          setState(() {
            _pickedFile = null;
            _tableHeaders = [];
            _tableRows = [];
          });
        } else {
          _showDialog(title: 'Upload Failed', message: response['error'] ?? 'Unknown error', isError: true);
        }
      }
    } catch (e) {
      _showDialog(title: 'Network Error', message: e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showDialog({required String title, required String message, required bool isError}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: isError ? Colors.red : const Color(0xFF25D366), size: 64),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: subTextColor)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Color(0xFF00A884)))),
        ],
      ),
    );
  }

  void _showSampleExcelDialog(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: modalBg,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sample Excel Format', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    Row(
                      children: [
                        if (_isDownloadingSample)
                          const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884))
                        else
                          IconButton(icon: const Icon(Icons.download, color: Color(0xFF00A884)), onPressed: () => _downloadSampleExcel(setDialogState)),
                        IconButton(icon: Icon(Icons.close, color: subTextColor), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _loadSampleExcelData(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
                    if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                    final headers = snapshot.data?['headers'] as List<String>? ?? [];
                    final rows = snapshot.data?['rows'] as List<List<String>>? ?? [];
                    return SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF202C33) : Colors.grey[200]),
                          columns: headers.map((h) => DataColumn(label: Text(h, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)))).toList(),
                          rows: rows.map((r) => DataRow(cells: r.map((cell) => DataCell(Text(cell, style: TextStyle(color: subTextColor)))).toList())).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadSampleExcelData() async {
    try {
      final bytes = await rootBundle.load('lib/assets/sample_excel/Final Sample Sheet.xlsx');
      final decoder = SpreadsheetDecoder.decodeBytes(bytes.buffer.asUint8List());
      final table = decoder.tables.values.first;
      return {
        'success': true,
        'headers': table.rows.first.map((e) => e?.toString() ?? '').toList(),
        'rows': table.rows.skip(1).map((row) => row.map((e) => e?.toString() ?? '').toList()).toList()
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> _downloadSampleExcel(StateSetter setDialogState) async {
    setDialogState(() => _isDownloadingSample = true);
    try {
      final bytes = await rootBundle.load('lib/assets/sample_excel/Final Sample Sheet.xlsx');
      await FileDownloadHelper.saveFile(bytes.buffer.asUint8List(), "Final Sample Sheet.xlsx");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully downloaded'), backgroundColor: Color(0xFF25D366)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      setDialogState(() => _isDownloadingSample = false);
    }
  }

  Widget _buildInstructionsNote(bool isDark, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber[400], size: 18),
              const SizedBox(width: 8),
              const Text('MANDATORY UPLOAD RULES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          _buildStepRow('1', 'Strict Column Order', 'The system reads the first 10 columns by position', Colors.amber, textColor, subTextColor),
          _buildStepRow('2', 'Financial Columns', 'Col 5 (Credits), Col 8 (Value), and Col 9 (Debits) MUST be numbers.', Colors.amber, textColor, subTextColor),
          _buildStepRow('3', 'Identity Column', 'Col 1 MUST be Employee ID and Col 3 Must be Employee Name.', Colors.amber, textColor, subTextColor),
          _buildStepRow('4', 'Col 11+', 'Any data after Column 10 is saved as a SNAPSHOT', Colors.amber, textColor, subTextColor),
        ],
      ),
    );
  }

  Widget _buildStepRow(String num, String title, String desc, Color color, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(num, style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 11, color: subTextColor),
                children: [
                  TextSpan(text: '$title: ', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      showBottomNav: false,
      title: 'Bulk Update',
      currentIndex: 1,
      onRefresh: _onRefresh,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showSampleExcelDialog(context),
                icon: const Icon(Icons.table_view, size: 16, color: Color(0xFF00A884)),
                label: const Text('Sample Excel', style: TextStyle(color: Color(0xFF00A884), fontSize: 13)),
              ),
            ),
            const SizedBox(height: 8),
            _buildInstructionsNote(isDark, textColor, subTextColor),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isParsingFile || _isUploading ? null : _pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_pickedFile != null ? 'Change File' : 'Pick Excel File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: cardBg,
                  foregroundColor: const Color(0xFF00A884),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: const Color(0xFF00A884).withOpacity(0.3))),
                  elevation: isDark ? 0 : 2,
                ),
              ),
            ),
            if (_pickedFile != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file, color: Color(0xFF25D366)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_pickedFile!.name, style: TextStyle(color: textColor))),
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _pickedFile = null)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadFile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit to Server', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
