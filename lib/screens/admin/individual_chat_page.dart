import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
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
  bool _isTyping = false;
  Timer? _typingTimer;

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

          final int existingIndex = _messages.indexWhere(
            (m) => m.id == message.id,
          );
          if (existingIndex == -1) {
            _messages.insert(0, message);
            debugPrint('✅ Message Displayed: ${message.content}');
          } else {
            debugPrint('♻️ Duplicate ignored: ${message.id}');
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

  void _sendMessage({String type = 'text', String? content}) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && type == 'text') return;

    if (type == 'text' && content == null) {
      // Quietly send
    }

    if (widget.receiverId != null) {
      if (type == 'text') _messageController.clear();
      setState(() {}); // Clear visibility

      try {
        _typingTimer?.cancel();
        _socketService.emit('typing:stop', {
          'conversationId': _activeConversationId,
          'receiverId': widget.receiverId,
        });

        _socketService.emit('message:send', {
          'conversationId': _activeConversationId, // Can be null for new chat
          'receiverId': widget.receiverId,
          'content': text,
          'type': type,
        });
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
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
                              GestureDetector(
                                onLongPress: isMe
                                    ? () => _deleteMessage(msg.id)
                                    : null,
                                child: _ChatBubble(message: msg, isMe: isMe),
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
                    child: Slider(
                      value: _previewPosition.inMilliseconds.toDouble(),
                      max: _previewDuration.inMilliseconds.toDouble() > 0
                          ? _previewDuration.inMilliseconds.toDouble()
                          : 1.0,
                      activeColor: const Color(0xFF1A73E8),
                      onChanged: (val) {
                        _previewPlayer.seek(Duration(milliseconds: val.toInt()));
                      },
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

  const _ChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bubbleMe = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final Color bubbleOther = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMessageContent(context, textColor),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey[600]),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done_all,
                    color: message.isRead ? const Color(0xFF34B7F1) : const Color(0xFF8696A0),
                    size: 16,
                  ),
                ],
              ],
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

  Widget _buildMessageContent(BuildContext context, Color textColor) {
    switch (message.type) {
      case 'image':
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            message.content,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
          ),
        );
      case 'audio':
        return _AudioPlayerWidget(url: message.content, isMe: isMe);
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
  const _AudioPlayerWidget({required this.url, required this.isMe});

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
