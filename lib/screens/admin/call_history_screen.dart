import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../../services/admin/call_log_service.dart';
import '../../models/call_log_model.dart';
import '../../services/auth_service.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLog> _logs = [];
  bool _isLoading = true;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingId;
  String? _currentUserId;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (_currentUserId == null) {
        final userData = await _authService.getUser();
        _currentUserId = userData?['id'];
      }
      final logs = await CallLogService.getAdminCallLogs();
      if (mounted) {
        setState(() {
          _logs = logs ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _playRecording(String url, String logId) async {
    if (_currentlyPlayingId == logId) {
      await _audioPlayer.stop();
      setState(() => _currentlyPlayingId = null);
    } else {
      await _audioPlayer.play(UrlSource(url));
      setState(() => _currentlyPlayingId = logId);
    }
  }

  String _getCallTitle(CallLog log) {
    if (_currentUserId == null) return 'Call with ${log.receiver.name}';
    final isOutgoing = log.caller.id == _currentUserId;
    if (isOutgoing) {
      return 'You called ${log.receiver.name}';
    } else {
      final callerName = log.caller.role == 'super_admin' ? 'Super Admin' : log.caller.name;
      return '$callerName called you';
    }
  }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      title: 'Call History',
      currentIndex: 1,
      onRefresh: _loadData,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('No call logs found', style: TextStyle(color: subTextColor)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white),
                        child: const Text('Reload Logs'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => _buildCallCard(_logs[index], isDark, textColor, subTextColor),
                ),
    );
  }

  Widget _buildCallCard(CallLog log, bool isDark, Color textColor, Color subTextColor) {
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final isOutgoing = _currentUserId != null && log.caller.id == _currentUserId;
    bool isMissed = ['missed', 'rejected', 'failed'].contains(log.status);
    bool isPlaying = _currentlyPlayingId == log.id;

    return Container(
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isMissed ? Colors.red.withOpacity(0.1) : (isOutgoing ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMissed ? Icons.call_missed : (isOutgoing ? Icons.call_made : Icons.call_received),
                  color: isMissed ? Colors.redAccent : (isOutgoing ? Colors.blueAccent : const Color(0xFF25D366)),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getCallTitle(log), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                    const SizedBox(height: 4),
                    Text(DateFormat('dd MMM yyyy, hh:mm a').format(log.createdAt), style: TextStyle(color: subTextColor, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(log.status.toUpperCase(), style: TextStyle(color: isMissed ? Colors.redAccent : const Color(0xFF25D366), fontWeight: FontWeight.bold, fontSize: 10)),
                  if (log.duration > 0)
                    Text('${log.duration ~/ 60}:${(log.duration % 60).toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: subTextColor.withOpacity(0.8))),
                ],
              ),
            ],
          ),
          if (log.recordingUrl != null) ...[
            Divider(height: 24, color: isDark ? Colors.white10 : Colors.black12),
            Row(
              children: [
                const Icon(Icons.mic, size: 16, color: Color(0xFF00A884)),
                const SizedBox(width: 8),
                const Text('Recording Available', style: TextStyle(fontSize: 12, color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
                const Spacer(),
                InkWell(
                  onTap: () => _playRecording(log.recordingUrl!, log.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF00A884), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 18, color: Colors.white),
                        const SizedBox(width: 4),
                        const Text(isPlaying ? 'Stop' : 'Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
