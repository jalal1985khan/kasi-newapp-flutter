import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
import 'common_widgets/user_layout.dart';
import 'package:intl/intl.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/chat_service.dart';
import '../../services/auth_service.dart';
import '../../models/chat_message_model.dart';
import 'package:shimmer/shimmer.dart';
import '../special_widgets/call_overlay.dart';

class IndividualChatScreen extends StatefulWidget {
  final String conversationId; // Needed for real-time
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
  final ScrollController _scrollController = ScrollController();
  final SocketService _socketService = SocketService();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isRecording = false;
  bool _showPreview = false;
  String? _audioPath;
  double _recordDuration = 0;
  Timer? _recordTimer;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isOtherUserOnline = false; // New Presence State
  String? _currentUserId;
  String? _activeConversationId;
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: IndividualChatScreen Loaded with WhatsApp UI V2');
    _activeConversationId = widget.conversationId;
    _loadData();
    _setupSocket();
    _socketSubscription = _socketService.connectionStatus.listen((connected) {
      if (connected && mounted && widget.otherUserId != null) {
        debugPrint('📡 [User Indiv Chat] Socket reconnected, checking status...');
        _socketService.emit('user:status', {'userId': widget.otherUserId});
      }
    });
  }

  @override
  void dispose() {
    _socketService.off('message:receive');
    _socketService.off('message:sent');
    _socketService.off('typing:start');
    _socketService.off('typing:stop');
    _socketService.off('user:online');
    _socketService.off('user:offline');
    _socketService.off('user:status_response');
    _socketService.off('message:read_receipt');
    _socketService.off('message:deleted');
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _setupSocket() {
    _socketService.connect();
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

    // Real Presence Listeners
    _socketService.on('user:online', (data) {
      if (data['userId'] == widget.otherUserId && mounted) {
        setState(() => _isOtherUserOnline = true);
      }
    });

    _socketService.on('user:offline', (data) {
      if (data['userId'] == widget.otherUserId && mounted) {
        setState(() => _isOtherUserOnline = false);
      }
    });

    _socketService.on('user:status_response', (data) {
      if (data['userId'] == widget.otherUserId && mounted) {
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

    // Initial Status Check
    _socketService.emit('user:status', {'userId': widget.otherUserId});

    // Mark as read immediately
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

      bool isMatch = (message.conversationId == _activeConversationId);
      
      // Fallback: check by sender/receiver if conversationId doesn't match or is null
      if (!isMatch) {
        bool isSentByMe =
            (message.senderId == _currentUserId &&
            message.receiverId == widget.otherUserId);
        bool isReceivedByMe =
            (message.senderId == widget.otherUserId &&
            message.receiverId == _currentUserId);
        isMatch = isSentByMe || isReceivedByMe;
      }

      debugPrint('Incoming message match: $isMatch (ID: ${message.id}, Type: ${message.type})');

      if (isMatch) {
        setState(() {
          if (_activeConversationId == null)
            _activeConversationId = message.conversationId;
          final int existingIndex = _messages.indexWhere(
            (m) => m.id == message.id,
          );
          if (existingIndex == -1) {
            _messages.insert(0, message); // Key for reverse:true
          }
        });
        // Emit read if we are looking at this chat
        _socketService.emit('message:read', {
          'conversationId': _activeConversationId,
        });
      }
    }
  }

  Future<void> _loadData() async {
    final response = await _chatService.getMessages(widget.conversationId);
    final user = await _authService.getUser();

    if (mounted) {
      setState(() {
        _currentUserId = user?['id'] ?? user?['_id'];
        // REVERSE maps oldest-to-newest into newest-at-bottom because of ListView(reverse:true)
        _messages = response.messages.reversed.toList();
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    _typingTimer?.cancel();
    _socketService.emit('typing:stop', {
      'conversationId': _activeConversationId ?? widget.conversationId,
      'receiverId': widget.otherUserId,
    });

    // Emit via socket
    _socketService.emit('message:send', {
      'conversationId': _activeConversationId ?? widget.conversationId,
      'receiverId': widget.otherUserId,
      'type': 'text',
      'content': text,
    });
    setState(() {}); // Clear visibility
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
          'conversationId': _activeConversationId ?? widget.conversationId,
          'receiverId': widget.otherUserId,
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

  Future<void> _pickAndUploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true, // Enable multiple files
      );

      if (result != null && result.paths.isNotEmpty) {
        final total = result.paths.length;
        int current = 0;

        setState(() => _isLoading = true);

        for (final path in result.paths) {
          if (path == null) continue;
          current++;

          if (path == null) continue;
          current++;

          final uploadResult = await _chatService.uploadMedia(path);

          if (uploadResult['success']) {
            _socketService.emit('message:send', {
              'conversationId': _activeConversationId ?? widget.conversationId,
              'receiverId': widget.otherUserId,
              'type': uploadResult['type'],
              'content': uploadResult['url'],
              'fileName': uploadResult['fileName'],
              'fileSize': uploadResult['fileSize'],
            });
          }
        }

        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _showPreview = false;
          _audioPath = path;
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

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        if (path != null) {
          _audioPath = path;
          _showPreview = true;
        }
      });
    } catch (e) {
      debugPrint('Stop recording error: $e');
    }
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    _audioRecorder.stop();
    if (_audioPath != null) {
      final file = File(_audioPath!);
      if (file.existsSync()) {
        file.delete();
      }
    }
    setState(() {
      _isRecording = false;
      _showPreview = false;
      _audioPath = null;
      _recordDuration = 0;
    });
  }

  Future<void> _sendRecordedVoice() async {
    if (_audioPath == null) return;

    final path = _audioPath!;
    setState(() {
      _showPreview = false;
      _isLoading = true;
    });

    if (mounted) {
      // Quietly start upload
    }

    try {
      final uploadResult = await _chatService.uploadMedia(path);
      if (uploadResult['success']) {
        _socketService.emit('message:send', {
          'conversationId': _activeConversationId ?? widget.conversationId,
          'receiverId': widget.otherUserId,
          'type': 'audio',
          'content': uploadResult['url'],
        });
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _audioPath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);

    return UserLayout(
      titleWidget: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF202C33),
                child: widget.avatar != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(widget.avatar!, fit: BoxFit.cover),
                      )
                    : Text(
                        widget.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white70),
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
                    color: _isTyping ? waTeal : Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: _isTyping ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: waDarkBg,
      foregroundColor: Colors.white,
      currentIndex: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      extraActions: [
        IconButton(
          icon: const Icon(Icons.call, color: Colors.white),
          onPressed: () {
            // Initiate call logic
            CallOverlayManager.show(
              context,
              widget.name,
              widget.avatar ?? '',
              widget.otherUserId,
            );
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            if (value == 'clear') {
              _clearChat();
            } else if (value == 'delete') {
              _deleteChat();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear',
              child: Text('Clear chat'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete chat', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ],
      body: Stack(
        children: [
          // High-Performance WhatsApp Pattern Background
          Positioned.fill(
            child: Image.network(
              'https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.08),
              colorBlendMode: BlendMode.dstIn,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0B141B)),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: (_isLoading && _messages.isEmpty)
                    ? _buildSkeletonLoading()
                    : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(10),
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
                                    color: Colors.grey.withOpacity(0.1),
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
            _buildMessageInput(),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
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

  bool _isSameDay(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1))))
      return 'Yesterday';
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      decoration: const BoxDecoration(
        color: Colors.transparent, // Background will be handled by the children
      ),
      child: _showPreview
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _audioPath != null
                        ? _AudioPlayerWidget(
                            url: _audioPath!,
                            isMe: true,
                            isLocal: true,
                          )
                        : const SizedBox(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFF8696A0), size: 24),
                    onPressed: _cancelRecording,
                  ),
                  GestureDetector(
                    onTap: _sendRecordedVoice,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF111B21),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 22),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: _isRecording
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.attach_file, color: Color(0xFF8696A0)),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Recording... ',
                                        style: TextStyle(
                                          color: Color(0xFF8696A0),
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(
                                          Duration(
                                            seconds: _recordDuration.toInt(),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF8696A0),
                                          fontSize: 16,
                                        ),
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                )
                              : TextField(
                                  controller: _messageController,
                                  onChanged: (val) {
                                    setState(() {});
                                    if (val.isNotEmpty) {
                                      _socketService.emit('typing:start', {
                                        'conversationId':
                                            _activeConversationId ??
                                            widget.conversationId,
                                        'receiverId': widget.otherUserId,
                                      });
                                    }
                                    _typingTimer?.cancel();
                                    _typingTimer = Timer(
                                      const Duration(seconds: 2),
                                      () {
                                        _socketService.emit('typing:stop', {
                                          'conversationId':
                                              _activeConversationId ??
                                              widget.conversationId,
                                          'receiverId': widget.otherUserId,
                                        });
                                      },
                                    );
                                  },
                                  onSubmitted: (_) => _sendMessage(),
                                  decoration: const InputDecoration(
                                    hintText: 'Message',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                        ),
                        if (!_isRecording) ...[
                          IconButton(
                            icon: const Icon(
                              Icons.attach_file,
                              color: Colors.grey,
                            ),
                            onPressed: _pickAndUploadFile,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Colors.grey,
                            ),
                            onPressed: () {},
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_isRecording) {
                      _stopRecording();
                    } else if (_messageController.text.trim().isEmpty) {
                      _startRecording();
                    } else {
                      _sendMessage();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isRecording ? Colors.red : const Color(0xFF128C7E),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRecording
                          ? Icons.stop
                          : (_messageController.text.trim().isEmpty
                                ? Icons.mic
                                : Icons.send),
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('Clear Chat', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to clear all messages in this chat?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _messages.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
    }
  }

  Future<void> _deleteChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('Delete Chat', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this chat?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      Navigator.pop(context);
    }
  }

  Widget _buildVoicePreview() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: _cancelRecording,
        ),
        Expanded(
          child: _audioPath != null
              ? _AudioPlayerWidget(
                  url: _audioPath!,
                  isMe: true,
                  isLocal: true,
                )
              : const SizedBox(),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "$mins:${secs.toString().padLeft(2, '0')}";
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _ChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFE7FFDB) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMessageContent(context),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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

  Widget _buildMessageContent(BuildContext context) {
    switch (message.type) {
      case 'image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                message.content,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      height: 200,
                      width: 200,
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image,
                  size: 100,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
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
              Icon(fileIcon, color: iconColor, size: 24),
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
        return Text(message.content, style: const TextStyle(fontSize: 16));
    }
  }
}

class _AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  final bool isLocal;
  const _AudioPlayerWidget({
    required this.url,
    required this.isMe,
    this.isLocal = false,
  });

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent, // Parent container handles background
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFFE7E9FD),
              shape: BoxShape.circle,
            ),
            child: GestureDetector(
              onTap: () {
                if (_isPlaying) {
                  _player.pause();
                } else {
                  if (widget.isLocal) {
                    _player.play(DeviceFileSource(widget.url));
                  } else {
                    _player.play(UrlSource(widget.url));
                  }
                }
              },
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: const Color(0xFF535AED),
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Waveform placeholder
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E9FD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0 
                      ? _position.inMilliseconds / _duration.inMilliseconds 
                      : 0.0,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF535AED)),
                  minHeight: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatDuration(_isPlaying ? _position : _duration),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "$mins:${secs.toString().padLeft(2, '0')}";
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}
