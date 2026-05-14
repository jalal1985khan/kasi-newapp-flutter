import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
import 'package:image_picker/image_picker.dart';
import 'chat_profile_screen.dart';
import '../special_widgets/call_overlay.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/chat_service.dart';
import '../../models/chat_message_model.dart';
import '../../services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class IndividualChatPage extends StatefulWidget {
  final String name;
  final String avatar;
  final String? conversationId;
  final String? receiverId;

  const IndividualChatPage({
    super.key,
    required this.name,
    required this.avatar,
    this.conversationId,
    this.receiverId,
  });

  @override
  State<IndividualChatPage> createState() => _IndividualChatPageState();
}

class _IndividualChatPageState extends State<IndividualChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();
  final AudioRecorder _audioRecorder = AudioRecorder();

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
  
  // Pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // New features
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
    // _socketService.off('message:receive');
    _socketService.off('typing:start');
    _socketService.off('typing:stop');
    // _socketService.off('user:online');
    // _socketService.off('user:offline');
    _socketService.off('user:status_response');
    // _socketService.off('message:read_receipt');
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _audioRecorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on(
      'message:receive',
      (data) => _handleIncomingMessage(data),
    );
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
      if (data['userId'] == widget.receiverId && mounted) {
        setState(() => _isOtherUserOnline = true);
      }
    });

    _socketService.on('user:offline', (data) {
      if (data['userId'] == widget.receiverId && mounted) {
        setState(() => _isOtherUserOnline = false);
      }
    });

    _socketService.on('user:status_response', (data) {
      if (data['userId'] == widget.receiverId && mounted) {
        setState(() => _isOtherUserOnline = data['isOnline'] ?? false);
      }
    });

    _socketService.on('message:reaction', (data) {
      if (data['conversationId'] == _activeConversationId && mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == data['messageId'] || m.id == data['_id']);
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
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == data['messageId']);
        });
      }
    });

    // Check initial online status
    if (widget.receiverId != null) {
      _socketService.emit('user:status', {'userId': widget.receiverId});
    }

    // Mark existing messages as read
    if (_activeConversationId != null) {
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

      debugPrint(
        '📬 Processing Message ID: ${message.id} | Content: ${message.content}',
      );

      bool isMatch = (message.conversationId == _activeConversationId);

      if (!isMatch && _activeConversationId == null) {
        bool isSentByMe =
            (message.senderId == _currentUserId &&
            message.receiverId == widget.receiverId);
        bool isReceivedByMe =
            (message.senderId == widget.receiverId &&
            message.receiverId == _currentUserId);
        isMatch = isSentByMe || isReceivedByMe;
      }

      if (isMatch) {
        setState(() {
          if (_activeConversationId == null) {
            _activeConversationId = message.conversationId;
            debugPrint('🎯 Conv ID Anchored: $_activeConversationId');
          }

          // 1. Check if this is a confirmation of an optimistic (temp) message
          final int tempIndex = _messages.indexWhere(
            (m) => m.id.startsWith('temp_') && m.content == message.content && m.senderId == message.senderId
          );

          // 2. Check if this message ID already exists (real message)
          final int existingIndex = _messages.indexWhere(
            (m) => m.id == message.id,
          );

          if (existingIndex != -1) {
            // Already have the real message, ignore
            debugPrint('♻️ Duplicate ignored: ${message.id}');
          } else if (tempIndex != -1) {
            // Replace temp message with real one, preserving reply content/forwarded status
            // in case the backend doesn't return them yet.
            _messages[tempIndex] = message.copyWith(
              replyToContent: message.replyToContent ?? _messages[tempIndex].replyToContent,
              replyToSenderName: message.replyToSenderName ?? _messages[tempIndex].replyToSenderName,
              isForwarded: message.isForwarded || _messages[tempIndex].isForwarded,
            );
            debugPrint('⚡ Temp message replaced with real ID: ${message.id}');
          } else {
            // New message, insert at top
            _messages.insert(0, message);
            debugPrint('✅ Message Displayed: ${message.content}');
          }
        });
        _socketService.emit('message:read', {
          'conversationId': _activeConversationId,
        });
      } else {
        debugPrint(
          '⚠️ Message mismatch for this chat. Active: $_activeConversationId, Msg: ${message.conversationId}',
        );
      }
    }
  }

  Future<void> _loadData() async {
    final user = await _authService.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];

    if (_activeConversationId != null) {
      try {
        final response = await _chatService.getMessages(_activeConversationId!);
        if (mounted) {
          setState(() {
            _messages = response.messages.reversed.toList();
            _hasMore = response.hasMore ?? false;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_activeConversationId == null || _messages.isEmpty || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final String oldestMessageId = _messages.last.id;
      final response = await _chatService.getMessages(_activeConversationId!, beforeId: oldestMessageId);
      
      if (mounted) {
        setState(() {
          _messages.addAll(response.messages.reversed.toList());
          _hasMore = response.hasMore ?? false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        debugPrint('Error loading more messages: $e');
      }
    }
  }

  void _sendMessage({String type = 'text', String? content}) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && type == 'text') return;

    // Capture reply context before clearing state
    String? replyToId = _replyingToMessage?.id;
    String? replyToContent;
    String? replyToSenderName;
    if (_replyingToMessage != null) {
      replyToSenderName = _replyingToMessage!.senderId == _currentUserId ? 'You' : widget.name;
      if (_replyingToMessage!.type == 'image') {
        replyToContent = 'Photo';
      } else if (_replyingToMessage!.type == 'audio') {
        replyToContent = 'Voice message';
      } else if (_replyingToMessage!.type == 'video') {
        replyToContent = 'Video';
      } else {
        replyToContent = _replyingToMessage!.content;
      }
    }

    if (widget.receiverId != null) {
      // Optimistic Update: Add message to list immediately
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final optimisticMsg = ChatMessage(
        id: tempId,
        conversationId: _activeConversationId ?? '',
        senderId: _currentUserId ?? '',
        receiverId: widget.receiverId!,
        content: text,
        type: type,
        isRead: false,
        deletedFor: [],
        createdAt: DateTime.now(),
        replyToContent: replyToContent,
        replyToSenderName: replyToSenderName,
      );

      setState(() {
        _messages.insert(0, optimisticMsg);
        if (type == 'text' && content == null) _messageController.clear();
        _replyingToMessage = null;
      });

      try {
        _typingTimer?.cancel();
        _socketService.emit('typing:stop', {
          'conversationId': _activeConversationId,
          'receiverId': widget.receiverId,
        });

        _socketService.emit('message:send', {
          'conversationId': _activeConversationId,
          'receiverId': widget.receiverId,
          'content': text,
          'type': type,
          'replyTo': replyToId,
          'replyToContent': replyToContent,
          'replyToSenderName': replyToSenderName,
          'isForwarded': false,
        });
      } catch (e) {
        // Handle failure: remove optimistic message
        setState(() {
          _messages.removeWhere((m) => m.id == tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
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
      try {
        _socketService.emit('message:delete', {
          'messageId': messageId,
          'conversationId': _activeConversationId,
          'receiverId': widget.receiverId,
        });
        
        // Persist to DB
        await _chatService.deleteMessage(messageId);
        
        // Immediate local UI update
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
        
        // Sockets update UI via handler, but we clear loading here
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _isLoading = false);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
    if (widget.conversationId == null &&
        _activeConversationId == null &&
        widget.receiverId == null)
      return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true, // Enable multiple files
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
                content: Text('Uploading file $current of $total...'),
                duration: const Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          final uploadRes = await _chatService.uploadMedia(path);
          if (uploadRes['success'] == true) {
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
          ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToMessage(String messageId) async {
    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      setState(() => _highlightedMessageId = messageId);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    } else {
      debugPrint('⚠️ Message context not found for ID: $messageId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waDarkBg = isDark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5);
    const Color waTeal = Color(0xFF00A884);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return AdminLayout(
      currentIndex: 3,
      titleWidget: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatProfileScreen(
                name: widget.name,
                avatar: widget.avatar,
                isOnline: _isOtherUserOnline,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF202C33),
                  child: widget.avatar.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child:
                              Image.network(widget.avatar, fit: BoxFit.cover),
                        )
                      : Text(
                          widget.name[0].toUpperCase(),
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black45),
                        ),
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
                        border: Border.all(color: waDarkBg, width: 2),
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
                  Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isTyping
                        ? 'typing...'
                        : (_isOtherUserOnline ? 'Online' : 'Offline'),
                    style: TextStyle(
                      color: _isTyping ? waTeal : subTextColor,
                      fontSize: 12,
                      fontWeight:
                          _isTyping ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111B21) : const Color(0xFFE5DDD5),
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      extraActions: [
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () {
            if (widget.receiverId != null) {
              CallOverlayManager.show(
                context,
                widget.name,
                widget.avatar,
                widget.receiverId!,
              );
            }
          },
        ),
        PopupMenuButton<String>(
          iconColor: Colors.white,
          onSelected: (value) {
            if (value == 'clear') {
              _clearChat();
            } else if (value == 'delete') {
              _deleteChat();
            }
          },
          itemBuilder: (context) {
            final bool isDarkPopup = Theme.of(context).brightness == Brightness.dark;
            final Color popupBg = isDarkPopup ? const Color(0xFF202C33) : Colors.white;
            final Color popupText = isDarkPopup ? Colors.white : Colors.black87;
            
            return [
              PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat', style: TextStyle(color: popupText)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete chat', style: const TextStyle(color: Colors.red)),
              ),
            ];
          },
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF202C33) : Colors.white,
        ),
      ],
      body: Stack(
        children: [
          // High-Performance WhatsApp Pattern Background
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
                    : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(10),
                        reverse: true,
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator(color: waTeal)),
                            );
                          }
                          final msg = _messages[index];
                          final isMe = msg.senderId == _currentUserId;
                          bool showDateSeparator = false;
                          if (index == _messages.length - 1) {
                            showDateSeparator = true;
                          } else {
                            final newerMsg = _messages[index + 1];
                            if (!_isSameDay(
                              msg.createdAt,
                              newerMsg.createdAt,
                            )) {
                              showDateSeparator = true;
                            }
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDateSeparator)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withAlpha(50),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _formatDate(msg.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Dismissible(
                                  key: _messageKeys[msg.id] ??= GlobalKey(),
                                  direction: DismissDirection.startToEnd,
                                  confirmDismiss: (direction) async {
                                    setState(() => _replyingToMessage = msg);
                                    return false; // Prevent actual dismissal
                                  },
                                  background: Container(
                                    padding: const EdgeInsets.only(left: 20),
                                    alignment: Alignment.centerLeft,
                                    child: const Icon(Icons.reply, color: Color(0xFF00A884)),
                                  ),
                                  child: _ChatBubble(
                                    message: msg,
                                    isMe: isMe,
                                    onLongPress: (m) => _showMessageOptions(m),
                                    isHighlighted: _highlightedMessageId == msg.id,
                                    onReplyTap: (replyToId) => _scrollToMessage(replyToId),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            if (_isTyping)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    Text(
                      '${widget.name} is typing...',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              _buildMessageInput(),
            ],
          ),
        ],
      ),
    );
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
        content: Text('Are you sure you want to clear all messages in this chat?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );

    if (confirmed == true) {
      // For individual chats, clearChat endpoint might be different or we need a service method
      // For now, let's assume we can clear via a service
      setState(() => _messages.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
    }
  }

  Future<void> _deleteChat() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Delete Chat', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to delete this chat?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      // Logic to delete conversation
      Navigator.pop(context);
    }
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
    const Color waTeal = Color(0xFF00A884);
    final Color inputBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingToMessage != null) _buildReplyPreview(),
          _showPreview
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B272E) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatDuration(_previewPosition),
                            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: _WaveformWidget(color: waTeal.withOpacity(0.5), count: 40),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatDuration(_previewDuration),
                            style: TextStyle(color: subTextColor, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 28),
                            color: Colors.grey,
                            onPressed: () {
                              _previewPlayer.stop();
                              setState(() {
                                _showPreview = false;
                                _audioPath = null;
                              });
                            },
                          ),
                          GestureDetector(
                            onTap: _togglePreviewPlay,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                                color: Colors.redAccent,
                                size: 32,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _sendRecordedVoice,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(color: waTeal, shape: BoxShape.circle),
                              child: const Icon(Icons.send, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
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
                    child: _isRecording
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                  child: _WaveformWidget(color: Colors.redAccent.withOpacity(0.6), count: 30),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                  onPressed: () {
                                    _recordTimer?.cancel();
                                    _audioRecorder.stop();
                                    setState(() => _isRecording = false);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 32),
                                  onPressed: _stopRecording,
                                ),
                              ],
                            ),
                          )
                        : Row(
                            children: [
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.attach_file, color: Color(0xFF8696A0)),
                                onPressed: _pickFiles,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: TextStyle(color: textColor),
                                  onChanged: (val) {
                                    setState(() {});
                                    if (val.isNotEmpty) {
                                      _socketService.emit('typing:start', {
                                        'conversationId': _activeConversationId,
                                        'receiverId': widget.receiverId,
                                      });
                                    }
                                    _typingTimer?.cancel();
                                    _typingTimer = Timer(
                                      const Duration(seconds: 2),
                                      () {
                                        _socketService.emit('typing:stop', {
                                          'conversationId': _activeConversationId,
                                          'receiverId': widget.receiverId,
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
                            ],
                          ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (_messageController.text.isNotEmpty) {
                      _sendMessage();
                    } else if (!_isRecording) {
                      _startRecording();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: waTeal, shape: BoxShape.circle),
                    child: Icon(
                      _messageController.text.isNotEmpty ? Icons.send : Icons.mic,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Old _pickFiles removed.

  bool _isSameDay(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1))))
      return 'Yesterday';
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  Widget _buildReplyPreview() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF1B272E) : const Color(0xFFF0F2F5);
    final Color barColor = const Color(0xFF53BDEB); // WhatsApp Blue for reply bar
    final Color nameColor = barColor;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: barColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replyingToMessage!.senderId == _currentUserId ? 'You' : widget.name,
                        style: TextStyle(color: nameColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      _buildReplyContentPreview(isDark),
                    ],
                  ),
                ),
              ),
              if (_replyingToMessage!.type == 'image')
                Container(
                  width: 45,
                  height: 45,
                  margin: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(_replyingToMessage!.content, fit: BoxFit.cover),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: Icon(Icons.cancel, size: 24, color: isDark ? Colors.white38 : Colors.grey[400]),
                  onPressed: () => setState(() => _replyingToMessage = null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyContentPreview(bool isDark) {
    final Color textColor = isDark ? Colors.white70 : Colors.black54;
    switch (_replyingToMessage!.type) {
      case 'image':
        return Row(
          children: [
            Icon(Icons.camera_alt, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text('Photo', style: TextStyle(color: textColor, fontSize: 14)),
          ],
        );
      case 'audio':
        return Row(
          children: [
            Icon(Icons.mic, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text('Voice message', style: TextStyle(color: textColor, fontSize: 14)),
          ],
        );
      case 'video':
        return Row(
          children: [
            Icon(Icons.videocam, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text('Video', style: TextStyle(color: textColor, fontSize: 14)),
          ],
        );
      default:
        return Text(
          _replyingToMessage!.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontSize: 14),
        );
    }
  }

  void _forwardMessage(ChatMessage message) async {
    final allPartners = await _chatService.getPartners();
    // Filter out the person who sent the message to prevent forwarding back to them
    final filteredPartners = allPartners.where((p) => (p['_id'] ?? p['id']) != widget.receiverId).toList();
    
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
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Search contacts...',
                          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF00A884)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (val) {
                          // Local filtering logic could go here
                        },
                      ),
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
            if (message.readAt != null) ...[
              const SizedBox(height: 8),
              Text('Read: ${DateFormat('hh:mm:ss a, MMM dd').format(message.readAt!.toLocal())}'),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
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
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
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
                      Icon(Icons.add, color: isDark ? Colors.white54 : Colors.grey),
                    ],
                  ),
                ),
                // Options Menu
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
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
    // Emit socket event for reaction
    _socketService.emit('message:reaction', {
      'messageId': message.id,
      'conversationId': message.conversationId,
      'emoji': emoji,
      'receiverId': widget.receiverId,
    });

    // Persist to DB
    await _chatService.updateMessageReaction(message.id, emoji);

    // Local feedback & Immediate UI update
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(reaction: emoji);
      }
    });

    // Local feedback toast
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You reacted with $emoji'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 200,
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
    final screenSize = MediaQuery.of(context).size;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(10),
        title: Text(fileName),
        content: SizedBox(
          width: screenSize.width * 0.95,
          height: screenSize.height * 0.95,
          child: _buildDialogContent(type, content, fileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogContent(String type, String content, String fileName) {
    String ext = content.split('.').last.split('?').first.toLowerCase();
    if (ext == 'mp4' || ext == 'mov' || ext == 'avi')
      return VideoPlayerWidget(url: content);
    switch (type) {
      case 'image':
        return InteractiveViewer(
          child: Image.network(
            content,
            errorBuilder: (c, e, s) =>
                const Center(child: Icon(Icons.broken_image, size: 50)),
          ),
        );
      case 'pdf':
      case 'document':
        return Center(child: Text(fileName)); // Simplified for now
      default:
        return Center(child: Text(content));
    }
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

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  const VideoPlayerWidget({super.key, required this.url});
  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted)
          setState(() {
            _initialized = true;
            _controller.play();
          });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const Center(child: CircularProgressIndicator());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
        IconButton(
          icon: Icon(
            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: () => setState(
            () => _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play(),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final Function(ChatMessage) onLongPress;
  final bool isHighlighted;
  final Function(String)? onReplyTap;

  const _ChatBubble({
    required this.message, 
    required this.isMe, 
    required this.onLongPress,
    this.isHighlighted = false,
    this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // WhatsApp Premium Colors - Adjusted for visibility
    final Color bubbleMe = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final Color bubbleOther = isDark ? const Color(0xFF262D31) : Colors.white;
    final Color highlightColor = isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : (Colors.grey[600] ?? Colors.grey);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: isHighlighted ? highlightColor : Colors.transparent,
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
    if (message.replyToContent == null) return const SizedBox.shrink();

    final Color barColor = const Color(0xFF53BDEB);
    final bool isPhoto = message.replyToContent == 'Photo';
    final bool isVoice = message.replyToContent == 'Voice message';
    final bool isVideo = message.replyToContent == 'Video';

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
                          message.replyToSenderName ?? 'You',
                          style: TextStyle(
                            color: barColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (isPhoto) Icon(Icons.camera_alt, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                            if (isVoice) Icon(Icons.mic, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                            if (isVideo) Icon(Icons.videocam, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                            if (isPhoto || isVoice || isVideo) const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                message.replyToContent!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
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

  Widget _buildMessageContent(BuildContext context, Color textColor) {
    switch (message.type) {
      case 'image':
        return Container(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              message.content,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
            ),
          ),
        );
      case 'audio':
        return _AudioPlayerWidget(url: message.content, isMe: isMe, initialDuration: message.duration);
      case 'document':
      case 'file':
      case 'video':
        IconData fileIcon = Icons.insert_drive_file;
        Color iconColor = Colors.blue;

        if (message.fileName != null) {
          final ext = message.fileName!.split('.').last.toLowerCase();
          if (['pdf'].contains(ext)) {
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

        return GestureDetector(
          onTap: () => _openFile(
            context,
            message.content,
            message.fileName ?? 'Attachment',
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fileIcon, color: iconColor),
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
      default:
        return Text(message.content, style: TextStyle(fontSize: 16, color: textColor));
    }
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

class _WaveformWidget extends StatefulWidget {
  final Color color;
  final int count;
  const _WaveformWidget({required this.color, this.count = 25});

  @override
  State<_WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<_WaveformWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 30),
          painter: _WaveformPainter(
            color: widget.color,
            animationValue: _controller.value,
            count: widget.count,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Color color;
  final double animationValue;
  final int count;
  _WaveformPainter({required this.color, required this.animationValue, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double spacing = size.width / count;

    for (int i = 0; i < count; i++) {
      // Simple pseudo-random heights that animate
      double h = (0.2 + 0.8 * (math.sin(i * 0.5 + animationValue * 10).abs())) * size.height;
      double x = i * spacing + spacing / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
