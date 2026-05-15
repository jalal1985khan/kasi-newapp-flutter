import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../user/common_widgets/user_layout.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/group_chat_service.dart';
import '../../models/chat_message_model.dart';
import '../../services/auth_service.dart';
import 'group_info_page.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'individual_chat_page.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;

class GroupChatPage extends StatefulWidget {
  final String groupId;
  final String name;
  final bool isAdmin;

  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.name,
    this.isAdmin = true,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final GroupChatService _groupChatService = GroupChatService();
  final AuthService _authService = AuthService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  bool _isRecording = false;
  double _recordDuration = 0;
  Timer? _recordTimer;
  Timer? _typingTimer;
  List<String> _typingUsers = [];
  String? _groupName;
  bool _showPreview = false;
  String? _audioPath;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;

  SocketService get socket => SocketService();

  @override
  void initState() {
    super.initState();
    _groupName = widget.name;
    _loadData();
    _setupSocket();
  }

  void _setupSocket() {
    socket.connect();
    socket.emit('group:join', {'groupId': widget.groupId});

    socket.on('group:message:receive', (data) => _handleIncomingMessage(data));

    socket.on('group:typing:start', (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        final name = data['senderName'] ?? 'Someone';
        if (!_typingUsers.contains(name)) {
          setState(() => _typingUsers.add(name));
        }
      }
    });

