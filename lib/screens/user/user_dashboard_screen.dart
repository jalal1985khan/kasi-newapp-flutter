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
import 'package:shimmer/shimmer.dart';
import '../../utils/premium_widgets.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final EmployeeService _employeeService = EmployeeService();
  final ScrollController _scrollController = ScrollController();
  
  User? _user;
  List<EmployeeData> _records = [];
  double _totalCredits = 0;
  double _totalDebits = 0;
  double _totalValue = 0;
  
  bool _isLoading = true;
  bool _isUploadingImage = false;
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final int _limit = 10;

  bool _isDownloading = false;
  final Map<int, GlobalKey> _recordKeys = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMore) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _records = [];
      _hasMore = true;
    });
    
    try {
      final response = await _employeeService.getEmployeeMe(page: _currentPage, limit: _limit);
      if (mounted) {
        setState(() {
          _user = response.user;
          _records = response.records;
          _totalCredits = response.totalCredits;
          _totalDebits = response.totalDebits;
          _totalValue = response.totalValue;
          _isLoading = false;
          _hasMore = response.records.length == _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreData() async {
    setState(() => _isFetchingMore = true);
    _currentPage++;
    
    try {
      final response = await _employeeService.getEmployeeMe(page: _currentPage, limit: _limit);
      if (mounted) {
        setState(() {
          _records.addAll(response.records);
          _isFetchingMore = false;
          _hasMore = response.records.length == _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadInitialData();
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    if (mounted) setState(() => _isUploadingImage = true);

    try {
      final uploadResult = await AuthService().uploadProfileImage(image.path);
      if (uploadResult['success'] == true) {
        final imageUrl = uploadResult['url'];
        final updateResult = await AuthService().updateProfile(profileImage: imageUrl);
        
        if (updateResult['success'] == true) {
          await _loadInitialData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile image updated'), backgroundColor: Color(0xFF25D366)),
            );
          }
        } else {
          throw Exception(updateResult['message']);
        }
      } else {
        throw Exception(uploadResult['message']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;
    final Color cardColor = isDark ? const Color(0xFF1B272E) : Colors.white;
    const Color waTeal = Color(0xFF00A884);

    return UserLayout(
      title: 'Dashboard',
      currentIndex: 0,
      onRefresh: _onRefresh,
      body: _isLoading 
          ? _buildShimmerLoading(isDark)
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: waTeal,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_user != null) _buildPremiumHeader(_user!),
                          const SizedBox(height: 20),
                          _buildFinancialSummary(cardColor, subTextColor),
                          const SizedBox(height: 28),
                          _buildSectionHeader('Batch Records', textColor),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  
                  if (_records.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text('No records found', style: TextStyle(color: subTextColor)),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == _records.length) {
                            return _isFetchingMore 
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Center(child: CircularProgressIndicator(color: waTeal)),
                                  )
                                : const SizedBox(height: 100);
                          }
                          
                          final record = _records[index];
                          _recordKeys[index] ??= GlobalKey();
                          return _buildPremiumRecordCard(record, index, isDark, cardColor, textColor, subTextColor, _recordKeys[index]!);
                        },
                        childCount: _records.length + 1,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildPremiumHeader(User user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00A884), Color(0xFF056162)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A884).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickAndUploadImage,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white.withOpacity(0.9),
                backgroundImage: user.profileImage != null && user.profileImage!.isNotEmpty
                    ? NetworkImage(AuthService().getFullUrl(user.profileImage!)!)
                    : null,
                child: _isUploadingImage
                    ? const CircularProgressIndicator(color: Color(0xFF00A884))
                    : (user.profileImage == null || user.profileImage!.isEmpty
                        ? Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Color(0xFF00A884), fontSize: 28, fontWeight: FontWeight.bold),
                          )
                        : null),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Employee ID: ${user.employeeId ?? "N/A"}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummary(Color cardColor, Color subTextColor) {
    final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    
    return Row(
      children: [
        _buildSummaryCard('Credits', cur.format(_totalCredits), const Color(0xFF25D366), Icons.arrow_downward, cardColor, subTextColor),
        const SizedBox(width: 12),
        _buildSummaryCard('Debits', cur.format(_totalDebits), Colors.orange, Icons.arrow_upward, cardColor, subTextColor),
        const SizedBox(width: 12),
        _buildSummaryCard('Value', cur.format(_totalValue), Colors.blue, Icons.account_balance_wallet, cardColor, subTextColor),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color, IconData icon, Color cardColor, Color subTextColor) {
    return Expanded(
      child: SoftTouchWrapper(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(fontSize: 12, color: subTextColor, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumRecordCard(EmployeeData record, int index, bool isDark, Color cardColor, Color textColor, Color subTextColor, GlobalKey recordKey) {
    return _PremiumRecordCard(
      record: record,
      index: index,
      isDark: isDark,
      cardColor: cardColor,
      textColor: textColor,
      subTextColor: subTextColor,
      user: _user!,
      onDownload: _captureAndSaveRecord,
      recordKey: recordKey,
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.5)),
        if (_records.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text('${_records.length} items', style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF202C33) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF2C3943) : const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
            const SizedBox(height: 20),
            Row(
              children: List.generate(3, (index) => Expanded(
                child: Container(margin: EdgeInsets.only(right: index == 2 ? 0 : 12), height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
              )),
            ),
            const SizedBox(height: 40),
            ...List.generate(5, (index) => Container(margin: const EdgeInsets.only(bottom: 16), height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)))),
          ],
        ),
      ),
    );
  }
}

class _PremiumRecordCard extends StatefulWidget {
  final EmployeeData record;
  final int index;
  final bool isDark;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  final User user;
  final Function(int, User) onDownload;
  final GlobalKey recordKey;

  const _PremiumRecordCard({
    required this.record,
    required this.index,
    required this.isDark,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.user,
    required this.onDownload,
    required this.recordKey,
  });

  @override
  State<_PremiumRecordCard> createState() => _PremiumRecordCardState();
}

class _PremiumRecordCardState extends State<_PremiumRecordCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cur = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    const Color waTeal = Color(0xFF00A884);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: widget.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
          ],
          border: Border.all(color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ExpansionTile(
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onExpansionChanged: (expanded) {
              setState(() {
                _isExpanded = expanded;
              });
            },
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (widget.record.credits > 0 ? const Color(0xFF25D366) : Colors.orange).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.record.credits > 0 ? Icons.add_rounded : Icons.remove_rounded,
                color: widget.record.credits > 0 ? const Color(0xFF25D366) : Colors.orange,
                size: 20,
              ),
            ),
            title: Text(
              widget.record.accountName ?? 'Record #${widget.index + 1}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: widget.textColor),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${DateFormat('dd MMM').format(DateTime.parse(widget.record.updatedAt))} • ${widget.record.transactionStatus ?? "Processed"}',
                style: TextStyle(color: widget.subTextColor, fontSize: 13),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cur.format(widget.record.credits > 0 ? widget.record.credits : widget.record.impact),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.record.credits > 0 ? const Color(0xFF25D366) : Colors.orange,
                    fontSize: 15,
                  ),
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 8),
                  SoftTouchWrapper(
                    onTap: () => widget.onDownload(widget.index, widget.user),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: waTeal.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.download_rounded, size: 20, color: waTeal),
                    ),
                  ),
                ],
              ],
            ),
            children: [
              RepaintBoundary(
                key: widget.recordKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  color: widget.isDark ? const Color(0xFF162127) : Colors.grey[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: waTeal, letterSpacing: 1.2)),
                          Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.record.updatedAt)), style: TextStyle(fontSize: 10, color: widget.subTextColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _receiptRow('Transaction ID', widget.record.id.toUpperCase(), widget.textColor, widget.subTextColor),
                      _receiptRow('Type', widget.record.transactionType ?? 'N/A', widget.textColor, widget.subTextColor),
                      _receiptRow('Status', widget.record.transactionStatus ?? 'Processed', widget.textColor, widget.subTextColor),
                      const Divider(height: 32),
                      Row(
                        children: [
                          Expanded(child: _receiptStat('CREDITS', cur.format(widget.record.credits), const Color(0xFF25D366), widget.subTextColor)),
                          Expanded(child: _receiptStat('DEBITS', cur.format(widget.record.impact), Colors.orange, widget.subTextColor)),
                          Expanded(child: _receiptStat('TOTAL', cur.format(widget.record.totalValue), Colors.blue, widget.subTextColor)),
                        ],
                      ),
                      if (widget.record.data.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('ADDITIONAL INFO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: waTeal, letterSpacing: 1)),
                        const SizedBox(height: 12),
                        ...widget.record.data.entries.take(5).map((e) => _receiptRow(e.key, e.value.toString(), widget.textColor, widget.subTextColor)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
        ],
      ),
    );
  }

  Widget _receiptStat(String label, String value, Color color, Color subTextColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
