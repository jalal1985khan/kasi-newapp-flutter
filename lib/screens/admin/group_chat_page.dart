import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
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
import '../user/media_gallery_screen.dart';
import '../special_widgets/group_call_overlay.dart';

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
  String? _userRole;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;

  SocketService get socket => SocketService();

  // Socket handlers
  late final Function(dynamic) _messageReceiveHandler;
  late final Function(dynamic) _typingStartHandler;
  late final Function(dynamic) _typingStopHandler;
  late final Function(dynamic) _renamedHandler;
  late final Function(dynamic) _deletedHandler;
  late final Function(dynamic) _messageDeletedHandler;
  late final Function(dynamic) _messageEditedHandler;

  @override
  void initState() {
    super.initState();
    _groupName = widget.name;
    _initHandlers();
    _loadData();
    _setupSocket();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    // In a reversed list, scrolling "up" means pixels > 0.
    if (_scrollController.offset > 300 && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    } else if (_scrollController.offset <= 300 && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      setState(() => _highlightedMessageId = messageId);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    }
  }

  void _showMessageOptions(ChatMessage message) {
    final bool isMe = message.senderId == _currentUserId;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222D34) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _initHandlers() {
    _messageReceiveHandler = (data) => _handleIncomingMessage(data);
    _typingStartHandler = (data) {
      final senderId = data['senderId'];
      if (senderId != null && senderId == _currentUserId) return;
      if (data['groupId'] == widget.groupId && mounted) {
        final name = data['senderName'] ?? 'Someone';
        if (!_typingUsers.contains(name)) {
          setState(() => _typingUsers.add(name));
        }
      }
    };
    _typingStopHandler = (data) {
      final senderId = data['senderId'];
      if (senderId != null && senderId == _currentUserId) return;
      if (data['groupId'] == widget.groupId && mounted) {
        final name = data['senderName'] ?? 'Someone';
        setState(() => _typingUsers.remove(name));
      }
    };
    _renamedHandler = (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        setState(() => _groupName = data['newName']);
      }
    };
    _deletedHandler = (data) {
      if (data['groupId'] == widget.groupId && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This group has been deleted by the admin.')),
        );
        Navigator.pop(context);
      }
    };
    _messageDeletedHandler = (data) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id.toString() == data['messageId'].toString());
        });
      }
    };
    _messageEditedHandler = (data) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id.toString() == data['messageId'].toString());
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(content: data['newContent']);
          }
        });
      }
    };
  }

  void _setupSocket() {
    socket.connect();
    socket.emit('group:join', {'groupId': widget.groupId});

    socket.on('group:message:receive', _messageReceiveHandler);
    socket.on('group:typing:start', _typingStartHandler);
    socket.on('group:typing:stop', _typingStopHandler);
    socket.on('group:renamed', _renamedHandler);
    socket.on('group:deleted', _deletedHandler);
    socket.on('group:message:deleted', _messageDeletedHandler);
    socket.on('group:message:edited', _messageEditedHandler);

    // Group call: if someone else starts a call while we are IN this chat
    socket.on('group_call:incoming', (data) {
      if (data['groupId'] == widget.groupId && mounted && !GroupCallOverlayManager.isActive) {
        final overlay = Overlay.of(context);
        IncomingGroupCallOverlayManager.showGlobal(
          overlay,
          callId:      data['callId'] ?? '',
          groupId:     data['groupId'] ?? '',
          groupName:   data['groupName'] ?? widget.name,
          hostName:    data['hostName'] ?? 'Host',
          hostImage:   data['hostImage'] ?? '',
          memberCount: data['memberCount'] ?? 2,
        );
      }
    });
  }

  @override
  void dispose() {
    socket.off('group:message:receive', _messageReceiveHandler);
    socket.off('group:typing:start', _typingStartHandler);
    socket.off('group:typing:stop', _typingStopHandler);
    socket.off('group:renamed', _renamedHandler);
    socket.off('group:deleted', _deletedHandler);
    socket.off('group:message:deleted', _messageDeletedHandler);
    socket.off('group:message:edited', _messageEditedHandler);
    socket.off('group_call:incoming');
    
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _previewPlayer.dispose();
    _scrollController.dispose();
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

      // Auto-scroll to bottom for own messages or if already at bottom
      if (_scrollController.hasClients) {
        final isAtBottom = _scrollController.offset < 100;
        final isMe = message.senderId == _currentUserId;
        if (isAtBottom || isMe) {
          Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
        }
      }
    }
  }

  Future<void> _loadData() async {
    final user = await _authService.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];
    _userRole = user?['role'];

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

  void _sendMessage({
    String type = 'text',
    String? content,
    String? caption,
    String? fileName,
    String? localPath,
    MessageUploadStatus uploadStatus = MessageUploadStatus.success,
    double uploadProgress = 1.0,
    String? existingTempId,
  }) {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && type == 'text') return;

    final tempId = existingTempId ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';

    if (type == 'text' && existingTempId == null) {
      _messageController.clear();
      _typingTimer?.cancel();
      socket.emit('group:typing:stop', {'groupId': widget.groupId});
    }

    if (existingTempId == null) {
      // Optimistic update
      final optimisticMsg = ChatMessage(
        id: tempId,
        conversationId: widget.groupId, // Use groupId as conversationId for groups
        senderId: _currentUserId ?? '',
        receiverId: '', // Groups don't have a single receiver
        type: type,
        content: text,
        fileName: fileName,
        isRead: false,
        deletedFor: [],
        createdAt: DateTime.now(),
        senderName: 'You',
        caption: caption,
        localPath: localPath,
        uploadStatus: uploadStatus,
        uploadProgress: uploadProgress,
      );
      setState(() {
        _messages.insert(0, optimisticMsg);
      });
    } else {
      // Update existing optimistic message status
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == existingTempId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            uploadStatus: uploadStatus,
            uploadProgress: uploadProgress,
            content: text,
            type: type,
          );
        }
      });
    }

    if (uploadStatus == MessageUploadStatus.success) {
      socket.emit('group:message:send', {
        'groupId': widget.groupId,
        'content': text,
        'type': type,
        'caption': caption,
        'fileName': fileName,
        'tempId': tempId,
      });
    }
  }

  Future<void> _uploadAndSend(String path, String caption, String type, {String? id}) async {
    final tempId = id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    // First, show optimistically
    if (id == null) {
      _sendMessage(
        type: type,
        content: '',
        caption: caption,
        fileName: p.basename(path),
        localPath: path,
        uploadStatus: MessageUploadStatus.uploading,
        uploadProgress: 0.0,
        existingTempId: tempId,
      );
    } else {
      _setUploadStatus(tempId, MessageUploadStatus.uploading, 0.0);
    }

    try {
      final uploadRes = await _chatService.uploadMedia(
        path,
        onSendProgress: (sent, total) {
          if (mounted) {
            _setUploadStatus(tempId, MessageUploadStatus.uploading, sent / total);
          }
        },
      );

      if (uploadRes['success'] == true) {
        _sendMessage(
          type: uploadRes['type'] ?? type,
          content: uploadRes['url'],
          caption: caption,
          fileName: p.basename(path),
          localPath: path,
          uploadStatus: MessageUploadStatus.success,
          uploadProgress: 1.0,
          existingTempId: tempId,
        );
      } else {
        _setUploadStatus(tempId, MessageUploadStatus.error, 0.0);
      }
    } catch (e) {
      _setUploadStatus(tempId, MessageUploadStatus.error, 0.0);
    }
  }

  void _setUploadStatus(String tempId, MessageUploadStatus status, double progress) {
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            uploadStatus: status,
            uploadProgress: progress,
          );
        }
      });
    }
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
      // Group voice call button
      IconButton(
        icon: const Icon(Icons.call, color: Colors.white),
        tooltip: 'Group Voice Call',
        onPressed: () async {
          if (GroupCallOverlayManager.isActive) return;
          // Fetch group members for the call
          final groupRes = await _groupChatService.getGroupDetails(widget.groupId);
          final rawMembers = (groupRes['group']?['members'] ?? []) as List;
          final members = rawMembers.map<Map<String, dynamic>>((m) {
            final uid = m['userId'] is Map ? m['userId']['_id'] : m['userId'];
            final name = m['userId'] is Map ? m['userId']['name'] : (m['name'] ?? 'Member');
            return {'userId': uid.toString(), 'name': name.toString()};
          }).toList();
          if (!mounted) return;
          GroupCallOverlayManager.showAsHost(
            context,
            groupId:   widget.groupId,
            groupName: _groupName ?? widget.name,
            members:   members,
          );
        },
      ),
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
                      controller: _scrollController,
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
                              child: _GroupChatBubble(
                                key: _messageKeys[msg.id] ?? (_messageKeys[msg.id] = GlobalKey()),
                                message: msg,
                                isMe: isMe,
                                onLongPress: (msg) => _showMessageOptions(msg),
                                userName: msg.senderName ?? 'User',
                                userRole: msg.senderRole,
                                isHighlighted: _highlightedMessageId == msg.id,
                                onReplyTap: _scrollToMessage,
                                onUploadRetry: (path, caption, type, id) => _uploadAndSend(path, caption, type, id: id),
                              ),
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
        if (_showScrollToBottom)
          Positioned(
            right: 16,
            bottom: 110,
            child: GestureDetector(
              onTap: _scrollToBottom,
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202C33) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.keyboard_double_arrow_down,
                  color: isDark ? Colors.white70 : Colors.black54,
                  size: 24,
                ),
              ),
            ),
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
  final Function(ChatMessage) onLongPress;
  final bool isHighlighted;
  final Function(String)? onReplyTap;
  final Function(String, String, String, String)? onUploadRetry;
  final String userName;
  final String? userRole;

  const _GroupChatBubble({
    super.key,
    required this.message, 
    required this.isMe, 
    required this.onLongPress,
    required this.userName,
    this.userRole,
    this.isHighlighted = false,
    this.onReplyTap,
    this.onUploadRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // WhatsApp Premium Colors
    final Color bubbleMe = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final Color bubbleOther = isDark ? const Color(0xFF232D36) : Colors.white;
    final Color highlightColor = isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color senderColor = isDark ? Colors.blueAccent[100]! : Colors.blueAccent[700]!;
    final Color subTextColor = isDark ? Colors.white54 : (Colors.grey[600] ?? Colors.grey);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: isHighlighted ? highlightColor : Colors.transparent,
      child: GestureDetector(
        onLongPress: () => onLongPress(message),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                  backgroundImage: (message.senderProfileImage != null && message.senderProfileImage!.isNotEmpty)
                      ? NetworkImage(AuthService().getFullUrl(message.senderProfileImage!)!)
                      : null,
                  child: (message.senderProfileImage == null || message.senderProfileImage!.isEmpty)
                      ? Text(
                          (message.senderName ?? 'M')[0].toUpperCase(),
                          style: TextStyle(fontSize: 12, color: senderColor, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Container(
                margin: EdgeInsets.only(
                  left: isMe ? 12 : 8,
                  right: 12,
                  top: 4,
                  bottom: 4,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isMe ? bubbleMe : bubbleOther,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: isMe ? const Radius.circular(15) : const Radius.circular(5),
                    bottomRight: isMe ? const Radius.circular(5) : const Radius.circular(15),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          message.senderName ?? 'Member',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: senderColor,
                          ),
                        ),
                      ),
                    _buildReplyContext(isDark),
                    _buildContent(context, textColor),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const SizedBox(width: 20),
                        Text(
                          DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                          style: TextStyle(fontSize: 10, color: subTextColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyContext(bool isDark) {
    if (message.replyToContent == null) return const SizedBox.shrink();

    final Color barColor = const Color(0xFF53BDEB);
    return GestureDetector(
      onTap: () {
        if (message.replyTo != null && onReplyTap != null) {
          onReplyTap!(message.replyTo!);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: barColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyToSenderName ?? 'Member',
                          style: TextStyle(color: barColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message.replyToContent!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    const double standardWidth = 250.0;
    switch (message.type) {
      case 'image':
        contentWidget = GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MediaGalleryScreen(
                  url: message.content,
                  type: 'image',
                  fileName: message.fileName,
                  senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                  userRole: userRole,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message.content,
              width: standardWidth,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
            ),
          ),
        );
        break;
      case 'audio':
        contentWidget = SizedBox(
          width: standardWidth,
          child: _AudioPlayerWidget(url: message.content, isMe: isMe, initialDuration: message.duration),
        );
        break;
      case 'document':
      case 'file':
      case 'video':
        IconData fileIcon = Icons.insert_drive_file;
        Color iconColor = Colors.blue;
        Color cardBg = Colors.grey.shade50;
        Color cardBorder = Colors.grey.shade200;
        Color badgeBg = Colors.grey.shade100;
        Color badgeText = Colors.grey.shade700;
        String ext = 'FILE';
        bool isVideo = false;

        if (message.fileName != null) {
          ext = message.fileName!.split('.').last.toLowerCase();
          if (ext == 'pdf') {
            fileIcon = Icons.picture_as_pdf;
            iconColor = const Color(0xFFE53935);
            cardBg = const Color(0xFFFFF1F1);
            cardBorder = const Color(0xFFFFD5D5);
            badgeBg = const Color(0xFFFFE0E0);
            badgeText = const Color(0xFFC62828);
          } else if (['xls', 'xlsx', 'csv'].contains(ext)) {
            fileIcon = Icons.table_chart;
            iconColor = const Color(0xFF2E7D32);
            cardBg = const Color(0xFFE8F5E9);
            cardBorder = const Color(0xFFC8E6C9);
            badgeBg = const Color(0xFFC8E6C9);
            badgeText = const Color(0xFF1B5E20);
          } else if (['doc', 'docx'].contains(ext)) {
            fileIcon = Icons.description;
            iconColor = const Color(0xFF1565C0);
            cardBg = const Color(0xFFE3F2FD);
            cardBorder = const Color(0xFFBBDEFB);
            badgeBg = const Color(0xFFBBDEFB);
            badgeText = const Color(0xFF0D47A1);
          } else if (['mp4', 'mov', 'avi'].contains(ext) || message.type == 'video') {
            fileIcon = Icons.video_library;
            iconColor = const Color(0xFFE65100);
            cardBg = const Color(0xFFFFF3E0);
            cardBorder = const Color(0xFFFFE0B2);
            badgeBg = const Color(0xFFFFE0B2);
            badgeText = const Color(0xFFE65100);
            isVideo = true;
          } else {
            fileIcon = Icons.insert_drive_file;
            iconColor = const Color(0xFF3F51B5);
            cardBg = const Color(0xFFE8EAF6);
            cardBorder = const Color(0xFFC5CAE9);
            badgeBg = const Color(0xFFC5CAE9);
            badgeText = const Color(0xFF1A237E);
          }
        } else if (message.type == 'video') {
          fileIcon = Icons.video_library;
          iconColor = const Color(0xFFE65100);
          cardBg = const Color(0xFFFFF3E0);
          cardBorder = const Color(0xFFFFE0B2);
          badgeBg = const Color(0xFFFFE0B2);
          badgeText = const Color(0xFFE65100);
          isVideo = true;
          ext = 'VIDEO';
        }

        // For "me" messages, use a unified transparent overlay card style to fit the dark blue theme perfectly!
        if (isMe) {
          cardBg = Colors.white.withOpacity(0.08);
          cardBorder = Colors.white.withOpacity(0.12);
          badgeBg = Colors.white.withOpacity(0.16);
          badgeText = Colors.white;
          iconColor = Colors.white;
        }

        contentWidget = Container(
          width: standardWidth,
          decoration: BoxDecoration(
            color: cardBg,
            border: Border.all(color: cardBorder, width: 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final isVid = isVideo || (message.fileName != null && 
                    (['mp4', 'mov', 'avi'].contains(message.fileName!.split('.').last.toLowerCase()))) || 
                    message.type == 'video';
                    
                if (isVid) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaGalleryScreen(
                        url: message.content,
                        type: 'video',
                        fileName: message.fileName,
                        senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                        userRole: userRole,
                      ),
                    ),
                  );
                } else {
                  final String extStr = message.fileName?.split('.').last.toLowerCase() ?? '';
                  String type = 'document';
                  if (extStr == 'pdf') type = 'pdf';
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaGalleryScreen(
                        url: message.content,
                        type: type,
                        fileName: message.fileName,
                        senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                        userRole: userRole,
                      ),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isMe ? Colors.white.withOpacity(0.15) : iconColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(fileIcon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.fileName ?? (isVideo ? 'Video file' : 'Document'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isMe ? Colors.white : Colors.blueGrey.shade900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  ext.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: badgeText,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tap to preview',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe ? Colors.white.withOpacity(0.6) : Colors.blueGrey.shade400,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.remove_red_eye_outlined,
                      color: isMe ? Colors.white.withOpacity(0.5) : Colors.blueGrey.shade400,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
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
  const _AudioPlayerWidget({required this.url, required this.isMe, this.initialDuration, super.key});

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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryColor = widget.isMe
        ? (isDark ? const Color(0xFF25D366) : Colors.green[800]!)
        : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              if (_isPlaying) {
                _player.pause();
              } else {
                _player.play(UrlSource(widget.url));
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: primaryColor,
                    inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                    thumbColor: primaryColor,
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble().clamp(
                          0.0,
                          _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                        ),
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.grey[600]),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
