import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shimmer/shimmer.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/chat_message_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/group_chat_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/local_database_service.dart';
import '../../services/chat/global_audio_player.dart';
import '../user/attachment_preview_screen.dart';
import '../user/media_gallery_screen.dart';
import '../special_widgets/group_call_overlay.dart';
import '../special_widgets/premium_recording_indicator.dart';
import '../../utils/premium_widgets.dart';
import 'group_info_page.dart';
import '../../services/event_bus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

final _dateFormatter = DateFormat('MMM d, yyyy');
final _timeFormatter = DateFormat('HH:mm');
final _detailFormatter = DateFormat('hh:mm:ss a, MMM dd');

String _thumbnailUrl(String url) {
  if (url.isEmpty) return url;
  if (url.contains('cloudinary.com') || url.contains('thumb_') || url.contains('wsrv.nl')) {
    return url;
  }
  if (url.startsWith('http')) {
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=400&q=60&output=jpg';
  }
  return url;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDate(DateTime d) {
  final now = DateTime.now();
  if (_isSameDay(d, now)) return 'Today';
  if (_isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _dateFormatter.format(d);
}

String _formatTime(DateTime d) => _timeFormatter.format(d);

// ─────────────────────────────────────────────────────────────────────────────
// GroupChatPage
// ─────────────────────────────────────────────────────────────────────────────

class GroupChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? groupImage;

  const GroupChatPage({
    super.key,
    required this.groupId,
    String? groupName,
    String? name,            // backward-compat alias
    this.groupImage,
    bool isAdmin = true,     // backward-compat param (ignored, role comes from auth)
  }) : groupName = groupName ?? name ?? '';

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  // ─── Services ──────────────────────────────────────────────────────────────
  final ChatService _chatService = ChatService();
  final GroupChatService _groupService = GroupChatService();
  final SocketService _socket = SocketService();
  final LocalDatabaseService _db = LocalDatabaseService();
  final AuthService _auth = AuthService();

  // ─── Controllers ───────────────────────────────────────────────────────────
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();

  // ─── State ────────────────────────────────────────────────────────────────
  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _members = [];
  final List<String> _typingUsers = [];
  bool _isLoading = true;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _showScrollToBottom = false;

  String? _currentUserId;
  String? _userRole;
  String _groupName = '';

  ChatMessage? _replyingTo;
  final bool _showEmojiPicker = false;

  // ─── Audio Recording ───────────────────────────────────────────────────────
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _audioPath;
  bool _showAudioPreview = false;

  // ─── Message Keys (for scroll to reply) ───────────────────────────────────
  final Map<String, GlobalKey> _msgKeys = {};
  String? _highlightedMessageId;

  StreamSubscription? _socketSubscription;
  StreamSubscription? _eventBusSubscription;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
    _scrollCtrl.addListener(_onScroll);
    
    _eventBusSubscription = EventBus().stream.listen((event) {
      if (event == 'fcm_refresh' && mounted) {
        _syncFromServer();
      }
    });
    
    _init();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _eventBusSubscription?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _recorder.dispose();
    _previewPlayer.dispose();
    _recordTimer?.cancel();
    _socket.off('group:message:new');
    _socket.off('group:message:receive');
    _socket.off('group:typing:start');
    _socket.off('group:typing:stop');
    _socket.off('group:message:deleted');
    _socket.off('group:message:reaction');
    super.dispose();
  }

  // ─── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final user = await _auth.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];
    _userRole = user?['role'];

    // 1. Show local cache immediately
    await _loadFromLocalDB();

    // 2. Setup socket
    _setupSocket();

    // 3. Sync from server in background
    _syncFromServer();

    // 4. Load members
    _loadMembers();

    // Scroll to bottom after first load
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  List<ChatMessage> _preserveLocalState(List<ChatMessage> freshMessages) {
    final tempMessages = <String, ChatMessage>{};
    final activeTempUploads = <ChatMessage>[];
    for (final m in _messages) {
      if (m.localPath != null) {
        tempMessages[m.id] = m;
      }
      if (m.id.startsWith('temp_')) {
        activeTempUploads.add(m);
      }
    }
    
    for (int i = 0; i < freshMessages.length; i++) {
      final existing = tempMessages[freshMessages[i].id];
      if (existing != null) {
        freshMessages[i] = freshMessages[i].copyWith(
          localPath: existing.localPath,
          uploadStatus: existing.uploadStatus,
          uploadProgress: existing.uploadProgress,
        );
      }
    }
    for (final tempMsg in activeTempUploads) {
      if (!freshMessages.any((m) => m.id == tempMsg.id)) {
        freshMessages.insert(0, tempMsg);
      }
    }
    freshMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return freshMessages;
  }

  Future<void> _loadFromLocalDB() async {
    try {
      final cached = await _db.getMessagesByConversation(widget.groupId);
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _messages = _preserveLocalState(cached);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupChat] loadFromLocalDB: $e');
    }
  }

  Future<void> _syncFromServer() async {
    try {
      final res = await _groupService.getGroupMessages(widget.groupId);
      if (!mounted) return;

      final rawList = res['messages'] as List? ?? [];
      if (rawList.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final serverMessages = rawList
          .map((e) => _groupMessageFromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList(); // newest first → index 0 = bottom

      // Upsert to local DB
      await _db.insertMessages(serverMessages);

      // Re-read merged data from local DB (avoids visual flash from swapping lists)
      final mergedMessages = await _db.getMessagesByConversation(widget.groupId);

      if (mounted) {
        setState(() {
          _messages = _preserveLocalState(mergedMessages);
          _hasMore = res['hasMore'] == true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupChat] syncFromServer: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final res = await _groupService.getGroupMessages(
        widget.groupId,
        beforeId: _messages.last.id,
      );
      final rawList = res['messages'] as List? ?? [];
      final more = rawList
          .map((e) => _groupMessageFromJson(e))
          .toList()
          .reversed
          .toList(); // oldest pages go to end
      await _db.insertMessages(more);
      if (mounted) {
        setState(() {
          _messages.addAll(more); // older messages appended to end (rendered at top)
          _hasMore = res['hasMore'] == true;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final res = await _groupService.getGroupDetails(widget.groupId);
      final group = res['group'] as Map<String, dynamic>? ?? {};
      final rawMembers = group['members'] as List? ?? [];
      if (mounted) {
        setState(() {
          _members = rawMembers
              .map((m) => {
                    'userId': m['userId']?['_id'] ?? m['userId'],
                    'name': m['userId']?['name'] ?? 'Member',
                    'role': m['role'] ?? 'member',
                    'profileImage': m['userId']?['profileImage'],
                  })
              .toList();
          _groupName = group['name'] ?? widget.groupName;
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupChat] loadMembers: $e');
    }
  }

  // ─── Socket ────────────────────────────────────────────────────────────────

  void _setupSocket() {
    _socketSubscription?.cancel();
    _socketSubscription = _socket.connectionStatus.listen((connected) {
      if (connected && mounted) {
        _socket.emit('group:join', {'groupId': widget.groupId});
        _syncFromServer(); // Fetch messages on reconnect/FCM wake
      }
    });

    void handleIncoming(dynamic data) {
      if (!mounted) return;
      final incoming = _groupMessageFromJson(data as Map<String, dynamic>);

      ChatMessage finalMsg = incoming;

      // Skip my own messages already added optimistically
      if (incoming.senderId == _currentUserId) {
        final tempIdx = _messages.indexWhere((m) {
          final tempId = data['tempId']?.toString();
          return (tempId != null && m.id == tempId) ||
              (m.id.startsWith('temp_') &&
                  m.content == incoming.content &&
                  m.type == incoming.type);
        });
        if (mounted) {
          setState(() {
            if (tempIdx != -1) {
              finalMsg = incoming.copyWith(
                localPath: incoming.localPath ?? _messages[tempIdx].localPath,
                previewUrl: incoming.previewUrl ?? _messages[tempIdx].previewUrl,
              );
              _messages[tempIdx] = finalMsg;
            } else {
              _messages.insert(0, incoming);
            }
          });
        }
      } else {
        final exists = _messages.any((m) => m.id == incoming.id);
        if (!exists && mounted) {
          setState(() => _messages.insert(0, incoming));
        }
      }
      _db.insertMessage(finalMsg);
      _scrollToBottomIfNear();
    }

    _socket.on('group:message:new', handleIncoming);
    _socket.on('group:message:receive', handleIncoming);

    _socket.on('group:typing:start', (data) {
      if (!mounted) return;
      final name = data['userName']?.toString() ?? '';
      if (name.isNotEmpty && data['userId'] != _currentUserId) {
        setState(() {
          if (!_typingUsers.contains(name)) _typingUsers.add(name);
        });
      }
    });

    _socket.on('group:typing:stop', (data) {
      if (!mounted) return;
      final name = data['userName']?.toString() ?? '';
      setState(() => _typingUsers.remove(name));
    });

    _socket.on('group:message:deleted', (data) {
      if (!mounted) return;
      final msgId = data['messageId']?.toString() ?? '';
      setState(() => _messages.removeWhere((m) => m.id == msgId));
      _db.deleteMessage(msgId);
    });

    _socket.on('group:message:reaction', (data) {
      if (!mounted) return;
      final msgId = data['messageId']?.toString() ?? '';
      final emoji = data['emoji']?.toString();
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(reaction: emoji);
        }
      });
    });
  }

  // ─── Messaging ────────────────────────────────────────────────────────────

  Timer? _typingTimer;

  void _onTyping() {
    _typingTimer?.cancel();
    _socket.emit('group:typing:start', {
      'groupId': widget.groupId,
      'userId': _currentUserId,
      'userName': 'You',
    });
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _socket.emit('group:typing:stop', {
        'groupId': widget.groupId,
        'userId': _currentUserId,
      });
    });
  }

  void _sendTextMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    _typingTimer?.cancel();
    _socket.emit('group:typing:stop', {'groupId': widget.groupId});
    _sendMessage(type: 'text', content: text);
  }

  void _sendMessage({
    required String type,
    String content = '',
    String? caption,
    String? fileName,
    String? localPath,
    String? previewUrl,
    MessageUploadStatus uploadStatus = MessageUploadStatus.success,
    double uploadProgress = 1.0,
    String? existingTempId,
  }) {
    String? replyTo = _replyingTo?.id;
    String? replyToContent;
    String? replyToSenderName;

    if (_replyingTo != null) {
      replyToSenderName = _replyingTo!.senderId == _currentUserId
          ? 'You'
          : (_replyingTo!.senderName ?? 'Someone');
      replyToContent = _replyingTo!.type == 'image'
          ? 'Photo'
          : _replyingTo!.type == 'video'
              ? 'Video'
              : _replyingTo!.type == 'audio'
                  ? 'Voice message'
                  : (_replyingTo!.content);
    }

    final tempId = existingTempId ??
        'temp_${DateTime.now().millisecondsSinceEpoch}_${content.hashCode}';

    final optimistic = ChatMessage(
      id: tempId,
      conversationId: widget.groupId,
      senderId: _currentUserId ?? '',
      receiverId: '',
      type: type,
      content: content,
      caption: caption,
      fileName: fileName,
      localPath: localPath,
      previewUrl: previewUrl,
      uploadStatus: uploadStatus,
      uploadProgress: uploadProgress,
      isRead: false,
      deletedFor: [],
      createdAt: DateTime.now(),
      senderName: 'You',
      replyTo: replyTo,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );

    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = optimistic;
        } else {
          _messages.insert(0, optimistic);
          _db.insertMessage(optimistic);
        }
        _replyingTo = null;
      });
      _scrollToBottom();
    } else {
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx == -1) {
        _db.insertMessage(optimistic);
      }
    }

    if (uploadStatus == MessageUploadStatus.uploading) return;

    _socket.emit('group:message:send', {
      'groupId': widget.groupId,
      'content': content,
      'type': type,
      'replyTo': replyTo,
      'replyToContent': replyToContent,
      'replyToSenderName': replyToSenderName,
      'caption': caption,
      'fileName': fileName,
      'tempId': tempId,
      'previewUrl': previewUrl,
      'preview_url': previewUrl,
    });
  }

  Future<void> _uploadAndSend(
    String path,
    String caption,
    String type, {
    String? id,
  }) async {
    final tempId =
        id ?? 'temp_upload_${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}';

    _updateMessage(tempId, uploadStatus: MessageUploadStatus.uploading, uploadProgress: 0.0);

    try {
      final res = await _chatService.uploadMedia(
        path,
        onSendProgress: (sent, total) {
          if (total > 0) {
            _updateMessage(tempId, uploadProgress: sent / total);
          }
        },
      );

      if (res['success'] == true) {
        _sendMessage(
          type: type,
          content: res['originalUrl'] ?? res['url'] ?? '',
          previewUrl: res['url'],
          caption: caption,
          fileName: p.basename(path),
          localPath: path,
          uploadStatus: MessageUploadStatus.success,
          uploadProgress: 1.0,
          existingTempId: tempId,
        );
      } else {
        _updateMessage(tempId, uploadStatus: MessageUploadStatus.error);
      }
    } catch (e) {
      debugPrint('❌ [GroupChat] upload failed: $e');
      _updateMessage(tempId, uploadStatus: MessageUploadStatus.error);
    }
  }

  void _updateMessage(
    String id, {
    MessageUploadStatus? uploadStatus,
    double? uploadProgress,
  }) {
    if (!mounted) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          uploadStatus: uploadStatus,
          uploadProgress: uploadProgress,
        );
      }
    });
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Delete this message for everyone?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _messages.removeWhere((m) => m.id == msg.id));
    await _db.deleteMessage(msg.id);
    await _groupService.deleteGroupMessage(widget.groupId, msg.id);
    _socket.emit('group:message:delete', {
      'groupId': widget.groupId,
      'messageId': msg.id,
    });
  }

  void _reactToMessage(ChatMessage msg, String? emoji) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) _messages[idx] = _messages[idx].copyWith(reaction: emoji);
    });
    _groupService.updateReaction(widget.groupId, msg.id, emoji);
    _socket.emit('group:message:react', {
      'groupId': widget.groupId,
      'messageId': msg.id,
      'emoji': emoji,
    });
  }

  // ─── File Picking ─────────────────────────────────────────────────────────

  Future<void> _handlePickedPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final previewResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AttachmentPreviewScreen(filePaths: paths, userName: widget.groupName),
      ),
    );

    if (previewResult is List) {
      for (final item in previewResult) {
        final path = item['path'] as String?;
        final caption = (item['caption'] as String?) ?? '';
        if (path == null) continue;

        final ext = p.extension(path).toLowerCase();
        String type = 'document';
        if (['.jpg', '.jpeg', '.png', '.gif'].contains(ext)) type = 'image';
        if (['.mp4', '.mov', '.avi'].contains(ext)) type = 'video';
        if (['.mp3', '.m4a', '.wav'].contains(ext)) type = 'audio';

        final tempId =
            'temp_upload_${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}';

        _sendMessage(
          type: type,
          content: '',
          caption: caption,
          fileName: p.basename(path),
          localPath: path,
          uploadStatus: MessageUploadStatus.uploading,
          uploadProgress: 0.05,
          existingTempId: tempId,
        );
        _uploadAndSend(path, caption, type, id: tempId);
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      _handlePickedPaths(result.paths.whereType<String>().toList());
    }
  }

  Future<void> _pickGallery() async {
    final images = await ImagePicker().pickMultiImage();
    if (images.isNotEmpty) {
      _handlePickedPaths(images.map((x) => x.path).toList());
    }
  }

  Future<void> _pickCamera() async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera);
    if (image != null) _handlePickedPaths([image.path]);
  }

  // ─── Audio Recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      if (path != null) {
        _audioPath = path;
        _showAudioPreview = true;
      }
    });
  }

  Future<void> _sendVoiceNote() async {
    final path = _audioPath;
    if (path == null) return;
    setState(() {
      _showAudioPreview = false;
      _audioPath = null;
    });
    final tempId = 'temp_voice_${DateTime.now().millisecondsSinceEpoch}';
    _sendMessage(
      type: 'audio',
      content: '',
      fileName: p.basename(path),
      localPath: path,
      uploadStatus: MessageUploadStatus.uploading,
      uploadProgress: 0.05,
      existingTempId: tempId,
    );
    _uploadAndSend(path, '', 'audio', id: tempId);
  }

  // ─── Scroll ────────────────────────────────────────────────────────────────

  void _onScroll() {
    final atTop = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200;
    if (atTop && !_isLoadingMore) _loadMoreMessages();
    final showBtn = _scrollCtrl.offset > 300;
    if (showBtn != _showScrollToBottom) {
      setState(() => _showScrollToBottom = showBtn);
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _scrollToBottomIfNear() {
    if (_scrollCtrl.hasClients && _scrollCtrl.offset < 200) {
      _scrollToBottom();
    }
  }

  Future<void> _scrollToMessage(String messageId) async {
    // Step 1: Message is already rendered
    final key = _msgKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.5);
      _flashHighlight(messageId);
      return;
    }

    // Step 2: Message is virtualized — scroll to estimated offset then retry
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    if (_scrollCtrl.hasClients) {
      final estimatedOffset = idx * 72.0;
      await _scrollCtrl.animateTo(
        estimatedOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }

    await Future.delayed(const Duration(milliseconds: 100));

    final retryCtx = _msgKeys[messageId]?.currentContext;
    if (retryCtx != null) {
      await Scrollable.ensureVisible(retryCtx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5);
      _flashHighlight(messageId);
    }
  }

  void _flashHighlight(String messageId) {
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  // ─── Long Press Menu ──────────────────────────────────────────────────────

  void _showMessageOptions(BuildContext ctx, ChatMessage msg) {
    final isMe = msg.senderId == _currentUserId;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1F2C34) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Emoji reactions row
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['❤️', '😂', '😮', '😢', '👍', '🙏'].map((e) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _reactToMessage(
                              msg, msg.reaction == e ? null : e);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: msg.reaction == e
                                ? Colors.amber.withValues(alpha: 0.2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(e, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                _menuItem(Icons.reply, 'Reply', textColor, () {
                  Navigator.pop(ctx);
                  setState(() => _replyingTo = msg);
                }),
                if (msg.type == 'text')
                  _menuItem(Icons.copy, 'Copy', textColor, () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')));
                  }),
                _menuItem(Icons.info_outline, 'Info', textColor, () {
                  Navigator.pop(ctx);
                  _showMessageInfo(msg);
                }),
                _menuItem(Icons.forward, 'Forward', textColor, () {
                  Navigator.pop(ctx);
                  _forwardMessage(msg);
                }),
                if (isMe)
                  _menuItem(Icons.delete, 'Delete', Colors.red, () {
                    Navigator.pop(ctx);
                    _deleteMessage(msg);
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }

  void _showMessageInfo(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sent: ${DateFormat('hh:mm:ss a, MMM dd').format(message.createdAt.toLocal())}'),
            const SizedBox(height: 8),
            Text('Status: ${message.isRead ? "Read" : "Delivered"}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _forwardMessage(ChatMessage message) async {
    final chatService = ChatService();
    final allPartners = await chatService.getPartners();
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final Color bgColor = isDark ? const Color(0xFF111B21) : Colors.white;
          final Color textColor = isDark ? Colors.white : Colors.black87;
          
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Forward to...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: allPartners.length,
                      itemBuilder: (context, index) {
                        final partner = allPartners[index];
                        final name = partner['name'] ?? 'Unknown';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF00A884).withOpacity(0.2),
                            child: Text(name[0].toUpperCase(), style: const TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
                          ),
                          title: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                          onTap: () async {
                            Navigator.pop(context);
                            final convId = await chatService.startConversation(partner['_id'] ?? partner['id']);
                            if (convId != null) {
                              SocketService().emit('message:send', {
                                'conversationId': convId,
                                'receiverId': partner['_id'] ?? partner['id'],
                                'content': message.content,
                                'type': message.type,
                                'isForwarded': true,
                                'replyToContent': message.replyToContent,
                                'replyToSenderName': message.replyToSenderName,
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Forwarded to $name'),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: const Color(0xFF00A884),
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Attachment Sheet ─────────────────────────────────────────────────────

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1F2C34) : Colors.white;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _attachBtn(Icons.camera_alt, 'Camera', Colors.orange, () {
                      Navigator.pop(ctx);
                      _pickCamera();
                    }),
                    _attachBtn(Icons.image, 'Gallery', Colors.purple, () {
                      Navigator.pop(ctx);
                      _pickGallery();
                    }),
                    _attachBtn(Icons.insert_drive_file, 'Document', Colors.teal, () {
                      Navigator.pop(ctx);
                      _pickFiles();
                    }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _attachBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5),
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Wallpaper
                Positioned.fill(
                  child: Image.asset(
                    isDark
                        ? 'assets/images/chat_bg_dark.png'
                        : 'assets/images/chat_bg_light.png',
                    fit: BoxFit.cover,
                  ),
                ),
                // Messages
                _isLoading
                    ? _buildSkeleton(isDark)
                    : _buildMessageList(isDark),
                // Scroll to bottom button
                if (_showScrollToBottom)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: GestureDetector(
                      onTap: _scrollToBottom,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF202C33)
                              : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8)
                          ],
                        ),
                        child: Icon(Icons.keyboard_double_arrow_down,
                            color:
                                isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Typing indicator
          if (_typingUsers.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                '${_typingUsers.join(', ')} ${_typingUsers.length == 1 ? 'is' : 'are'} typing...',
                style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ),
          // Reply bar
          if (_replyingTo != null) _buildReplyBar(isDark),
          // Audio preview
          if (_showAudioPreview) _buildAudioPreviewBar(isDark),
          // Input
          _buildInput(isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF202C33) : const Color(0xFF075E54),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoPage(
              groupId: widget.groupId,
              groupName: _groupName,
              members: _members,
              onGroupUpdated: (name, members) {
                setState(() {
                  _groupName = name;
                  _members = members;
                });
              },
            ),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF00A884),
              backgroundImage: widget.groupImage != null &&
                      widget.groupImage!.isNotEmpty
                  ? NetworkImage(
                      AuthService().getFullUrl(widget.groupImage) ??
                          widget.groupImage!)
                  : null,
              child:
                  widget.groupImage == null || widget.groupImage!.isEmpty
                      ? Text(
                          _groupName.isNotEmpty
                              ? _groupName[0].toUpperCase()
                              : 'G',
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_groupName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(
                    _typingUsers.isNotEmpty
                        ? '${_typingUsers.first} typing...'
                        : '${_members.length} members',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call, color: Colors.white),
          onPressed: () {
            if (_members.isEmpty) return;
            GroupCallOverlayManager.showAsHost(
              context,
              groupId: widget.groupId,
              groupName: _groupName,
              members: _members,
            );
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) async {
            if (v == 'info') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupInfoPage(
                    groupId: widget.groupId,
                    groupName: _groupName,
                    members: _members,
                    onGroupUpdated: (name, members) =>
                        setState(() {
                          _groupName = name;
                          _members = members;
                        }),
                  ),
                ),
              );
            } else if (v == 'clear') {
              await _groupService.clearGroupChat(widget.groupId);
              setState(() => _messages.clear());
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'info', child: Text('Group Info')),
            const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList(bool isDark) {
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      itemCount: _messages.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF00A884))),
          );
        }
        final msg = _messages[i];
        final isMe = msg.senderId == _currentUserId;

        bool showDate = false;
        if (i == _messages.length - 1) {
          showDate = true;
        } else {
          final older = _messages[i + 1];
          if (!_isSameDay(msg.createdAt, older.createdAt)) showDate = true;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate) _buildDateSep(msg.createdAt, isDark),
            TweenAnimationBuilder<double>(
              key: ValueKey('hl_${msg.id}_${_highlightedMessageId == msg.id ? 1 : 0}'),
              tween: Tween<double>(
                begin: _highlightedMessageId == msg.id ? 1.0 : 0.0,
                end: 0.0,
              ),
              duration: const Duration(milliseconds: 1800),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                final highlightColor = isDark
                    ? Colors.white.withOpacity(value * 0.15)
                    : const Color(0xFF00A884).withOpacity(value * 0.12);
                return Container(
                  decoration: BoxDecoration(
                    color: highlightColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: value > 0.1
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00A884).withOpacity(value * 0.2),
                              blurRadius: 10 * value,
                              spreadRadius: value,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: Dismissible(
                key: _msgKeys[msg.id] ??= GlobalKey(),
                direction: DismissDirection.startToEnd,
                confirmDismiss: (_) async {
                  setState(() => _replyingTo = msg);
                  return false;
                },
                background: Container(
                  padding: const EdgeInsets.only(left: 20),
                  alignment: Alignment.centerLeft,
                  child: const Icon(Icons.reply, color: Color(0xFF00A884)),
                ),
                child: _GroupBubble(
                  message: msg,
                  isMe: isMe,
                  currentUserId: _currentUserId ?? '',
                  onLongPress: () => _showMessageOptions(ctx, msg),
                  onReplyTap: (id) => _scrollToMessage(id),
                  onUploadRetry: (path, caption, type, id) =>
                      _uploadAndSend(path, caption, type, id: id),
                  userRole: _userRole ?? '',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateSep(DateTime date, bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _formatDate(date),
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildReplyBar(bool isDark) {
    final msg = _replyingTo!;
    final bg = isDark ? const Color(0xFF2A3942) : const Color(0xFFF0F2F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bg,
      child: Row(
        children: [
          Container(
              width: 3, height: 44, color: const Color(0xFF00A884)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.senderId == _currentUserId
                      ? 'You'
                      : (msg.senderName ?? 'Member'),
                  style: const TextStyle(
                      color: Color(0xFF00A884),
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
                Text(
                  msg.type == 'image'
                      ? '📷 Photo'
                      : msg.type == 'video'
                          ? '🎥 Video'
                          : msg.type == 'audio'
                              ? '🎤 Voice'
                              : (msg.content.isEmpty
                                  ? msg.type
                                  : msg.content),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          )
        ],
      ),
    );
  }

  Widget _buildAudioPreviewBar(bool isDark) {
    final bg = isDark ? const Color(0xFF2A3942) : const Color(0xFFF0F2F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bg,
      child: Row(
        children: [
          const Icon(Icons.mic, color: Color(0xFF00A884)),
          const SizedBox(width: 8),
          Text('Voice note (${_recordSeconds}s)',
              style: const TextStyle(fontSize: 13)),
          const Spacer(),
          TextButton(
            onPressed: () =>
                setState(() => _showAudioPreview = false),
            child: const Text('Discard',
                style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A884)),
            onPressed: _sendVoiceNote,
            child: const Text('Send',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    const Color waTeal = Color(0xFF00A884);
    final Color inputBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null) _buildReplyPreview(isDark),
          _showAudioPreview
              ? _buildAudioPreviewBar(isDark)
              : Row(
                  children: [
                    _isRecording
                        ? Expanded(
                            child: PremiumRecordingIndicator(
                              duration: Duration(seconds: _recordSeconds),
                              onCancel: () {
                                _recordTimer?.cancel();
                                _recorder.stop();
                                setState(() => _isRecording = false);
                              },
                              onStop: _stopRecording,
                            ),
                          )
                        : Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.attach_file, color: isDark ? Colors.white60 : Colors.grey),
                                    onPressed: _showAttachmentSheet,
                                  ),
                                  Expanded(
                                    child: Container(
                                      constraints: const BoxConstraints(maxHeight: 120),
                                      child: TextField(
                                        controller: _textCtrl,
                                        focusNode: _focusNode,
                                        maxLines: null,
                                        style: TextStyle(color: textColor),
                                        decoration: InputDecoration(
                                          hintText: 'Message',
                                          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                        ),
                                        onChanged: (_) => _onTyping(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    if (!_isRecording) ...[
                      const SizedBox(width: 8),
                      SoftTouchWrapper(
                        onTap: () {
                          if (_textCtrl.text.isNotEmpty) {
                            _sendTextMessage();
                          } else {
                            _startRecording();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: waTeal,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: waTeal.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _textCtrl,
                            builder: (_, v, _) => AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                v.text.trim().isNotEmpty ? Icons.send : Icons.mic,
                                key: ValueKey(v.text.trim().isNotEmpty),
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
    ),);
  }
  Widget _buildReplyPreview(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: isDark ? Colors.black26 : Colors.black12,
          borderRadius: BorderRadius.circular(12),
          border: const Border(left: BorderSide(color: Color(0xFF53BDEB), width: 4))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _replyingTo!.senderId == _currentUserId
                        ? 'You'
                        : (_replyingTo!.senderName ?? 'Member'),
                    style: const TextStyle(
                        color: Color(0xFF53BDEB),
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                Text(_replyingTo!.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _replyingTo = null)),
        ],
      ),
    );
  }

  Widget _buildSkeleton(bool isDark) {
    return Shimmer.fromColors(
      baseColor:
          isDark ? const Color(0xFF202C33) : const Color(0xFFE0E0E0),
      highlightColor:
          isDark ? const Color(0xFF2C3943) : const Color(0xFFF5F5F5),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, i) => Align(
          alignment:
              i % 2 == 0 ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            width: 140 + (i * 18.0) % 100,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Parse helper ─────────────────────────────────────────────────────────

  ChatMessage _groupMessageFromJson(Map<String, dynamic> json) {
    // The group API returns sender as an object or as a flat field
    final senderObj = json['sender'] as Map<String, dynamic>?;
    final senderId = senderObj?['_id']?.toString() ??
        senderObj?['id']?.toString() ??
        json['senderId']?.toString() ??
        '';
    final senderName = senderObj?['name']?.toString() ?? json['senderName']?.toString();
    final senderImage = senderObj?['profileImage']?.toString() ??
        json['senderProfileImage']?.toString();

    return ChatMessage(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      conversationId: widget.groupId,
      senderId: senderId,
      receiverId: '',
      type: json['type']?.toString() ?? 'text',
      content: json['content']?.toString() ?? '',
      fileName: json['fileName']?.toString(),
      fileSize: (json['fileSize'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      isRead: json['isRead'] == true || json['isRead'] == 1,
      readAt: json['readAt'] != null
          ? DateTime.tryParse(json['readAt'].toString())
          : null,
      deletedFor: List<String>.from(json['deletedFor'] ?? []),
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      senderName: senderName,
      senderRole: json['senderRole']?.toString(),
      reaction: json['reaction']?.toString(),
      replyTo: json['replyTo']?.toString(),
      replyToContent: json['replyToContent']?.toString(),
      replyToSenderName: json['replyToSenderName']?.toString(),
      isForwarded: json['isForwarded'] == true,
      caption: json['caption']?.toString(),
      senderProfileImage: senderImage,
      previewUrl: json['previewUrl']?.toString() ?? json['preview_url']?.toString(),
      uploadProgress: 1.0,
      uploadStatus: MessageUploadStatus.success,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GroupBubble — pure StatelessWidget, zero nullable bang operators
// ─────────────────────────────────────────────────────────────────────────────

class _GroupBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final String currentUserId;
  final VoidCallback onLongPress;
  final void Function(String messageId) onReplyTap;
  final void Function(String path, String caption, String type, String? id) onUploadRetry;
  final String userRole;

  const _GroupBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.currentUserId,
    required this.onLongPress,
    required this.onReplyTap,
    required this.onUploadRetry,
    required this.userRole,
  });

  static const double _maxWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUploading = message.uploadStatus == MessageUploadStatus.uploading;
    final isError = message.uploadStatus == MessageUploadStatus.error;

    final bubbleBg = isMe
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
        : (isDark ? const Color(0xFF1F2C34) : Colors.white);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth + 40),
          child: Container(
            margin: EdgeInsets.only(
              top: 2,
              bottom: 2,
              left: isMe ? 60 : 8,
              right: isMe ? 8 : 60,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Avatar (non-me only)
                if (!isMe) ...[
                  _buildAvatar(),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment:
                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      // Sender name (non-me)
                      if (!isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            message.senderName ?? 'Member',
                            style: TextStyle(
                              color: _senderColor(message.senderId),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: bubbleBg,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(15),
                              topRight: const Radius.circular(15),
                              bottomLeft: Radius.circular(isMe ? 15 : 5),
                              bottomRight: Radius.circular(isMe ? 5 : 15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1))
                            ],
                          ),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Reply quote
                            if (message.replyTo != null &&
                                message.replyToContent != null)
                              _buildReplyQuote(isDark),
                            // Content
                            _buildContent(context, isDark, textColor, subColor),
                            // Caption
                            if (message.caption != null &&
                                message.caption!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(message.caption!,
                                    style: TextStyle(
                                        color: textColor, fontSize: 13)),
                              ),
                            // Upload progress
                            if (isUploading)
                              _buildProgressBar(isDark),
                            if (isError)
                              _buildRetryButton(),
                            // Time + read
                            _buildTimestamp(isDark, subColor),
                          ],
                        ),
                      ),
                      ),
                      // Reaction
                      if (message.reaction != null &&
                          message.reaction!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(message.reaction!,
                              style: const TextStyle(fontSize: 16)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _senderColor(String senderId) {
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF8E24AA),
      const Color(0xFF1E88E5),
      const Color(0xFF00897B),
      const Color(0xFFF4511E),
      const Color(0xFF6D4C41),
    ];
    final idx = senderId.codeUnits.fold<int>(0, (s, c) => s + c) % colors.length;
    return colors[idx];
  }

  Widget _buildAvatar() {
    final imageUrl = message.senderProfileImage != null &&
            message.senderProfileImage!.isNotEmpty
        ? (AuthService().getFullUrl(message.senderProfileImage) ??
            message.senderProfileImage!)
        : null;
    final name = message.senderName ?? 'M';

    return CircleAvatar(
      radius: 14,
      backgroundColor: _senderColor(message.senderId),
      backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
      child: imageUrl == null
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'M',
              style: const TextStyle(color: Colors.white, fontSize: 11))
          : null,
    );
  }

  Widget _buildReplyQuote(bool isDark) {
    return GestureDetector(
      onTap: () {
        if (message.replyTo != null) onReplyTap(message.replyTo!);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: Color(0xFF00A884), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.replyToSenderName ?? 'Member',
              style: const TextStyle(
                  color: Color(0xFF00A884),
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              message.replyToContent ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext ctx, bool isDark, Color textColor, Color subColor) {
    switch (message.type) {
      case 'text':
        return SelectableText(
          message.content,
          style: TextStyle(color: textColor, fontSize: 14.5, height: 1.35),
        );

      case 'image':
        return _buildImageBubble(ctx, isDark);

      case 'video':
        return _buildVideoBubble(ctx, isDark);

      case 'audio':
        return SizedBox(
          width: _maxWidth,
          child: _AudioBubble(
            url: AuthService().getFullUrl(message.content) ?? message.content,
            isMe: isMe,
          ),
        );

      case 'document':
      case 'file':
        return _buildDocBubble(ctx, isDark, textColor);

      default:
        return Text(
          message.content.isNotEmpty ? message.content : message.type,
          style: TextStyle(color: textColor, fontSize: 14.5),
        );
    }
  }

  Widget _buildImageBubble(BuildContext ctx, bool isDark) {
    String? cleanedPath;
    final bool isUploading = message.uploadStatus == MessageUploadStatus.uploading;
    bool isLocalUpload = false;
    if (message.localPath != null) {
      cleanedPath = cleanLocalPath(message.localPath!);
      isLocalUpload = File(cleanedPath).existsSync(); // Always prefer local file
    }

    return GestureDetector(
      onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => MediaGalleryScreen(
                    url: isLocalUpload ? cleanedPath! : (message.previewUrl ?? message.content),
                    originalUrl: isLocalUpload ? cleanedPath! : message.content,
                    type: 'image',
                    fileName: message.fileName,
                    senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                    userRole: userRole,
                  ),
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: isUploading
              ? Shimmer.fromColors(
                  key: const ValueKey('skeleton'),
                  baseColor: isDark ? const Color(0xFF202C33) : const Color(0xFFE0E0E0),
                  highlightColor: isDark ? const Color(0xFF2C3943) : const Color(0xFFF5F5F5),
                  child: Container(
                    width: _maxWidth,
                    height: 180,
                    color: Colors.white,
                  ),
                )
              : isLocalUpload
                  ? HighlyResilientImageWidget(
                      key: const ValueKey('local_image'),
                      path: cleanedPath!,
                      isLocal: true,
                      width: _maxWidth,
                      height: 180,
                      fit: BoxFit.cover,
                    )
                  : CachedNetworkImage(
                      key: const ValueKey('remote_image'),
                      imageUrl: AuthService().getFullUrl(
                              message.previewUrl ?? message.content) ??
                          (message.previewUrl ?? message.content),
                      width: _maxWidth,
                      height: 180,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: Colors.black12),
                      errorWidget: (_, _, _) => const Icon(Icons.broken_image),
                    ),
        ),
      ),
    );
  }

  Widget _buildVideoBubble(BuildContext ctx, bool isDark) {
    String? cleanedPath;
    final bool isUploading = message.uploadStatus == MessageUploadStatus.uploading;
    bool isLocalUpload = false;
    if (message.localPath != null) {
      cleanedPath = cleanLocalPath(message.localPath!);
      isLocalUpload = File(cleanedPath).existsSync(); // Always prefer local file
    }

    final previewUrl = message.previewUrl ?? '';
    final thumbUrl = previewUrl.isNotEmpty
        ? (AuthService().getFullUrl(previewUrl) ?? previewUrl)
        : '';

    return GestureDetector(
      onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => MediaGalleryScreen(
                    url: isLocalUpload ? cleanedPath! : (message.previewUrl ?? message.content),
                    originalUrl: isLocalUpload ? cleanedPath! : message.content,
                    type: 'video',
                    fileName: message.fileName,
                    senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                    userRole: userRole,
                  ),
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isLocalUpload
            ? LocalVideoThumbnailWidget(
                localVideoPath: cleanedPath!,
                width: _maxWidth,
                height: 180,
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  thumbUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: thumbUrl,
                          width: _maxWidth,
                          height: 180,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                              width: _maxWidth,
                              height: 180,
                              color: Colors.black26,
                              child: const Icon(Icons.videocam,
                                  color: Colors.white54, size: 48)))
                      : Container(
                          width: _maxWidth,
                          height: 180,
                          color: Colors.black26,
                          child: const Icon(Icons.videocam,
                              color: Colors.white54, size: 48)),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDocBubble(BuildContext ctx, bool isDark, Color textColor) {
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.blue;
    Color cardBg = Colors.grey.shade50;
    Color cardBorder = Colors.grey.shade200;
    Color badgeBg = Colors.grey.shade100;
    Color badgeText = Colors.grey.shade700;
    String ext = 'FILE';

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
      } else if (['ppt', 'pptx'].contains(ext)) {
        fileIcon = Icons.slideshow;
        iconColor = const Color(0xFFD84315);
        cardBg = const Color(0xFFFBE9E7);
        cardBorder = const Color(0xFFFFCCBC);
        badgeBg = const Color(0xFFFFCCBC);
        badgeText = const Color(0xFFD84315);
      } else {
        fileIcon = Icons.insert_drive_file;
        iconColor = const Color(0xFF3F51B5);
        cardBg = const Color(0xFFE8EAF6);
        cardBorder = const Color(0xFFC5CAE9);
        badgeBg = const Color(0xFFC5CAE9);
        badgeText = const Color(0xFF1A237E);
      }
    }

    if (isMe) {
      cardBg = Colors.white.withValues(alpha: 0.08);
      cardBorder = Colors.white.withValues(alpha: 0.12);
      badgeBg = Colors.white.withValues(alpha: 0.16);
      badgeText = Colors.white;
      iconColor = Colors.white;
    }

    String? cleanedDocPath;
    final bool isUploading = message.uploadStatus == MessageUploadStatus.uploading;
    bool isLocalDoc = false;
    if (message.localPath != null) {
      cleanedDocPath = cleanLocalPath(message.localPath!);
      isLocalDoc = File(cleanedDocPath).existsSync(); // Always prefer local file
    }

    if (ext == 'pdf' && (isLocalDoc || message.previewUrl != null)) {
      // Render beautiful split PDF card with Cover Page on top!
      return Container(
        width: _maxWidth,
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
              final isUploading = message.uploadStatus == MessageUploadStatus.uploading;
              final isError = message.uploadStatus == MessageUploadStatus.error;
              if (!isUploading && !isError && message.content.isNotEmpty) {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => MediaGalleryScreen(
                      url: isLocalDoc ? cleanedDocPath! : (message.previewUrl ?? message.content),
                      originalUrl: isLocalDoc ? cleanedDocPath! : message.content,
                      type: 'pdf',
                      fileName: message.fileName,
                      senderName: isMe ? 'You' : (message.senderName ?? 'Member'),
                      userRole: userRole,
                    ),
                  ),
                );
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top: Page 1 cover preview
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  child: SizedBox(
                    height: 140,
                    child: isLocalDoc
                        ? LocalPdfThumbnailWidget(localPath: cleanedDocPath!, width: _maxWidth, height: 140)
                        : CachedNetworkImage(
                            imageUrl: AuthService().getFullUrl(message.previewUrl!) ?? message.previewUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (c, e, s) => Container(
                              color: Colors.red.shade50,
                              child: const Center(
                                child: Icon(Icons.picture_as_pdf, size: 45, color: Color(0xFFE53935)),
                              ),
                            ),
                          ),
                  ),
                ),
                // Bottom: File details row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFE53935).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.picture_as_pdf, color: isMe ? Colors.white : const Color(0xFFE53935), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.fileName ?? 'Document.pdf',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.white : Colors.blueGrey.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'PDF • Tap to view',
                              style: TextStyle(
                                fontSize: 9,
                                color: isMe ? Colors.white.withOpacity(0.6) : Colors.blueGrey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.remove_red_eye_outlined,
                        color: isMe ? Colors.white.withValues(alpha: 0.5) : Colors.blueGrey.shade400,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Classic card
      return Container(
        width: _maxWidth,
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
              final isUploading = message.uploadStatus == MessageUploadStatus.uploading;
              final isError = message.uploadStatus == MessageUploadStatus.error;
              if (!isUploading && !isError && message.content.isNotEmpty) {
                final String extStr = message.fileName?.split('.').last.toLowerCase() ?? '';
                String type = 'document';
                if (extStr == 'pdf') type = 'pdf';
                
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => MediaGalleryScreen(
                      url: isLocalDoc ? cleanedDocPath! : (message.previewUrl ?? message.content),
                      originalUrl: isLocalDoc ? cleanedDocPath! : message.content,
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
                      color: isMe ? Colors.white.withValues(alpha: 0.15) : iconColor.withValues(alpha: 0.12),
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
                          message.fileName ?? 'Document',
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
                            Expanded(
                              child: Text(
                                'Tap to preview',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe ? Colors.white.withValues(alpha: 0.6) : Colors.blueGrey.shade400,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.remove_red_eye_outlined,
                    color: isMe ? Colors.white.withValues(alpha: 0.5) : Colors.blueGrey.shade400,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildProgressBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: message.uploadProgress,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
            color: const Color(0xFF00A884),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 2),
          Text(
            'Uploading ${(message.uploadProgress * 100).toInt()}%',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: () {
          if (message.localPath != null) {
            onUploadRetry(
                message.localPath!, message.caption ?? '', message.type, message.id);
          }
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, color: Colors.red, size: 14),
            SizedBox(width: 4),
            Text('Upload failed. Tap to retry.',
                style: TextStyle(color: Colors.red, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestamp(bool isDark, Color subColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _formatTime(message.createdAt),
            style: TextStyle(fontSize: 10, color: subColor),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.done_all,
              size: 16,
              color: message.isRead
                  ? const Color(0xFF34B7F1)
                  : subColor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AudioBubble — uses GlobalAudioPlayer singleton
// ─────────────────────────────────────────────────────────────────────────────

class _AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _AudioBubble({required this.url, required this.isMe});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final GlobalAudioPlayer _player = GlobalAudioPlayer();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _player.activeUrl == widget.url;
    final color = widget.isMe
        ? (isDark ? Colors.greenAccent : const Color(0xFF075E54))
        : (isDark ? Colors.white : Colors.black87);

    return ListenableBuilder(
      listenable: _player,
      builder: (_, _) {
        final isPlaying = isActive && _player.isPlaying;
        final pos = isActive ? _player.position : Duration.zero;
        final dur = isActive ? _player.duration : Duration.zero;
        final progress =
            (dur.inMilliseconds > 0 && isActive)
                ? pos.inMilliseconds / dur.inMilliseconds
                : 0.0;

        return Row(
          children: [
            GestureDetector(
              onTap: () => _player.play(widget.url),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00A884)),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: const Color(0xFF00A884),
                      inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                      thumbColor: const Color(0xFF00A884),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (v) {
                        if (dur.inMilliseconds > 0) {
                          _player.seek(Duration(
                              milliseconds: (v * dur.inMilliseconds).toInt()));
                        }
                      },
                    ),
                  ),
                  Text(
                    isActive ? '${_fmt(pos)} / ${_fmt(dur)}' : _fmt(dur),
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String cleanLocalPath(String path) {
  String decoded = Uri.decodeFull(path);
  if (decoded.startsWith('file://')) {
    decoded = decoded.replaceFirst('file://', '');
  } else if (decoded.startsWith('file:')) {
    decoded = decoded.replaceFirst('file:', '');
  }
  if (!decoded.startsWith('/')) {
    decoded = '/$decoded';
  }
  return decoded;
}

class LocalPdfThumbnailWidget extends StatefulWidget {
  final String localPath;
  final double width;
  final double height;
  
  static final Map<String, Uint8List> _thumbnailCache = {};

  const LocalPdfThumbnailWidget({
    super.key,
    required this.localPath,
    required this.width,
    required this.height,
  });

  @override
  State<LocalPdfThumbnailWidget> createState() => _LocalPdfThumbnailWidgetState();
}

class _LocalPdfThumbnailWidgetState extends State<LocalPdfThumbnailWidget> {
  Future<Uint8List?>? _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    if (LocalPdfThumbnailWidget._thumbnailCache.containsKey(widget.localPath)) {
      _thumbnailFuture = Future.value(LocalPdfThumbnailWidget._thumbnailCache[widget.localPath]);
    } else {
      _thumbnailFuture = _generateThumbnail();
    }
  }

  Future<Uint8List?> _generateThumbnail() async {
    try {
      final document = await PdfDocument.openFile(widget.localPath);
      final page = await document.getPage(1);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.jpeg,
      );
      await page.close();
      await document.close();
      if (pageImage?.bytes != null) {
        LocalPdfThumbnailWidget._thumbnailCache[widget.localPath] = pageImage!.bytes;
      }
      return pageImage?.bytes;
    } catch (e) {
      debugPrint('Error generating local PDF thumbnail: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedBytes = LocalPdfThumbnailWidget._thumbnailCache[widget.localPath];
    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        key: ValueKey(widget.localPath),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
          );
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.red.shade50,
          child: const Center(
            child: Icon(Icons.picture_as_pdf, size: 45, color: Color(0xFFE53935)),
          ),
        );
      },
    );
  }
}

class LocalVideoThumbnailWidget extends StatefulWidget {
  final String localVideoPath;
  final double width;
  final double height;

  static final Map<String, Uint8List> _thumbnailCache = {};

  const LocalVideoThumbnailWidget({
    super.key,
    required this.localVideoPath,
    required this.width,
    required this.height,
  });

  @override
  State<LocalVideoThumbnailWidget> createState() => _LocalVideoThumbnailWidgetState();
}

class _LocalVideoThumbnailWidgetState extends State<LocalVideoThumbnailWidget> {
  Future<Uint8List?>? _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    if (LocalVideoThumbnailWidget._thumbnailCache.containsKey(widget.localVideoPath)) {
      _thumbnailFuture = Future.value(LocalVideoThumbnailWidget._thumbnailCache[widget.localVideoPath]);
    } else {
      _thumbnailFuture = _generateThumbnail();
    }
  }

  Future<Uint8List?> _generateThumbnail() async {
    try {
      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: widget.localVideoPath,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 400,
        quality: 60,
      );
      if (thumbPath != null) {
        final bytes = await File(thumbPath).readAsBytes();
        LocalVideoThumbnailWidget._thumbnailCache[widget.localVideoPath] = bytes;
        return bytes;
      }
      return null;
    } catch (e) {
      debugPrint('Error generating local video thumbnail: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedBytes = LocalVideoThumbnailWidget._thumbnailCache[widget.localVideoPath];
    if (cachedBytes != null) {
      return Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          Image.memory(
            cachedBytes,
            key: ValueKey(widget.localVideoPath),
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
          ),
          const Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
        ],
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Image.memory(
                snapshot.data!,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
              ),
              const Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
            ],
          );
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.videocam, size: 50, color: Colors.grey),
          ),
        );
      },
    );
  }
}

class HighlyResilientImageWidget extends StatefulWidget {
  final String path;
  final bool isLocal;
  final double width;
  final double height;
  final BoxFit fit;

  static final Map<String, Uint8List> _localImageBytesCache = {};

  const HighlyResilientImageWidget({
    super.key,
    required this.path,
    required this.isLocal,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  State<HighlyResilientImageWidget> createState() => _HighlyResilientImageWidgetState();
}

class _HighlyResilientImageWidgetState extends State<HighlyResilientImageWidget> {
  Future<Uint8List?>? _localLoadFuture;

  @override
  void initState() {
    super.initState();
    if (widget.isLocal) {
      if (HighlyResilientImageWidget._localImageBytesCache.containsKey(widget.path)) {
        _localLoadFuture = Future.value(HighlyResilientImageWidget._localImageBytesCache[widget.path]);
      } else {
        _localLoadFuture = _readBytes();
      }
    }
  }

  Future<Uint8List?> _readBytes() async {
    try {
      final file = File(widget.path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        HighlyResilientImageWidget._localImageBytesCache[widget.path] = bytes;
        return bytes;
      }
      return null;
    } catch (e) {
      debugPrint('Error reading local image bytes: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocal) {
      final cachedBytes = HighlyResilientImageWidget._localImageBytesCache[widget.path];
      if (cachedBytes != null) {
        return Image.memory(
          cachedBytes,
          key: ValueKey('memory_${widget.path}'),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        );
      }

      return FutureBuilder<Uint8List?>(
        future: _localLoadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              key: ValueKey('memory_${widget.path}'),
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholder();
              },
            );
          }
          return _buildPlaceholder();
        },
      );
    } else {
      return CachedNetworkImage(
        imageUrl: widget.path,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (_, _) => _buildPlaceholder(),
        errorWidget: (_, _, _) => _buildPlaceholder(),
      );
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black.withOpacity(0.05),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: Color(0xFF00A884),
          ),
        ),
      ),
    );
  }
}
