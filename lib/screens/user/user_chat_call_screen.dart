import 'dart:async';
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
import '../../services/admin/call_log_service.dart';
import '../../models/call_log_model.dart';
import '../special_widgets/call_overlay.dart';
import '../../utils/premium_widgets.dart';

class UserChatCallScreen extends StatefulWidget {
  const UserChatCallScreen({super.key});

  @override
  State<UserChatCallScreen> createState() => _UserChatCallScreenState();
}

class _UserChatCallScreenState extends State<UserChatCallScreen> with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
    _tabController.dispose();
    _socketSubscription?.cancel();
    _searchController.dispose();
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
          _onlineStatuses.clear(); // Clear old statuses to avoid "always online" bug
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

    // Real-time message updates
    _socketService.on('message:receive', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('message:sent', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('group:message:receive', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('conversation:update', (data) {
      if (mounted) _loadData(silent: true);
    });
    _socketService.on('group:update', (data) {
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
      final callLogsResponse = await CallLogService.getUserCallLogs();
      final user = await _authService.getUser();

      if (mounted) {
        setState(() {
          _conversations = conversationsResponse.conversations;
          _groups = groupsResponse['groups'] ?? [];
          _callLogs = callLogsResponse ?? [];
          _currentUserId = user?['id'] ?? user?['_id'];
          _isLoading = false;
        });

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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final partners = await _chatService.getPartners();
    if (!mounted) return;

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
                  'Message Admin',
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
                          style: const TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(partner['name'], style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        partner['role'].toString().replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                      onTap: () async {
                        try {
                          final convId = await _chatService.startConversation(partner['_id']);
                          if (convId != null && mounted) {
                            Navigator.pop(context);
                            _onRefresh();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => IndividualChatScreen(
                                    conversationId: convId,
                                    name: partner['name'],
                                    otherUserId: partner['_id'],
                                    avatar: AuthService().getFullUrl(partner['profileImage']),
                                  ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
      ),
    );
  }

  void _showCallDialog() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final partners = await _chatService.getPartners();
    if (!mounted) return;

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
                          style: const TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(partner['name'], style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        partner['role'].toString().replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                      trailing: const Icon(Icons.call, color: Color(0xFF00A884)),
                      onTap: () {
                        Navigator.pop(context);
                        CallOverlayManager.show(context, partner['name'], AuthService().getFullUrl(partner['profileImage']) ?? '', partner['_id']);
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waTeal = const Color(0xFF00A884);
    final Color waGrey = isDark ? const Color(0xFF8696A0) : Colors.white70;

    return UserLayout(
      titleWidget: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: _tabController.index == 0 ? 'Search chats...' : 'Search calls...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                border: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
            )
          : null,
      title: _isSearching ? null : 'Chats',
      currentIndex: 1,
      onRefresh: _loadData,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: isDark ? waTeal : Colors.white,
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
                if (_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + ((g['unreadCount'] ?? 0) as int)) > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? waTeal : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + ((g['unreadCount'] ?? 0) as int))}',
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
          icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
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
      floatingActionButton: SoftTouchWrapper(
        onTap: () => _tabController.index == 0 ? _showMessageDialog() : _showCallDialog(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: waTeal,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: waTeal.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _tabController.index == 0 ? Icons.message : Icons.add_call,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: waTeal,
            child: _isLoading && _conversations.isEmpty && _groups.isEmpty
                ? _buildSkeletonList(isDark)
                : _buildChatList(isDark),
          ),
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: waTeal,
            child: _isLoading && _callLogs.isEmpty
                ? _buildSkeletonList(isDark)
                : _buildCallList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList(bool isDark) {
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

  Widget _buildChatList(bool isDark) {
    var allItems = [
      ..._conversations.where((c) => c.participants.any((p) => p.role == 'admin' || p.role == 'super-admin')).map((c) => {'type': 'individual', 'data': c}),
      ..._groups.map((g) => {'type': 'group', 'data': g}),
    ];

    if (_searchQuery.isNotEmpty) {
      allItems = allItems.where((item) {
        if (item['type'] == 'group') {
          return (item['data'] as Map)['name'].toString().toLowerCase().contains(_searchQuery);
        } else {
          final conv = item['data'] as Conversation;
          final other = conv.participants.firstWhere((p) => p.id != _currentUserId, orElse: () => conv.participants.first);
          return other.name.toLowerCase().contains(_searchQuery);
        }
      }).toList();
    }

    allItems.sort((a, b) {
      DateTime da = a['type'] == 'individual'
          ? (a['data'] as Conversation).updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse((a['data'] as Map)['updatedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime db = b['type'] == 'individual'
          ? (b['data'] as Conversation).updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse((b['data'] as Map)['updatedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    if (allItems.isEmpty) return _buildEmptyState(Icons.chat_bubble_outline, 'No conversations yet');

    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.black54;

    return ListView.separated(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: allItems.length,
      separatorBuilder: (context, index) => Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
      itemBuilder: (context, index) {
        final item = allItems[index];
        if (item['type'] == 'group') {
          final group = item['data'] as Map;
          final lastMsg = group['lastMessage'];
          return ListTile(
            onLongPress: () => _showGroupOptions(context, group, isDark, textColor, subTextColor),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
              backgroundImage: (group['profileImage'] != null && group['profileImage'].toString().isNotEmpty)
                  ? NetworkImage(AuthService().getFullUrl(group['profileImage'].toString())!)
                  : null,
              child: (group['profileImage'] == null || group['profileImage'].toString().isEmpty)
                  ? Icon(Icons.groups, size: 28, color: isDark ? Colors.white70 : Colors.grey[600])
                  : null,
            ),
            title: Text(group['name'], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: textColor)),
            subtitle: Text(lastMsg != null ? '~${lastMsg['senderName'] ?? 'Member'}: ${lastMsg['content'] ?? ""}' : 'No messages yet', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subTextColor, fontSize: 14)),
            trailing: _buildTrailing(group['unreadCount'] ?? 0, lastMsg?['timestamp'], subTextColor),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => GroupChatPage(groupId: group['_id'], name: group['name'], isAdmin: false)));
              _loadData(silent: true);
            },
          );
        }

        final conv = item['data'] as Conversation;
        final admin = conv.participants.firstWhere((p) => p.id != _currentUserId, orElse: () => conv.participants.first);
        final bool isOnline = _onlineStatuses[admin.id] ?? false;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF1A73E8).withOpacity(0.1),
                backgroundImage: (admin.profileImage != null && admin.profileImage!.isNotEmpty)
                    ? NetworkImage(AuthService().getFullUrl(admin.profileImage)!)
                    : null,
                child: (admin.profileImage == null || admin.profileImage!.isEmpty)
                    ? Text(
                        admin.name.isNotEmpty ? admin.name[0].toUpperCase() : 'A',
                        style: const TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.bold, fontSize: 20),
                      )
                    : null,
              ),
              if (isOnline) Positioned(right: 2, bottom: 2, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: const Color(0xFF25D366), shape: BoxShape.circle, border: Border.all(color: isDark ? const Color(0xFF111B21) : Colors.white, width: 2)))),
            ],
          ),
          title: Text(admin.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: textColor)),
          subtitle: Text(conv.lastMessage?.content ?? 'No messages yet', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subTextColor, fontSize: 14)),
          trailing: _buildTrailing(conv.unreadCount, conv.updatedAt?.toIso8601String(), subTextColor),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (context) => IndividualChatScreen(conversationId: conv.id, otherUserId: admin.id, name: admin.name, avatar: AuthService().getFullUrl(admin.profileImage))));
            _loadData(silent: true);
          },
        );
      },
    );
  }

  String? _getEffectiveProfileImage(CallUser user) {
    if (user.profileImage != null && user.profileImage!.isNotEmpty) {
      return user.profileImage;
    }
    // Fallback: search in conversations list
    try {
      for (var item in _conversations) {
        if (item['type'] == 'individual') {
          final conv = item['data'] as Conversation;
          final partner = conv.participants.firstWhere((p) => p.id == user.id, orElse: () => Participant(id: '', name: '', email: '', role: '', fcmToken: ''));
          if (partner.id.isNotEmpty && partner.profileImage != null && partner.profileImage!.isNotEmpty) {
            return partner.profileImage;
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  Widget _buildCallList(bool isDark) {
    var filteredLogs = _callLogs;
    if (_searchQuery.isNotEmpty) {
      filteredLogs = _callLogs.where((log) {
        final other = _currentUserId == log.caller.id ? log.receiver : log.caller;
        return other.name.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    if (filteredLogs.isEmpty) return _buildEmptyState(Icons.call_outlined, 'No call history');

    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.black54;

    return ListView.separated(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: filteredLogs.length,
      separatorBuilder: (context, index) => Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
      itemBuilder: (context, index) {
        final log = filteredLogs[index];
        final isOutgoing = _currentUserId == log.caller.id;
        final bool isMissed = ['missed', 'rejected', 'failed'].contains(log.status);
        final otherUser = isOutgoing ? log.receiver : log.caller;
        final String? effectiveImage = _getEffectiveProfileImage(otherUser);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            backgroundImage: (effectiveImage != null && effectiveImage.isNotEmpty)
                ? NetworkImage(AuthService().getFullUrl(effectiveImage)!)
                : null,
            child: (effectiveImage == null || effectiveImage.isEmpty)
                ? Text(
                    otherUser.name.isNotEmpty ? otherUser.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 22, 
                      color: isDark ? Colors.white70 : Colors.grey[600], 
                      fontWeight: FontWeight.bold
                    ),
                  )
                : null,
          ),
          title: Text(otherUser.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: isMissed ? Colors.redAccent : textColor)),
          subtitle: Row(
            children: [
              Icon(isOutgoing ? Icons.call_made : (isMissed ? Icons.call_missed : Icons.call_received), size: 16, color: isMissed ? Colors.redAccent : const Color(0xFF25D366)),
              const SizedBox(width: 4),
              Text(DateFormat('MMMM d, h:mm a').format(log.createdAt.toLocal()), style: TextStyle(color: subTextColor, fontSize: 14)),
            ],
          ),
          trailing: IconButton(icon: const Icon(Icons.call, color: Color(0xFF00A884)), onPressed: () => CallOverlayManager.show(context, otherUser.name, AuthService().getFullUrl(effectiveImage) ?? '', otherUser.id)),
        );
      },
    );
  }

  Widget _buildTrailing(int unreadCount, String? timestamp, Color subTextColor) {
    final timeStr = timestamp != null ? _formatTime(DateTime.parse(timestamp)) : '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(timeStr, style: TextStyle(color: unreadCount > 0 ? const Color(0xFF25D366) : subTextColor, fontSize: 12)),
        const SizedBox(height: 4),
        if (unreadCount > 0)
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
            child: Text('$unreadCount', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
          )
        else
          const SizedBox(height: 24),
      ],
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    if (now.year == local.year && now.month == local.month && now.day == local.day) return DateFormat('hh:mm a').format(local);
    return DateFormat('yyyy-MM-dd').format(local);
  }

  Widget _buildEmptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }

  void _showGroupOptions(BuildContext context, Map group, bool isDark, Color textColor, Color subTextColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
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
              await _groupChatService.clearGroupChat(group['_id']);
              _loadData(silent: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Delete Group', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
                  title: Text('Delete Group', style: TextStyle(color: textColor)),
                  content: Text('Are you sure?', style: TextStyle(color: subTextColor)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (confirmed == true) {
                await _groupChatService.deleteGroup(group['_id']);
                _loadData(silent: true);
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
