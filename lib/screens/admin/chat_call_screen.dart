import 'dart:async';
import 'package:flutter/material.dart';
import 'individual_chat_page.dart';
import 'group_chat_page.dart';
import '../../services/chat/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/chat/group_chat_service.dart';
import '../../models/chat_conversation_model.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'admin_common_widgets/admin_layout.dart';
import '../special_widgets/call_overlay.dart';
import '../../services/admin/call_log_service.dart';
import '../../models/call_log_model.dart';

class ChatCallScreen extends StatefulWidget {
  const ChatCallScreen({super.key});

  @override
  State<ChatCallScreen> createState() => _ChatCallScreenState();
}

class _ChatCallScreenState extends State<ChatCallScreen> with TickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();
  final GroupChatService _groupChatService = GroupChatService();
  List<Conversation> _conversations = [];
  List<dynamic> _groups = [];
  List<CallLog> _callLogs = [];
  bool _isLoading = true;
  String? _currentUserId;
  final Map<String, bool> _onlineStatuses = {};
  late TabController _tabController;
  StreamSubscription? _socketSubscription;
  
  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Socket handlers
  late final Function(dynamic) _userOnlineHandler;
  late final Function(dynamic) _userOfflineHandler;
  late final Function(dynamic) _usersOnlineListHandler;
  late final Function(dynamic) _userStatusResponseHandler;
  late final Function(dynamic) _groupCreatedHandler;
  late final Function(dynamic) _groupDeletedHandler;
  late final Function(dynamic) _groupRenamedHandler;
  late final Function(dynamic) _messageReceiveHandler;
  late final Function(dynamic) _messageSentHandler;
  late final Function(dynamic) _groupMessageReceiveHandler;
  late final Function(dynamic) _conversationUpdateHandler;
  late final Function(dynamic) _groupUpdateHandler;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _initHandlers();
    _socketService.connect();
    _setupSocketListeners();
    _socketSubscription = _socketService.connectionStatus.listen((connected) {
      if (connected && mounted) {
        debugPrint('📡 [Admin Chat] Socket reconnected, requesting online list...');
        _socketService.emit('user:request_online_list', {});
      }
    });
    _loadData();
  }

  void _initHandlers() {
    _userOnlineHandler = (data) {
      if (mounted) setState(() => _onlineStatuses[data['userId']] = true);
    };
    _userOfflineHandler = (data) {
      if (mounted) setState(() => _onlineStatuses[data['userId']] = false);
    };
    _usersOnlineListHandler = (data) {
      final List<dynamic> onlineIds = data['userIds'] ?? [];
      if (mounted) {
        setState(() {
          _onlineStatuses.clear();
          for (var id in onlineIds) {
            _onlineStatuses[id.toString()] = true;
          }
        });
      }
    };
    _userStatusResponseHandler = (data) {
      if (mounted)
        setState(() => _onlineStatuses[data['userId']] = data['isOnline'] ?? false);
    };
    _groupCreatedHandler = (data) {
      if (mounted) _onRefresh();
    };
    _groupDeletedHandler = (data) {
      if (mounted) _onRefresh();
    };
    _groupRenamedHandler = (data) {
      if (mounted) _onRefresh();
    };
    _messageReceiveHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _messageSentHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _groupMessageReceiveHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _conversationUpdateHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _groupUpdateHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
  }

  @override
  void dispose() {
    _socketService.off('user:online', _userOnlineHandler);
    _socketService.off('user:offline', _userOfflineHandler);
    _socketService.off('users:online_list', _usersOnlineListHandler);
    _socketService.off('user:status_response', _userStatusResponseHandler);
    _socketService.off('group:created', _groupCreatedHandler);
    _socketService.off('group:deleted', _groupDeletedHandler);
    _socketService.off('group:renamed', _groupRenamedHandler);
    _socketService.off('message:receive', _messageReceiveHandler);
    _socketService.off('message:sent', _messageSentHandler);
    _socketService.off('group:message:receive', _groupMessageReceiveHandler);
    _socketService.off('conversation:update', _conversationUpdateHandler);
    _socketService.off('group:update', _groupUpdateHandler);

    _tabController.dispose();
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on('user:online', _userOnlineHandler);
    _socketService.on('user:offline', _userOfflineHandler);
    _socketService.on('users:online_list', _usersOnlineListHandler);
    _socketService.on('user:status_response', _userStatusResponseHandler);
    _socketService.on('group:created', _groupCreatedHandler);
    _socketService.on('group:deleted', _groupDeletedHandler);
    _socketService.on('group:renamed', _groupRenamedHandler);
    _socketService.on('message:receive', _messageReceiveHandler);
    _socketService.on('message:sent', _messageSentHandler);
    _socketService.on('group:message:receive', _groupMessageReceiveHandler);
    _socketService.on('conversation:update', _conversationUpdateHandler);
    _socketService.on('group:update', _groupUpdateHandler);
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _conversations.isEmpty && _groups.isEmpty) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      final conversationsResponse = await _chatService.getConversations();
      final groupsResponse = await _groupChatService.getMyGroups();
      final callLogsResponse = await CallLogService.getAdminCallLogs();
      final user = await _authService.getUser();

      if (mounted) {
        setState(() {
          _conversations = conversationsResponse.conversations;
          _groups = groupsResponse['groups'] ?? [];
          _callLogs = callLogsResponse ?? [];
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

  void _showMessageDialog(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'New Message',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF00A884),
                        child: Icon(Icons.group_add, color: Colors.white),
                      ),
                      title: Text(
                        'New Group',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateGroupDialog(context);
                      },
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: partners.length,
                        itemBuilder: (context, index) {
                          final partner = partners[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1A73E8).withOpacity(0.1),
                              child: Text(
                                partner['name'][0].toUpperCase(),
                                style: const TextStyle(color: Color(0xFF1A73E8)),
                              ),
                            ),
                            title: Text(partner['name'], style: TextStyle(color: textColor)),
                            subtitle: Text(
                              partner['role']
                                  .toString()
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              style: TextStyle(fontSize: 12, color: subTextColor),
                            ),
                            onTap: () async {
                              try {
                                final convId = await _chatService.startConversation(
                                  partner['_id'],
                                );
                                if (convId != null && mounted) {
                                  Navigator.pop(context);
                                  _onRefresh();
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => IndividualChatPage(
                                        name: partner['name'],
                                        avatar: '',
                                        conversationId: convId,
                                        receiverId: partner['_id'],
                                      ),
                                    ),
                                  );
                                  if (mounted) _loadData(silent: true);
                                }
                              } catch (e) {
                                debugPrint('Error starting chat: $e');
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

  void _showCallDialog(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Contact to Call',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: partners.length,
                  itemBuilder: (context, index) {
                    final partner = partners[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF00A884).withOpacity(0.1),
                        child: Text(
                          partner['name'][0].toUpperCase(),
                          style: const TextStyle(color: Color(0xFF00A884)),
                        ),
                      ),
                      title: Text(partner['name'], style: TextStyle(color: textColor)),
                      subtitle: Text(
                        partner['role']
                            .toString()
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                      trailing: const Icon(Icons.call, color: Color(0xFF00A884)),
                      onTap: () {
                        Navigator.pop(context);
                        CallOverlayManager.show(
                          context,
                          partner['name'],
                          '',
                          partner['_id'],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    final List<String> selectedIds = [];
    final TextEditingController nameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: modalBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Create Group',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      TextButton(
                        onPressed: selectedIds.isNotEmpty
                            ? () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter group name'),
                                    ),
                                  );
                                  return;
                                }
                                final res = await _groupChatService.createGroup(
                                  name: name,
                                  memberIds: selectedIds,
                                );
                                if (res['success']) {
                                  Navigator.pop(context);
                                  _onRefresh();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(res['error'] ?? 'Error'),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: Text(
                          'Connect',
                          style: TextStyle(fontWeight: FontWeight.bold, color: selectedIds.isNotEmpty ? const Color(0xFF00A884) : subTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: nameController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Enter group name...',
                      hintStyle: TextStyle(color: subTextColor),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: partners.length,
                  itemBuilder: (context, index) {
                    final partner = partners[index];
                    final isSelected = selectedIds.contains(partner['_id']);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true)
                            selectedIds.add(partner['_id']);
                          else
                            selectedIds.remove(partner['_id']);
                        });
                      },
                      secondary: CircleAvatar(
                        backgroundColor: const Color(
                          0xFF1A73E8,
                        ).withOpacity(0.1),
                        child: Text(
                          partner['name'][0].toUpperCase(),
                          style: const TextStyle(color: Color(0xFF1A73E8)),
                        ),
                      ),
                      title: Text(partner['name'], style: TextStyle(color: textColor)),
                      subtitle: Text(
                        partner['role']
                            .toString()
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildCallList() {
    var filteredLogs = _callLogs;
    if (_searchQuery.isNotEmpty) {
      filteredLogs = _callLogs.where((log) {
        final otherUser = _currentUserId != null && log.caller.id == _currentUserId ? log.receiver : log.caller;
        return otherUser.name.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    if (filteredLogs.isEmpty) {
      return _buildPlaceholderTab(Icons.call_outlined, _searchQuery.isEmpty ? 'Start a call with your contacts' : 'No call logs matching "$_searchQuery"');
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.black54;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filteredLogs.length,
      separatorBuilder: (context, index) =>
          Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
      itemBuilder: (context, index) {
            final log = filteredLogs[index];
            final isOutgoing = _currentUserId != null && log.caller.id == _currentUserId;
            final bool isMissed = ['missed', 'rejected', 'failed'].contains(log.status);
            
            final otherUser = isOutgoing ? log.receiver : log.caller;
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                child: Text(
                  otherUser.name.isNotEmpty ? otherUser.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 22, 
                    color: isDark ? Colors.white70 : Colors.grey[600], 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
              title: Text(
                otherUser.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600, 
                  fontSize: 17, 
                  color: isMissed ? Colors.redAccent : textColor
                ),
              ),
              subtitle: Row(
                children: [
                  Icon(
                    isOutgoing ? Icons.call_made : (isMissed ? Icons.call_missed : Icons.call_received),
                    size: 16,
                    color: isMissed ? Colors.redAccent : const Color(0xFF25D366),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMMM d, h:mm a').format(log.createdAt.toLocal()),
                    style: TextStyle(color: subTextColor, fontSize: 14),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.call, color: Color(0xFF00A884)),
                onPressed: () {
                  CallOverlayManager.show(
                    context,
                    otherUser.name,
                    '', // Avatar not available in call logs
                    otherUser.id,
                  );
                },
              ),
              onTap: () {
                // Show call details or recording if available
              },
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waTeal = const Color(0xFF00A884);
    final Color waGrey = isDark ? const Color(0xFF8696A0) : Colors.black54;

    return AdminLayout(
      titleWidget: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: _tabController.index == 0 ? 'Search chats...' : 'Search calls...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                border: InputBorder.none,
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.toLowerCase());
              },
            )
          : null,
      title: _isSearching ? null : 'Chats',
      currentIndex: 3,
      onRefresh: _loadData,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: waTeal,
        indicatorWeight: 3.5,
        labelColor: isDark ? waTeal : Colors.white,
        unselectedLabelColor: isDark ? waGrey : Colors.white70,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('CHATS'),
                if (_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + (g['unreadCount'] ?? 0)) > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? waTeal : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + (g['unreadCount'] ?? 0))}',
                      style: TextStyle(
                        color: isDark ? Colors.black : waTeal,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'CALLS'),
        ],
      ),
      extraActions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              if (_isSearching) {
                _isSearching = false;
                _searchQuery = '';
                _searchController.clear();
              } else {
                _isSearching = true;
              }
            });
          },
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showMessageDialog(context);
          } else {
            _showCallDialog(context);
          }
        },
        backgroundColor: waTeal,
        elevation: 4,
        child: Icon(
          _tabController.index == 0 ? Icons.message : Icons.add_call,
          color: Colors.white,
          size: 28,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
            // Chats Tab
            RefreshIndicator(
              onRefresh: _onRefresh,
              color: waTeal,
              child: _isLoading && _conversations.isEmpty && _groups.isEmpty
                  ? _buildSkeletonList()
                  : _buildChatList(),
            ),
            
            // Status Tab Placeholder
            // _buildPlaceholderTab(Icons.update, 'Status updates will appear here'),
            
            // Calls Tab
            RefreshIndicator(
              onRefresh: _onRefresh,
              color: waTeal,
              child: _isLoading && _callLogs.isEmpty
                  ? _buildSkeletonList()
                  : _buildCallList(),
            ),
          ],
        ),
      );
  }

  Widget _buildPlaceholderTab(IconData icon, String text) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: isDark ? const Color(0xFF202C33) : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(color: isDark ? const Color(0xFF8696A0) : Colors.black54, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF202C33) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF2C3943) : const Color(0xFFF5F5F5),
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
    var allItems = [
      ..._conversations.map((c) => {'type': 'individual', 'data': c}),
      ..._groups.map((g) => {'type': 'group', 'data': g}),
    ];

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      allItems = allItems.where((item) {
        if (item['type'] == 'group') {
          final group = item['data'] as Map;
          return (group['name'] ?? '').toString().toLowerCase().contains(_searchQuery);
        } else {
          final conv = item['data'] as Conversation;
          final otherParticipant = conv.participants.firstWhere(
            (p) => p.id != _currentUserId,
            orElse: () => conv.participants.first,
          );
          return otherParticipant.name.toLowerCase().contains(_searchQuery);
        }
      }).toList();
    }

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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No conversations yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.black54;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: allItems.length,
      separatorBuilder: (context, index) =>
          Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
      itemBuilder: (context, index) {
        final item = allItems[index];

        if (item['type'] == 'group') {
          final group = item['data'] as Map;
          final lastMsg = group['lastMessage'];
          final timeStr = lastMsg?['timestamp'] != null
              ? DateFormat.jm().format(
                  DateTime.parse(lastMsg['timestamp']).toLocal(),
                )
              : '';

          return GestureDetector(
            onLongPress: () => _showGroupOptions(context, group),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
              child: Icon(Icons.groups, size: 28, color: isDark ? Colors.white70 : Colors.grey[600]),
            ),
            title: Text(
              group['name'],
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: textColor),
            ),
            subtitle: Row(
              children: [
                if (lastMsg != null) ...[
                  Text(
                    '~${lastMsg['senderName'] ?? 'Member'}: ',
                    style: TextStyle(color: subTextColor, fontSize: 14),
                  ),
                ],
                Expanded(
                  child: Text(
                    lastMsg?['content'] ?? 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subTextColor, fontSize: 14),
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
                  const SizedBox(height: 24), // Maintain height consistency
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatPage(groupId: group['_id'], name: group['name']),
                ),
              );
              if (mounted) _loadData(silent: true);
            },
          ),
        );
        }

        // Individual Chat logic
        final conversation = item['data'] as Conversation;
        final otherParticipant = conversation.participants.firstWhere(
          (p) => p.id != _currentUserId,
          orElse: () => conversation.participants.first,
        );
        final bool isOnline = _onlineStatuses[otherParticipant.id] ?? false;
        final lastMsgIndividual = conversation.lastMessage;
        final timeStrIndividual = lastMsgIndividual?.timestamp != null
            ? DateFormat.jm().format(lastMsgIndividual!.timestamp!.toLocal())
            : '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF1A73E8).withOpacity(0.1),
                child: Text(
                  otherParticipant.name.isNotEmpty ? otherParticipant.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 22, color: Color(0xFF1A73E8), fontWeight: FontWeight.bold),
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
                      border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111B21) : Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            otherParticipant.name,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: textColor),
          ),
          subtitle: Row(
            children: [
              if (lastMsgIndividual?.type == 'audio')
                const Icon(Icons.mic, size: 16, color: Colors.grey),
              if (lastMsgIndividual?.type == 'image')
                const Icon(Icons.image, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  lastMsgIndividual?.content ?? 'No messages',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subTextColor, fontSize: 14),
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStrIndividual,
                style: TextStyle(
                  color: conversation.unreadCount > 0 ? const Color(0xFF25D366) : Colors.grey[500],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              if (conversation.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${conversation.unreadCount}',
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
                builder: (context) => IndividualChatPage(
                  name: otherParticipant.name,
                  avatar: '',
                  conversationId: conversation.id,
                  receiverId: otherParticipant.id,
                ),
              ),
            );
            if (mounted) _loadData(silent: true);
          },
        );
      },
    );
  }

  void _showGroupOptions(BuildContext context, Map group) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      backgroundColor: modalBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: isDark ? Colors.white70 : Colors.black54),
            title: Text('Clear Chat', style: TextStyle(color: textColor)),
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
