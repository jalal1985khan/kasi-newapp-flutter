import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:path/path.dart' as p;
import 'attachment_preview_screen.dart';
import 'media_gallery_screen.dart';
import 'common_widgets/user_layout.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/chat_service.dart';
import '../../services/auth_service.dart';
import '../../models/chat_message_model.dart';
import '../special_widgets/call_overlay.dart';
import '../../utils/premium_widgets.dart';

class IndividualChatScreen extends StatefulWidget {
  final String conversationId;
  final String name;
  final String? avatar;
  final String otherUserId;

  const IndividualChatScreen({
    super.key,
    required this.conversationId,
    required this.name,
    this.avatar,
    required this.otherUserId,
  });

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _activeConversationId;
  bool _isOtherUserOnline = false;
  ChatMessage? _replyingToMessage;
  final Set<String> _starredMessages = {};
  bool _isTyping = false;
  Timer? _typingTimer;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  String? _userRole;
  
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;
  StreamSubscription? _socketSubscription;

  // Audio Features
  bool _isRecording = false;
  double _recordDuration = 0;
  Timer? _recordTimer;
  bool _showPreview = false;
  String? _audioPath;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _activeConversationId = widget.conversationId;
    _loadData();
    _setupSocket();
    _socketSubscription = _socketService.connectionStatus.listen((connected) {
      if (connected && mounted) {
        _socketService.emit('user:status', {'userId': widget.otherUserId});
      }
    });
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore && _hasMore) {
      _loadMoreMessages();
    }
  }

  void _setupSocket() {
    _socketService.connect();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _socketService.off('typing:start');
    _socketService.off('typing:stop');
    _socketService.off('user:status_response');
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _audioRecorder.dispose();
    _scrollController.dispose();
    _previewPlayer.dispose();
    _socketSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on('message:receive', (data) => _handleIncomingMessage(data));
    _socketService.on('message:sent', (data) => _handleIncomingMessage(data));

    _socketService.on('typing:start', (data) {
      if (data['conversationId'] == _activeConversationId && mounted) {
        setState(() => _isTyping = true);
      }
    });

    _socketService.on('typing:stop', (data) {
      if (data['conversationId'] == _activeConversationId && mounted) {
        setState(() => _isTyping = false);
      }
    });

    _socketService.on('user:online', (data) {
      debugPrint('🟢 Socket: user:online received for ${data['userId']}');
      if (data['userId'].toString() == widget.otherUserId.toString() && mounted) {
        setState(() => _isOtherUserOnline = true);
      }
    });

    _socketService.on('user:offline', (data) {
      debugPrint('🔴 Socket: user:offline received for ${data['userId']}');
      if (data['userId'].toString() == widget.otherUserId.toString() && mounted) {
        setState(() => _isOtherUserOnline = false);
      }
    });

    _socketService.on('user:status_response', (data) {
      if (data['userId'].toString() == widget.otherUserId.toString() && mounted) {
        setState(() => _isOtherUserOnline = data['isOnline'] ?? false);
      }
    });

    _socketService.on('message:reaction', (data) {
      if (data['conversationId'] == _activeConversationId && mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == data['messageId']);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(reaction: data['emoji']);
          }
        });
      }
    });

    _socketService.on('message:read_receipt', (data) {
      if (data['conversationId'] == _activeConversationId && mounted) {
        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            if (_messages[i].senderId == _currentUserId) {
              _messages[i] = _messages[i].copyWith(isRead: true);
            }
          }
        });
      }
    });

    _socketService.on('message:deleted', (data) {
      debugPrint('🗑️ Socket: message:deleted received: ${data['messageId']}');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id.toString() == data['messageId'].toString());
        });
      }
    });

    _socketService.on('message:update', (data) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == data['messageId']);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(content: data['content']);
          }
        });
      }
    });

    _socketService.emit('user:status', {'userId': widget.otherUserId});

    if (_activeConversationId != null) {
      _socketService.emit('chat:join', {
        'conversationId': _activeConversationId,
      });
      _socketService.emit('message:read', {
        'conversationId': _activeConversationId,
      });
    }
  }

  void _handleIncomingMessage(dynamic data) {
    if (mounted) {
      final message = ChatMessage.fromJson({
        ...data,
        'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
      });

      bool isMatch = (message.conversationId == _activeConversationId);

      if (!isMatch && _activeConversationId == null) {
        bool isSentByMe = (message.senderId == _currentUserId && message.receiverId == widget.otherUserId);
        bool isReceivedByMe = (message.senderId == widget.otherUserId && message.receiverId == _currentUserId);
        isMatch = isSentByMe || isReceivedByMe;
      }

      if (isMatch) {
        setState(() {
          if (_activeConversationId == null) {
            _activeConversationId = message.conversationId;
            _socketService.emit('chat:join', {'conversationId': _activeConversationId});
          }

          final int tempIndex = _messages.indexWhere((m) {
            final incomingTempId = data['tempId'];
            if (incomingTempId != null && m.id == incomingTempId) return true;
            return m.id.startsWith('temp_') && 
                   m.content == message.content && 
                   m.senderId == message.senderId &&
                   m.type == message.type;
          });

          final int existingIndex = _messages.indexWhere((m) => m.id == message.id);

          if (existingIndex != -1) {
            // Ignore duplicate
          } else if (tempIndex != -1) {
            _messages[tempIndex] = message.copyWith(
              replyToContent: message.replyToContent ?? _messages[tempIndex].replyToContent,
              replyToSenderName: message.replyToSenderName ?? _messages[tempIndex].replyToSenderName,
              isForwarded: message.isForwarded || _messages[tempIndex].isForwarded,
              caption: message.caption ?? _messages[tempIndex].caption,
            );
          } else {
            _messages.insert(0, message);
          }
        });
        _socketService.emit('message:read', {'conversationId': _activeConversationId});
      }
    }
  }

  Future<void> _loadData() async {
    final user = await _authService.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];
    _userRole = user?['role'];

    if (_activeConversationId != null) {
      try {
        final response = await _chatService.getMessages(_activeConversationId!);
        if (mounted) {
          setState(() {
            _messages = response.messages.reversed.toList();
            _hasMore = response.hasMore;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_activeConversationId == null || _messages.isEmpty || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final response = await _chatService.getMessages(_activeConversationId!, beforeId: _messages.last.id);
      if (mounted) {
        setState(() {
          _messages.addAll(response.messages.reversed.toList());
          _hasMore = response.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
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
  }) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && type == 'text' && localPath == null) return;

    String? replyToId = _replyingToMessage?.id;
    String? replyToContent;
    String? replyToSenderName;
    if (_replyingToMessage != null) {
      replyToSenderName = _replyingToMessage!.senderId == _currentUserId ? 'You' : widget.name;
      replyToContent = _replyingToMessage!.type == 'image' ? 'Photo' 
                     : _replyingToMessage!.type == 'audio' ? 'Voice message' 
                     : _replyingToMessage!.type == 'video' ? 'Video' 
                     : _replyingToMessage!.content;
    }

    final tempId = existingTempId ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create or Update optimistic message
    final optimisticMsg = ChatMessage(
      id: tempId,
      conversationId: _activeConversationId ?? '',
      senderId: _currentUserId ?? '',
      receiverId: widget.otherUserId,
      content: text,
      type: type,
      isRead: false,
      deletedFor: [],
      createdAt: DateTime.now(),
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      caption: caption,
      fileName: fileName,
      localPath: localPath,
      uploadStatus: uploadStatus,
      uploadProgress: uploadProgress,
    );

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        _messages[idx] = optimisticMsg;
      } else {
        _messages.insert(0, optimisticMsg);
      }
      if (type == 'text' && content == null) _messageController.clear();
      _replyingToMessage = null;
    });

    // If still uploading, don't emit to socket yet
    if (uploadStatus == MessageUploadStatus.uploading || uploadStatus == MessageUploadStatus.error) {
      return;
    }

    try {
      _typingTimer?.cancel();
      _socketService.emit('typing:stop', {
        'conversationId': _activeConversationId,
        'receiverId': widget.otherUserId,
      });

      _socketService.emit('message:send', {
        'conversationId': _activeConversationId,
        'receiverId': widget.otherUserId,
        'content': text,
        'type': type,
        'replyTo': replyToId,
        'replyToContent': replyToContent,
        'replyToSenderName': replyToSenderName,
        'isForwarded': false,
        'caption': caption,
        'fileName': fileName,
        'tempId': tempId,
      });
    } catch (e) {
      if (existingTempId == null) {
        setState(() => _messages.removeWhere((m) => m.id == tempId));
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  Future<void> _uploadAndSend(String path, String caption, String type, String tempId) async {
    try {
      final uploadRes = await _chatService.uploadMedia(
        path,
        onSendProgress: (sent, total) {
          if (mounted) {
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == tempId);
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(
                  uploadProgress: sent / total,
                );
              }
            });
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
        _setUploadError(tempId);
      }
    } catch (e) {
      _setUploadError(tempId);
    }
  }

  void _setUploadError(String tempId) {
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            uploadStatus: MessageUploadStatus.error,
          );
        }
      });
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        _socketService.emit('message:delete', {
          'messageId': messageId,
          'conversationId': _activeConversationId,
          'receiverId': widget.otherUserId,
        });
        await _chatService.deleteMessage(messageId);
        setState(() => _messages.removeWhere((m) => m.id == messageId));
      } catch (e) {
        debugPrint('Delete error: $e');
      }
    }
  }

  void _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
      setState(() => _isRecording = false);
    }
  }

  void _setupPreviewPlayer() async {
    if (_audioPath == null) return;
    await _previewPlayer.setSourceDeviceFile(_audioPath!);
    _previewPlayer.onDurationChanged.listen((d) => setState(() => _previewDuration = d));
    _previewPlayer.onPositionChanged.listen((p) => setState(() => _previewPosition = p));
    _previewPlayer.onPlayerComplete.listen((_) => setState(() => _isPlayingPreview = false));
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _audioPath = null;
    }
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.paths.isNotEmpty) {
      final List<String> paths = result.paths.whereType<String>().toList();
      
      if (!mounted) return;
      final previewResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttachmentPreviewScreen(filePaths: paths, userName: widget.name),
        ),
      );

      if (previewResult != null && previewResult is List) {
        for (final item in previewResult) {
          final path = item['path'];
          final caption = item['caption'];
          if (path == null) continue;
          
          final tempId = 'temp_upload_${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}';
          final ext = p.extension(path).toLowerCase();
          String type = 'document';
          if (['.jpg', '.jpeg', '.png', '.gif'].contains(ext)) type = 'image';
          if (['.mp4', '.mov', '.avi'].contains(ext)) type = 'video';
          if (['.mp3', '.m4a', '.wav'].contains(ext)) type = 'audio';

          // Send optimistic message immediately with uploading status
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

          // Start background upload
          _uploadAndSend(path, caption, type, tempId);
        }
      }
    }
  }

  void _scrollToMessage(String messageId) async {
    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(key!.currentContext!, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      setState(() => _highlightedMessageId = messageId);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waDarkBg = isDark ? const Color(0xFF0B141B) : const Color(0xFFE5DDD5);
    const Color waTeal = Color(0xFF00A884);
    final Color subTextColor = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;

    return UserLayout(
      currentIndex: 1,
      titleWidget: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isDark ? const Color(0xFF202C33) : Colors.white24,
                child: widget.avatar != null && widget.avatar!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(widget.avatar!, fit: BoxFit.cover),
                      )
                    : Text(widget.name[0].toUpperCase(), style: const TextStyle(color: Colors.white70)),
              ),
              if (_isOtherUserOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? const Color(0xFF202C33) : waTeal, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                Text(
                  _isTyping ? 'typing...' : (_isOtherUserOnline ? 'Online' : 'Offline'),
                  style: TextStyle(color: _isTyping ? const Color(0xFF25D366) : Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5),
      foregroundColor: Colors.white,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      extraActions: [
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () => CallOverlayManager.show(context, widget.name, widget.avatar ?? '', widget.otherUserId),
        ),
      ],
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              isDark 
                ? 'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/light-bg-theme.png'
                : 'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/transparent-bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: isDark ? const Color(0xFF0B141B) : const Color(0xFFE5DDD5)),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: (_isLoading && _messages.isEmpty)
                    ? _buildSkeletonLoading()
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.all(10),
                        reverse: true,
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: waTeal)));
                          }
                          final msg = _messages[index];
                          final isMe = msg.senderId == _currentUserId;
                          bool showDateSeparator = false;
                          if (index == _messages.length - 1) {
                            showDateSeparator = true;
                          } else if (!_isSameDay(msg.createdAt, _messages[index + 1].createdAt)) {
                            showDateSeparator = true;
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDateSeparator) _buildDateSeparator(msg.createdAt),
                              Dismissible(
                                key: ValueKey('dismiss_${msg.id}'),
                                direction: DismissDirection.startToEnd,
                                confirmDismiss: (_) async {
                                  setState(() => _replyingToMessage = msg);
                                  return false;
                                },
                                background: Container(padding: const EdgeInsets.only(left: 20), alignment: Alignment.centerLeft, child: const Icon(Icons.reply, color: waTeal)),
                                child: _ChatBubble(
                                  key: _messageKeys[msg.id] ??= GlobalKey(),
                                  message: msg,
                                  isMe: isMe,
                                  onLongPress: _showMessageOptions,
                                  userName: widget.name,
                                  isHighlighted: _highlightedMessageId == msg.id,
                                  onReplyTap: _scrollToMessage,
                                  onUploadRetry: _uploadAndSend,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              _buildMessageInput(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
        child: Text(_formatDate(date), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
      ),
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
        itemBuilder: (context, index) => Align(
          alignment: index % 2 == 0 ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 150 + (index * 15.0) % 100, height: 60, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waTeal = Color(0xFF00A884);
    final Color inputBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingToMessage != null) _buildReplyPreview(),
          _showPreview
              ? _buildVoicePreview(isDark, waTeal, textColor)
              : Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: inputBg, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
                        child: _isRecording ? _buildRecordingUI(textColor) : _buildTextInput(textColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SoftTouchWrapper(
                      onTap: () {
                        if (_messageController.text.isNotEmpty) {
                          _sendMessage();
                        } else if (!_isRecording) {
                          _startRecording();
                        } else {
                          _stopRecording();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: waTeal, shape: BoxShape.circle),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            _messageController.text.isNotEmpty ? Icons.send : (_isRecording ? Icons.stop : Icons.mic),
                            key: ValueKey(_messageController.text.isNotEmpty ? 'send' : (_isRecording ? 'stop' : 'mic')),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildTextInput(Color textColor) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.attach_file, color: Color(0xFF8696A0)),
          onPressed: _pickFiles,
        ),
        Expanded(
          child: TextField(
            controller: _messageController,
            focusNode: _focusNode,
            autofocus: false,
            style: TextStyle(color: textColor),
            onTap: () {
              if (!_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
            },
            onChanged: (val) {
              setState(() {});
              _socketService.emit(val.isNotEmpty ? 'typing:start' : 'typing:stop', {
                'conversationId': _activeConversationId,
                'receiverId': widget.otherUserId
              });
            },
            decoration: const InputDecoration(
              hintText: 'Type a message...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _BlinkingMicIcon(),
          const SizedBox(width: 12),
          Text(
            '${_recordDuration.toInt()}s',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(20, (i) => Container(
                width: 2,
                height: 10 + (math.Random().nextInt(20).toDouble()),
                color: Colors.redAccent.withOpacity(0.4),
              )),
            ),
          ),
          const Text('Slide to cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildVoicePreview(bool isDark, Color waTeal, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1B272E) : Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => _showPreview = false)),
          IconButton(icon: Icon(_isPlayingPreview ? Icons.pause : Icons.play_arrow), onPressed: _togglePreviewPlay),
          Expanded(child: Text('Voice message', style: TextStyle(color: textColor))),
          IconButton(icon: Icon(Icons.send, color: waTeal), onPressed: _sendRecordedVoice),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.black12, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Color(0xFF53BDEB), width: 4))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_replyingToMessage!.senderId == _currentUserId ? 'You' : widget.name, style: const TextStyle(color: Color(0xFF53BDEB), fontWeight: FontWeight.bold, fontSize: 12)),
                Text(_replyingToMessage!.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _replyingToMessage = null)),
        ],
      ),
    );
  }

  void _showMessageOptions(ChatMessage message) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF232D36) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reaction Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildReactionItem(message, '👍'),
                      _buildReactionItem(message, '❤️'),
                      _buildReactionItem(message, '😂'),
                      _buildReactionItem(message, '😮'),
                      _buildReactionItem(message, '😢'),
                      _buildReactionItem(message, '🙏'),
                    ],
                  ),
                ),
                // Options Menu
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      _buildOptionItem(context, 'Reply', Icons.reply, () {
                        Navigator.pop(context);
                        setState(() => _replyingToMessage = message);
                      }),
                      _buildOptionItem(context, 'Forward', Icons.forward, () {
                        Navigator.pop(context);
                        _forwardMessage(message);
                      }),
                      _buildOptionItem(context, 'Copy', Icons.copy, () {
                        Clipboard.setData(ClipboardData(text: message.content));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message copied to clipboard')),
                        );
                      }),
                      _buildOptionItem(context, 'Info', Icons.info_outline, () {
                        Navigator.pop(context);
                        _showMessageInfo(message);
                      }),
                      _buildOptionItem(context, 'Star', _starredMessages.contains(message.id) ? Icons.star : Icons.star_border, () {
                        Navigator.pop(context);
                        setState(() {
                          if (_starredMessages.contains(message.id)) {
                            _starredMessages.remove(message.id);
                          } else {
                            _starredMessages.add(message.id);
                          }
                        });
                      }),
                      const Divider(height: 1),
                      _buildOptionItem(context, 'Delete', Icons.delete_outline, () {
                        Navigator.pop(context);
                        _deleteMessage(message.id);
                      }, isDestructive: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReactionItem(ChatMessage message, String emoji) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _sendReaction(message, emoji);
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  void _sendReaction(ChatMessage message, String emoji) async {
    _socketService.emit('message:reaction', {
      'messageId': message.id,
      'conversationId': message.conversationId,
      'emoji': emoji,
      'receiverId': widget.otherUserId,
    });

    await _chatService.updateMessageReaction(message.id, emoji);

    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(reaction: emoji);
      }
    });
  }

  void _forwardMessage(ChatMessage message) async {
    final allPartners = await _chatService.getPartners();
    final filteredPartners = allPartners.where((p) => (p['_id'] ?? p['id']) != widget.otherUserId).toList();
    
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
                      itemCount: filteredPartners.length,
                      itemBuilder: (context, index) {
                        final partner = filteredPartners[index];
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
                            final convId = await _chatService.startConversation(partner['_id'] ?? partner['id']);
                            if (convId != null) {
                              _socketService.emit('message:send', {
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

  Widget _buildOptionItem(BuildContext context, String title, IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color = isDestructive ? Colors.redAccent : (isDark ? Colors.white : Colors.black87);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: color, fontSize: 16)),
            Icon(icon, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  void _showContentDialog(String type, String content, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileName),
        content: _buildDialogContent(type, content, fileName),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildDialogContent(String type, String content, String fileName) {
    if (type == 'image') {
      return InteractiveViewer(child: Image.network(content));
    }
    return Center(child: Text(content));
  }


  bool _isSameDay(DateTime d1, DateTime d2) => d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMM dd, yyyy').format(date);
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final Function(ChatMessage) onLongPress;
  final bool isHighlighted;
  final Function(String)? onReplyTap;
  final Function(String, String, String, String)? onUploadRetry;
  final String userName;
  final String? userRole;

  const _ChatBubble({
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
    final Color bubbleMe = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final Color bubbleOther = isDark ? const Color(0xFF262D31) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.grey;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: isHighlighted ? (isDark ? Colors.white12 : Colors.black12) : Colors.transparent,
      child: GestureDetector(
        onLongPress: () => onLongPress(message),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                  if (message.isForwarded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forward, size: 12, color: subTextColor),
                          const SizedBox(width: 4),
                          Text('Forwarded', style: TextStyle(fontSize: 11, color: subTextColor, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  if (message.replyToContent != null)
                    _buildReplyContext(isDark),
                  _buildMessageContent(context, textColor),
                  if (message.reaction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(message.reaction!, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(width: 20), // Minimum space between text and meta
                      Text(
                        DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                        style: TextStyle(fontSize: 10, color: subTextColor),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all,
                          color: message.isRead ? const Color(0xFF34B7F1) : subTextColor,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyContext(bool isDark) {
    final Color barColor = const Color(0xFF53BDEB);
    final bool isPhoto = message.replyToContent == 'Photo';
    final bool isVoice = message.replyToContent == 'Voice message';
    final bool isVideo = message.replyToContent == 'Video';

    return GestureDetector(
      onTap: () => onReplyTap?.call(message.replyTo ?? ""),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: barColor, width: 4)),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.replyToSenderName ?? '',
                  style: TextStyle(color: barColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (isPhoto) const Icon(Icons.camera_alt, size: 14, color: Colors.grey),
                    if (isVoice) const Icon(Icons.mic, size: 14, color: Colors.grey),
                    if (isVideo) const Icon(Icons.videocam, size: 14, color: Colors.grey),
                    if (isPhoto || isVoice || isVideo) const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        message.replyToContent ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, Color textColor) {
    Widget media;
    final isUploading = message.uploadStatus == MessageUploadStatus.uploading;
    final isError = message.uploadStatus == MessageUploadStatus.error;
    const double standardWidth = 250.0;

    switch (message.type) {
      case 'image':
        Widget img;
        if (message.localPath != null && (message.content.isEmpty || !message.content.startsWith('http'))) {
          img = Image.file(File(message.localPath!), width: standardWidth, height: 200, fit: BoxFit.cover);
        } else {
          img = Image.network(message.content, width: standardWidth, height: 200, fit: BoxFit.cover);
        }
        media = GestureDetector(
          onTap: () {
            if (!isUploading && !isError) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaGalleryScreen(
                    url: message.content,
                    type: 'image',
                    fileName: message.fileName,
                    senderName: isMe ? 'You' : (message.senderName ?? userName),
                    userRole: userRole,
                  ),
                ),
              );
            }
          },
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: img),
        );
        break;
      case 'audio':
        media = SizedBox(width: standardWidth, child: _AudioBubblePlayer(url: message.content, isMe: isMe));
        break;
      case 'video':
        media = GestureDetector(
          onTap: () {
            if (!isUploading && !isError) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaGalleryScreen(
                    url: message.content,
                    type: 'video',
                    fileName: message.fileName,
                    senderName: isMe ? 'You' : (message.senderName ?? userName),
                    userRole: userRole,
                  ),
                ),
              );
            }
          },
          child: Container(
            width: standardWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(message.fileName ?? 'Video', style: TextStyle(color: textColor, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        );
        break;
      case 'document':
      case 'file':
        media = Container(
          width: standardWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(message.fileName ?? 'File Attachment', style: TextStyle(color: textColor, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
        break;
      default:
        media = Text(message.content, style: TextStyle(color: textColor, fontSize: 16));
    }

    if (isUploading || isError) {
      media = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0.7, child: media),
          if (isUploading)
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                value: message.uploadProgress,
                strokeWidth: 3,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          if (isError)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 30),
              onPressed: () {
                if (message.localPath != null && onUploadRetry != null) {
                  // Restart upload
                  onUploadRetry!(message.localPath!, message.caption ?? '', message.type, message.id);
                }
              },
            ),
        ],
      );
    }

    if (message.caption != null && message.caption!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          media,
          const SizedBox(height: 6),
          Text(message.caption!, style: TextStyle(color: textColor, fontSize: 14)),
        ],
      );
    }
    return media;
  }
}

class _AudioBubblePlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  const _AudioBubblePlayer({required this.url, required this.isMe});

  @override
  State<_AudioBubblePlayer> createState() => _AudioBubblePlayerState();
}

class _AudioBubblePlayerState extends State<_AudioBubblePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
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
    final Color primaryColor = widget.isMe ? (isDark ? const Color(0xFF25D366) : Colors.green[800]!) : Colors.blue;

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
                    value: _position.inMilliseconds.toDouble(),
                    max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
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
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey[600]),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey[600]),
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

class _BlinkingMicIcon extends StatefulWidget {
  @override
  _BlinkingMicIconState createState() => _BlinkingMicIconState();
}

class _BlinkingMicIconState extends State<_BlinkingMicIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Icon(Icons.mic, color: Colors.redAccent, size: 24),
    );
  }
}

