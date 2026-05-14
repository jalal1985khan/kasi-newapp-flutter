import 'package:flutter/material.dart';
import 'common_widgets/user_layout.dart';
import 'individual_chat_screen.dart';
import '../../services/chat/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/group_chat_service.dart';
import '../../models/chat_conversation_model.dart';
import '../admin/group_chat_page.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';

class UserChatCallScreen extends StatefulWidget {
  const UserChatCallScreen({super.key});

  @override
  State<UserChatCallScreen> createState() => _UserChatCallScreenState();
}

class _UserChatCallScreenState extends State<UserChatCallScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();
  final GroupChatService _groupChatService = GroupChatService();
  List<Conversation> _conversations = [];
  List<dynamic> _groups = [];
  bool _isLoading = true;
  String? _currentUserId;
  final Map<String, bool> _onlineStatuses = {};
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _socketService.connect();
    _setupSocketListeners();
    _socketSubscription = _socketService.connectionStatus.listen((connected) {
      if (connected && mounted) {
        debugPrint('📡 [User Chat] Socket reconnected, requesting online list...');
        _socketService.emit('user:request_online_list', {});
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on('user:online', (data) {
      if (mounted) setState(() => _onlineStatuses[data['userId']] = true);
    });
    _socketService.on('user:offline', (data) {
      if (mounted) setState(() => _onlineStatuses[data['userId']] = false);
    });
    _socketService.on('users:online_list', (data) {
      final List<dynamic> onlineIds = data['userIds'] ?? [];
      if (mounted) {
        setState(() {
          for (var id in onlineIds) {
            _onlineStatuses[id.toString()] = true;
          }
        });
      }
    });
    _socketService.on('user:status_response', (data) {
      if (mounted)
        setState(
          () => _onlineStatuses[data['userId']] = data['isOnline'] ?? false,
        );
    });

    _socketService.on('group:created', (data) {
      if (mounted) _onRefresh();
    });

    _socketService.on('group:deleted', (data) {
      if (mounted) _onRefresh();
    });

    _socketService.on('group:renamed', (data) {
      if (mounted) _onRefresh();
    });

    // Real-time message updates for the conversation list
    _socketService.on('message:receive', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('message:sent', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('group:message:receive', (data) {
      if (mounted) _loadData(silent: true);
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _conversations.isEmpty && _groups.isEmpty) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      final conversationsResponse = await _chatService.getConversations();
      final groupsResponse = await _groupChatService.getMyGroups();
      final user = await _authService.getUser();

      if (mounted) {
        setState(() {
          _conversations = conversationsResponse.conversations;
          _groups = groupsResponse['groups'] ?? [];
          _currentUserId = user?['id'] ?? user?['_id'];
          _isLoading = false;
        });

        // Request online status update after loading conversations
        _socketService.emit('user:request_online_list', {});
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  void _showMessageDialog() async {
    final partners = await _chatService.getPartners();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Message Admin',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: partners.length,
                itemBuilder: (context, index) {
                  final partner = partners[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).primaryColor.withOpacity(0.1),
                      child: Text(partner['name'][0].toUpperCase()),
                    ),
                    title: Text(partner['name']),
                    subtitle: Text(
                      partner['role']
                          .toString()
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      try {
                        final convId = await _chatService.startConversation(
                          partner['_id'],
                        );
                        if (convId != null && mounted) {
                          Navigator.pop(context); // Close sheet
                          _onRefresh(); // Refresh in background
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => IndividualChatScreen(
                                conversationId: convId,
                                name: partner['name'],
                                otherUserId: partner['_id'],
                              ),
                            ),
                          );
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to start conversation. Please try again.',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error starting chat: $e')),
                          );
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
  }

  @override
  Widget build(BuildContext context) {
    const Color waTeal = Color(0xFF00A884);
    const Color waGrey = Color(0xFF8696A0);

    return DefaultTabController(
      length: 3,
      initialIndex: 0,
      child: UserLayout(
        title: 'Chats',
        currentIndex: 1,
        onRefresh: _loadData,
        bottom: const TabBar(
          indicatorColor: waTeal,
          indicatorWeight: 3.5,
          labelColor: waTeal,
          unselectedLabelColor: waGrey,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: [
            Tab(text: 'CHATS'),
            Tab(text: 'STATUS'),
            Tab(text: 'CALLS'),
          ],
        ),
        extraActions: [
          IconButton(icon: const Icon(Icons.camera_alt_outlined, color: waGrey), onPressed: () {}),
          IconButton(icon: const Icon(Icons.search, color: waGrey), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert, color: waGrey), onPressed: () {}),
        ],
        floatingActionButton: FloatingActionButton(
          onPressed: _showMessageDialog,
          backgroundColor: waTeal,
          elevation: 4,
          child: const Icon(Icons.message, color: Colors.white, size: 28),
        ),
        body: TabBarView(
          children: [
            // Chats Tab
            _isLoading && _conversations.isEmpty && _groups.isEmpty
                ? _buildSkeletonList()
                : _buildChatList(),
            
            // Status Tab Placeholder
            _buildPlaceholderTab(Icons.update, 'Status updates will appear here'),
            
            // Calls Tab Placeholder
            _buildPlaceholderTab(Icons.call_outlined, 'Start a call with your contacts'),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: const Color(0xFF202C33)),
          const SizedBox(height: 16),
          Text(
            text,
            style: const TextStyle(color: Color(0xFF8696A0), fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF202C33),
      highlightColor: const Color(0xFF2C3943),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 10,
        itemBuilder: (context, index) => ListTile(
          leading: const CircleAvatar(radius: 28, backgroundColor: Colors.white),
          title: Container(height: 16, width: double.infinity, color: Colors.white),
          subtitle: Container(height: 12, width: 150, color: Colors.white, margin: const EdgeInsets.only(top: 8)),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    // Filter individual chats: Employee can only see conversations with an Admin
    final adminChats = _conversations.where((conv) {
      return conv.participants.any(
        (p) => p.role == 'admin' || p.role == 'super-admin',
      );
    }).toList();

    final allItems = [
      ...adminChats.map((c) => {'type': 'individual', 'data': c}),
      ..._groups.map((g) => {'type': 'group', 'data': g}),
    ];

    // Sort all by last updated
    allItems.sort((a, b) {
      DateTime da = a['type'] == 'individual'
          ? (a['data'] as Conversation).updatedAt ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse((a['data'] as Map)['updatedAt'] ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
      DateTime db = b['type'] == 'individual'
          ? (b['data'] as Conversation).updatedAt ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse((b['data'] as Map)['updatedAt'] ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    if (allItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 60),
            SizedBox(height: 16),
            Text('No chats found.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: allItems.length,
      separatorBuilder: (context, index) =>
          const Divider(color: Color(0xFF1F2C34), thickness: 0.2, height: 1, indent: 85),
      itemBuilder: (context, index) {
        final item = allItems[index];

        if (item['type'] == 'group') {
          final group = item['data'] as Map;
          final lastMsg = group['lastMessage'];
          final timeStr = lastMsg?['timestamp'] != null
              ? _formatTime(DateTime.parse(lastMsg['timestamp']))
              : '';

          return GestureDetector(
            onLongPress: () => _showGroupOptions(context, group),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[800],
              child: const Icon(Icons.groups, size: 28, color: Colors.white70),
            ),
            title: Text(
              group['name'],
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Colors.white),
            ),
            subtitle: Row(
              children: [
                if (lastMsg != null) ...[
                  Text(
                    '~${lastMsg['senderName'] ?? 'Member'}: ',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
                Expanded(
                  child: Text(
                    lastMsg?['content'] ?? 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: (group['unreadCount'] ?? 0) > 0 ? const Color(0xFF25D366) : Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                if ((group['unreadCount'] ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: Color(0xFF25D366),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${group['unreadCount']}',
                      style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const SizedBox(height: 24),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatPage(groupId: group['_id'], name: group['name'], isAdmin: false),
                ),
              );
              if (mounted) _loadData(silent: true);
            },
          ),
        );
        }

        final conv = item['data'] as Conversation;
        // Find the other participant (the admin)
        final admin = conv.participants.firstWhere(
          (p) => p.id != _currentUserId,
          orElse: () => conv.participants.first,
        );

        final bool isOnline = _onlineStatuses[admin.id] ?? false;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF202C33),
                child: Text(
                  admin.name.isNotEmpty ? admin.name[0].toUpperCase() : 'A',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              if (isOnline)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF111B21), width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            admin.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Colors.white),
          ),
          subtitle: Row(
            children: [
              if (conv.lastMessage?.type == 'audio')
                const Icon(Icons.mic, size: 16, color: Colors.grey),
              if (conv.lastMessage?.type == 'image')
                const Icon(Icons.image, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  conv.lastMessage?.content ?? 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                conv.updatedAt != null ? _formatTime(conv.updatedAt!) : '',
                style: TextStyle(
                  color: conv.unreadCount > 0 ? const Color(0xFF25D366) : Colors.grey[500],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              if (conv.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${conv.unreadCount}',
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              else
                const SizedBox(height: 24),
            ],
          ),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => IndividualChatScreen(
                  conversationId: conv.id,
                  otherUserId: admin.id,
                  name: admin.name,
                ),
              ),
            );
            if (mounted) _loadData(silent: true);
          },
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    if (now.year == localDate.year &&
        now.month == localDate.month &&
        now.day == localDate.day) {
      return DateFormat('hh:mm a').format(localDate);
    }
    return DateFormat('yyyy-MM-dd').format(localDate);
  }

  void _showGroupOptions(BuildContext context, Map group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111B21),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            title: const Text('Clear Chat', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              _clearGroupChat(group['_id']);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Delete Group', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(context);
              _deleteGroup(group['_id']);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _clearGroupChat(String groupId) async {
    await _groupChatService.clearGroupChat(groupId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
      _loadData(silent: true);
    }
  }

  Future<void> _deleteGroup(String groupId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('Delete Group', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this group?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed == true) {
      await _groupChatService.deleteGroup(groupId);
      _loadData(silent: true);
    }
  }
}