    socket.on('group:typing:stop', (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        final name = data['senderName'] ?? 'Someone';
        setState(() => _typingUsers.remove(name));
      }
    });

    socket.on('group:renamed', (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        setState(() => _groupName = data['newName']);
      }
    });

    socket.on('group:deleted', (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This group has been deleted by the admin.'),
          ),
        );
        Navigator.pop(context);
      }
    });

    // Handle being added to new groups or group deletions if needed
  }

  @override
  void dispose() {
    socket.off('group:message:receive');
    socket.off('group:typing:start');
    socket.off('group:typing:stop');
    socket.off('group:renamed');
    socket.off('group:deleted');
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  void _handleIncomingMessage(dynamic data) {
    if (mounted && data['groupId'] == widget.groupId) {
      final message = ChatMessage.fromJson({
        ...data,
        'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
      });

      setState(() {
        final int tempIndex = _messages.indexWhere((m) {
          final incomingTempId = data['tempId'];
          if (incomingTempId != null && m.id == incomingTempId) return true;
          return m.id.startsWith('temp_') && 
                 m.content == message.content && 
                 m.senderId == message.senderId &&
                 m.type == message.type;
        });

        final int existingIndex = _messages.indexWhere(
          (m) => m.id == message.id,
        );
        
        if (existingIndex != -1) {
          // Ignore duplicate
        } else if (tempIndex != -1) {
          _messages[tempIndex] = message.copyWith(
            caption: message.caption ?? _messages[tempIndex].caption,
          );
        } else {
          _messages.insert(0, message);
        }
      });
      socket.emit('group:message:read', {'groupId': widget.groupId});
    }
  }

  Future<void> _loadData() async {
    final user = await _authService.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];

    try {
      final res = await _groupChatService.getGroupMessages(widget.groupId);
      if (mounted && res['success']) {
        final List msgsData = res['messages'] ?? [];
        final groupData = res['group'];
        setState(() {
          if (groupData != null) _groupName = groupData['name'];
          _messages = msgsData
              .map((m) => ChatMessage.fromJson(m))
              .toList()
              .reversed
              .toList();
          _isLoading = false;
        });
        socket.emit('group:message:read', {'groupId': widget.groupId});
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sendMessage({String type = 'text', String? content}) {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && type == 'text') return;

    if (type == 'text' && content == null) {
      // Quietly send
    }

    if (type == 'text') _messageController.clear();
    setState(() {});

    _typingTimer?.cancel();
    socket.emit('group:typing:stop', {'groupId': widget.groupId});

    socket.emit('group:message:send', {
      'groupId': widget.groupId,
      'content': text,
      'type': type,
      'caption': content != null ? null : null, // This function is simplified, but I'll add the keys anyway
      'tempId': 'temp_${DateTime.now().millisecondsSinceEpoch}',
    });
  }

  void _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  void _stopRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        if (path != null) {
          _audioPath = path;
          _showPreview = true;
          _setupPreviewPlayer();
        }
      });
    } catch (e) {
      debugPrint('Stop recording error: $e');
      setState(() => _isRecording = false);
    }
  }

  void _setupPreviewPlayer() async {
    if (_audioPath == null) return;
    await _previewPlayer.setSourceDeviceFile(_audioPath!);
    _previewPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _previewDuration = d);
    });
    _previewPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _previewPosition = p);
    });
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingPreview = false);
    });
  }

  void _togglePreviewPlay() async {
    if (_isPlayingPreview) {
      await _previewPlayer.pause();
    } else {
      await _previewPlayer.resume();
    }
    setState(() => _isPlayingPreview = !_isPlayingPreview);
  }

  void _sendRecordedVoice() async {
    if (_audioPath == null) return;
    final path = _audioPath!;
    setState(() {
      _showPreview = false;
      _isLoading = true;
    });

    try {
      final uploadResult = await _chatService.uploadMedia(path);
      if (uploadResult['success']) {
        _sendMessage(type: 'audio', content: uploadResult['url']);
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _audioPath = null;
    }
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      final total = result.paths.length;
      int current = 0;

      setState(() => _isLoading = true);
      try {
        for (final path in result.paths) {
          if (path == null) continue;
          current++;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Uploading to group: $current of $total...'),
                duration: const Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          final uploadRes = await _chatService.uploadMedia(path);
          if (uploadRes['success']) {
            _sendMessage(
              type: uploadRes['type'] ?? 'document',
              content: uploadRes['url'],
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Group upload failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message for yourself?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting message from group...'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
      try {
        await _groupChatService.deleteGroupMessage(widget.groupId, messageId);
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdmin) {
      return AdminLayout(
        currentIndex: 3,
        titleWidget: _buildTitleWidget(),
        leading: _buildLeading(),
        onRefresh: _loadData,
        extraActions: _buildExtraActions(),
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5),
        foregroundColor: Colors.white,
        body: _buildBody(),
      );
    } else {
      return UserLayout(
        currentIndex: 1,
        titleWidget: _buildTitleWidget(),
        leading: _buildLeading(),
        onRefresh: _loadData,
        extraActions: _buildExtraActions(),
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5),
        foregroundColor: Colors.white,
        body: _buildBody(),
      );
    }
  }

  Widget _buildTitleWidget() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.white; // AppBar text usually white in both WhatsApp modes

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _groupName ?? widget.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (_typingUsers.isNotEmpty)
          const Text(
            'typing...',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF00A884),
              fontWeight: FontWeight.bold,
            ),
          )
        else
          Text(
            'Group Chat',
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6)),
          ),
      ],
    );
  }

  Widget _buildLeading() {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.pop(context),
    );
  }

  List<Widget> _buildExtraActions() {
    return [
      IconButton(
        icon: const Icon(Icons.info_outline),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupInfoPage(
                groupId: widget.groupId,
                isAdmin: widget.isAdmin,
              ),
            ),
          );
          if (result == true) {
            _loadData();
          }
        },
      ),
    ];
  }

  Future<void> _clearChat() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Clear Chat', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to clear all messages in this group?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );

    if (confirmed == true) {
      await _groupChatService.clearGroupChat(widget.groupId);
      if (mounted) {
        setState(() => _messages.clear());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
      }
    }
  }

  Future<void> _deleteGroup() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Delete Group', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to delete this group?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _groupChatService.deleteGroup(widget.groupId);
      if (result['success'] && mounted) {
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['error']}')));
      }
    }
  }
  Widget _buildBody() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            'https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png',
            fit: BoxFit.cover,
            color: isDark ? Colors.black.withOpacity(0.08) : Colors.black.withOpacity(0.04),
            colorBlendMode: BlendMode.dstIn,
            errorBuilder: (_, __, ___) => Container(color: isDark ? const Color(0xFF0B141B) : const Color(0xFFE5DDD5)),
          ),
        ),
        Column(
          children: [
            Expanded(
              child: (_isLoading && _messages.isEmpty)
                  ? _buildSkeletonLoading()
                  : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      physics: const AlwaysScrollableScrollPhysics(),
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.senderId == _currentUserId;

                        bool showDateSeparator = false;
                        if (index == _messages.length - 1) {
                          showDateSeparator = true;
                        } else {
                          final newerMsg = _messages[index + 1];
                          if (!_isSameDay(msg.createdAt, newerMsg.createdAt)) {
                            showDateSeparator = true;
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showDateSeparator)
                              _buildDateSeparator(msg.createdAt),
                            GestureDetector(
                              onLongPress: isMe
                                  ? () => _deleteMessage(msg.id)
                                  : null,
                              child: _GroupChatBubble(message: msg, isMe: isMe),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
            _buildMessageInput(),
          ],
        ),
      ],
    );
  }

  Widget _buildSkeletonLoading() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF202C33) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF2C3943) : const Color(0xFFF5F5F5),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (context, index) {
          final isMe = index % 2 == 0;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 150 + (index * 15.0) % 100,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageInput() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inputBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: _showPreview
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF202C33) : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFF1A73E8),
                    ),
                    onPressed: _togglePreviewPlay,
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final double maxVal = _previewDuration.inMilliseconds.toDouble();
                        final double currentVal = _previewPosition.inMilliseconds.toDouble();
                        final double sliderMax = maxVal > 0 ? maxVal : (currentVal > 0 ? currentVal + 1000 : 1.0);
                        final double sliderValue = currentVal.clamp(0.0, sliderMax);
                        
                        return Slider(
                          value: sliderValue,
                          max: sliderMax,
                          activeColor: const Color(0xFF1A73E8),
                          onChanged: (val) {
                            _previewPlayer.seek(Duration(milliseconds: val.toInt()));
                          },
                        );
                      }
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      _previewPlayer.stop();
                      setState(() {
                        _showPreview = false;
                        _audioPath = null;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendRecordedVoice,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF00A884) : const Color(0xFF111B21),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.attach_file, color: Color(0xFF8696A0)),
                          onPressed: _pickFiles,
                        ),
                        Expanded(
                          child: _isRecording
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.mic, color: Colors.red, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Recording... ${_recordDuration.toInt()}s',
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : TextField(
                                  controller: _messageController,
                                  style: TextStyle(color: textColor),
                                  onChanged: (val) {
                                    setState(() {});
                                    if (val.isNotEmpty) {
                                      socket.emit('group:typing:start', {
                                        'groupId': widget.groupId,
                                      });
                                    }
                                    _typingTimer?.cancel();
                                    _typingTimer = Timer(
                                      const Duration(seconds: 2),
                                      () {
                                        socket.emit('group:typing:stop', {
                                          'groupId': widget.groupId,
                                        });
                                      },
                                    );
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                  ),
                                ),
                        ),
                        if (_isRecording)
                          IconButton(
                            icon: const Icon(Icons.stop, color: Colors.red),
                            onPressed: _stopRecording,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_messageController.text.isNotEmpty) {
                      _sendMessage();
                    } else if (!_isRecording) {
                      _startRecording();
                    }
                  },
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFF1A73E8),
                    radius: 25,
                    child: Icon(
                      _messageController.text.isNotEmpty ? Icons.send : Icons.mic,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool _isSameDay(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  Widget _buildDateSeparator(DateTime date) {
    String label;
    final now = DateTime.now();
    if (_isSameDay(date, now))
      label = 'Today';
    else if (_isSameDay(date, now.subtract(const Duration(days: 1))))
      label = 'Yesterday';
    else
      label = DateFormat('MMMM dd, yyyy').format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF202C33) : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _GroupChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _GroupChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bubbleMe = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final Color bubbleOther = isDark ? const Color(0xFF232D36) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color senderColor = isDark ? Colors.blueAccent[100]! : Colors.blueAccent[700]!;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? bubbleMe : bubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.senderName ?? 'Member',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: senderColor,
                ),
              ),
            const SizedBox(height: 2),
            _buildContent(context, textColor),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(message.createdAt.toLocal()),
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(
    BuildContext context,
    String url,
    String fileName,
  ) async {
    try {
      final dio = dio_lib.Dio();
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/$fileName';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening $fileName...'),
          duration: const Duration(seconds: 2),
        ),
      );

      final file = File(path);
      if (!await file.exists()) {
        await dio.download(url, path);
      }

      await OpenFilex.open(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    }
  }

  Widget _buildContent(BuildContext context, Color textColor) {
    Widget contentWidget;
    switch (message.type) {
      case 'image':
        contentWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            message.content,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
          ),
        );
        break;
      case 'audio':
        contentWidget = _AudioPlayerWidget(url: message.content, isMe: isMe, initialDuration: message.duration);
        break;
      case 'document':
      case 'file':
      case 'video':
        IconData fileIcon = Icons.insert_drive_file;
        Color iconColor = Colors.blue;

        if (message.fileName != null) {
          final ext = message.fileName!.split('.').last.toLowerCase();
          if (ext == 'pdf') {
            fileIcon = Icons.picture_as_pdf;
            iconColor = Colors.red;
          } else if (['xls', 'xlsx', 'csv'].contains(ext)) {
            fileIcon = Icons.table_chart;
            iconColor = Colors.green;
          } else if (['doc', 'docx', 'txt'].contains(ext)) {
            fileIcon = Icons.description;
            iconColor = Colors.blue;
          } else if (['mp4', 'mov', 'avi'].contains(ext) ||
              message.type == 'video') {
            fileIcon = Icons.video_library;
            iconColor = Colors.orange;
          }
        }

        contentWidget = GestureDetector(
          onTap: () => _openFile(
            context,
            message.content,
            message.fileName ?? 'Attachment',
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fileIcon, color: iconColor, size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.fileName ?? 'Attachment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: iconColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
        break;
      default:
        contentWidget = Text(message.content, style: TextStyle(fontSize: 16, color: textColor));
    }

    if (message.caption != null && message.caption!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          contentWidget,
          const SizedBox(height: 6),
          Text(message.caption!, style: TextStyle(color: textColor, fontSize: 14)),
        ],
      );
    }
    return contentWidget;
  }
}

class _AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  final int? initialDuration;
  const _AudioPlayerWidget({required this.url, required this.isMe, this.initialDuration});

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialDuration != null) {
      _duration = Duration(seconds: widget.initialDuration!);
    }
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            size: 24,
            color: widget.isMe ? Colors.green[800] : Colors.blue,
          ),
          onPressed: () {
            if (_isPlaying)
              _player.pause();
            else
              _player.play(UrlSource(widget.url));
          },
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10
                    : Colors.black12,
                valueColor: AlwaysStoppedAnimation(
                  widget.isMe ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF25D366) : Colors.green[800]) : Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "${_position.inSeconds}s / ${_duration.inSeconds}s",
              style: TextStyle(fontSize: 10, color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.grey[700]),
            ),
          ],
        ),
      ],
    );
  }
}
