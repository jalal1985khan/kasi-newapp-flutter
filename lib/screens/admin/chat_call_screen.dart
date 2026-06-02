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
import '../status_tab_content.dart';
import 'package:news_cover/services/event_bus.dart';

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
  List<dynamic> _partners = [];
  bool _isLoading = true;
  String? _currentUserId;
  final Map<String, bool> _onlineStatuses = {};
  late TabController _tabController;
  final GlobalKey<StatusTabContentState> _statusTabKey = GlobalKey<StatusTabContentState>();
  StreamSubscription? _socketSubscription;
  StreamSubscription? _eventBusSubscription;
  bool _isGroupsExpanded = true;
  
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
    _tabController = TabController(length: 3, vsync: this);
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
        _loadData(silent: true);
      }
    });
    
    _eventBusSubscription = EventBus().stream.listen((event) {
      if (event == 'fcm_refresh' && mounted) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) _loadData(silent: true);
        });
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
      if (mounted) {
        setState(() => _onlineStatuses[data['userId']] = data['isOnline'] ?? false);
      }
    };
    _groupCreatedHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _groupDeletedHandler = (data) {
      if (mounted) _loadData(silent: true);
    };
    _groupRenamedHandler = (data) {
      if (mounted) _loadData(silent: true);
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
    _socketService.off('group:message:new', _groupMessageReceiveHandler);
    _socketService.off('conversation:update', _conversationUpdateHandler);
    _socketService.off('group:update', _groupUpdateHandler);

    _tabController.dispose();
    _socketSubscription?.cancel();
    _eventBusSubscription?.cancel();
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
    _socketService.on('group:message:new', _groupMessageReceiveHandler);
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
      final allPartners = await _chatService.getPartners();
      final user = await _authService.getUser();

      if (mounted) {
        setState(() {
          _conversations = conversationsResponse.conversations;
          _groups = groupsResponse['groups'] ?? [];
          _callLogs = callLogsResponse ?? [];
          _partners = allPartners;
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
    _socketService.connect(force: true);
    await _loadData();
  }

  void _showMessageDialog(BuildContext outerContext) async {
    final bool isDark = Theme.of(outerContext).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF0B141A) : Colors.white; // WhatsApp slate dark bg
    final Color cardBg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color accentColor = const Color(0xFF00A884); // WhatsApp green

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: modalBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag indicator
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Contact',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${partners.length} contacts available',
                            style: TextStyle(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: textColor),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // Live Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: TextStyle(color: textColor, fontSize: 14),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: subTextColor, size: 20),
                        suffixIcon: searchController.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  searchController.clear();
                                  setModalState(() {
                                    searchQuery = '';
                                  });
                                },
                                child: Icon(Icons.clear_rounded, color: subTextColor, size: 18),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                // Actions & Contacts List
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Only show New Group button when not searching
                      if (searchQuery.isEmpty) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: accentColor.withOpacity(0.12),
                            child: Icon(Icons.group_add_rounded, color: accentColor, size: 22),
                          ),
                          title: Text(
                            'New Group',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            'Create a group conversation',
                            style: TextStyle(color: subTextColor, fontSize: 12),
                          ),
                          onTap: () {
                            Navigator.pop(context); // Close "New Message" sheet safely
                            _showCreateGroupDialog(outerContext); // Use outer context to display new group dialog!
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text(
                            'CONTACTS ON DAILY NEWS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: subTextColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],

                      // Contacts list
                      ...() {
                        final filteredList = partners.where((p) {
                          final name = (p['name'] ?? '').toString().toLowerCase();
                          final username = (p['username'] ?? '').toString().toLowerCase();
                          return name.contains(searchQuery) || username.contains(searchQuery);
                        }).toList();

                        if (filteredList.isEmpty) {
                          return [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(Icons.people_outline_rounded, size: 48, color: subTextColor),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No contacts found',
                                      style: TextStyle(color: subTextColor, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          ];
                        }

                        return filteredList.map((partner) {
                          final String firstLetter = partner['name'] != null && partner['name'].toString().isNotEmpty
                              ? partner['name'][0].toUpperCase()
                              : '?';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: accentColor.withOpacity(0.12),
                              backgroundImage: partner['profileImage'] != null && partner['profileImage'].toString().isNotEmpty
                                  ? NetworkImage(partner['profileImage'])
                                  : null,
                              child: partner['profileImage'] == null || partner['profileImage'].toString().isEmpty
                                  ? Text(
                                      firstLetter,
                                      style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 15),
                                    )
                                  : null,
                            ),
                            title: Text(
                              partner['name'] ?? '',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: Text(
                              '@${partner['username'] ?? ''} • ${partner['role'].toString().replaceAll('_', ' ').toUpperCase()}',
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
                                    outerContext,
                                    MaterialPageRoute(
                                      builder: (context) => IndividualChatPage(
                                        name: partner['name'],
                                        avatar: AuthService().getFullUrl(partner['profileImage']) ?? '',
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
                        }).toList();
                      }(),
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

  void _showCallDialog(BuildContext outerContext) async {
    final bool isDark = Theme.of(outerContext).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF0B141A) : Colors.white; // WhatsApp slate dark bg
    final Color cardBg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color accentColor = const Color(0xFF00A884); // WhatsApp green

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: modalBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag indicator
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Contact to Call',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${partners.length} contacts available',
                            style: TextStyle(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: textColor),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // Live Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: TextStyle(color: textColor, fontSize: 14),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: subTextColor, size: 20),
                        suffixIcon: searchController.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  searchController.clear();
                                  setModalState(() {
                                    searchQuery = '';
                                  });
                                },
                                child: Icon(Icons.clear_rounded, color: subTextColor, size: 18),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    'CONTACTS ON DAILY NEWS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: subTextColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

                // Contacts list
                Expanded(
                  child: () {
                    final filteredList = partners.where((p) {
                      final name = (p['name'] ?? '').toString().toLowerCase();
                      final username = (p['username'] ?? '').toString().toLowerCase();
                      return name.contains(searchQuery) || username.contains(searchQuery);
                    }).toList();

                    if (filteredList.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline_rounded, size: 48, color: subTextColor),
                              const SizedBox(height: 12),
                              Text(
                                'No contacts found',
                                style: TextStyle(color: subTextColor, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final partner = filteredList[index];
                        final String firstLetter = partner['name'] != null && partner['name'].toString().isNotEmpty
                            ? partner['name'][0].toUpperCase()
                            : '?';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: accentColor.withOpacity(0.12),
                            backgroundImage: partner['profileImage'] != null && partner['profileImage'].toString().isNotEmpty
                                ? NetworkImage(partner['profileImage'])
                                : null,
                            child: partner['profileImage'] == null || partner['profileImage'].toString().isEmpty
                                ? Text(
                                    firstLetter,
                                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 15),
                                  )
                                : null,
                          ),
                          title: Text(
                            partner['name'] ?? '',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Text(
                            '@${partner['username'] ?? ''} • ${partner['role'].toString().replaceAll('_', ' ').toUpperCase()}',
                            style: TextStyle(fontSize: 12, color: subTextColor),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.call, color: accentColor, size: 20),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            CallOverlayManager.show(
                              outerContext,
                              partner['name'],
                              AuthService().getFullUrl(partner['profileImage']) ?? '',
                              partner['_id'],
                            );
                          },
                        );
                      },
                    );
                  }(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF0B141A) : Colors.white; // Slate WhatsApp dark bg
    final Color cardBg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color accentColor = const Color(0xFF00A884); // WhatsApp green

    final allPartners = await _chatService.getPartners();
    if (!mounted) return;

    final partners = allPartners
        .where((p) => p['role'] != 'super_admin')
        .toList();

    final List<String> selectedIds = [];
    final TextEditingController nameController = TextEditingController();
    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: modalBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Drag Indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Group',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${selectedIds.length} of ${partners.length} selected',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: accentColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: textColor),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1, thickness: 0.5),

                    // Group Details Inputs
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Group Avatar Icon
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: accentColor,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                              maxLength: 25,
                              decoration: InputDecoration(
                                hintText: 'Type group subject here...',
                                hintStyle: TextStyle(color: subTextColor, fontWeight: FontWeight.normal),
                                counterText: '',
                                labelText: 'Group Name',
                                labelStyle: TextStyle(color: accentColor, fontSize: 13),
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accentColor, width: 2),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accentColor, width: 2),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Horizontal List of Selected Members
                    if (selectedIds.isNotEmpty) ...[
                      Container(
                        height: 90,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: cardBg.withOpacity(0.4),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: selectedIds.length,
                          itemBuilder: (context, index) {
                            final selId = selectedIds[index];
                            final member = partners.firstWhere((p) => p['_id'] == selId);
                            final String firstLetter = member['name'] != null && member['name'].toString().isNotEmpty
                                ? member['name'][0].toUpperCase()
                                : '?';

                            return Container(
                              margin: const EdgeInsets.only(right: 14),
                              width: 60,
                              child: Stack(
                                children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: accentColor.withOpacity(0.15),
                                        backgroundImage: member['profileImage'] != null && member['profileImage'].toString().isNotEmpty
                                            ? NetworkImage(member['profileImage'])
                                            : null,
                                        child: member['profileImage'] == null || member['profileImage'].toString().isEmpty
                                            ? Text(
                                                firstLetter,
                                                style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        member['name'] ?? '',
                                        style: TextStyle(fontSize: 11, color: textColor, overflow: TextOverflow.ellipsis),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                  Positioned(
                                    right: 2,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedIds.remove(selId);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.grey,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5),
                    ],

                    // Search Member Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: searchController,
                          style: TextStyle(color: textColor, fontSize: 14),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val.trim().toLowerCase();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search contacts...',
                            hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                            prefixIcon: Icon(Icons.search_rounded, color: subTextColor, size: 20),
                            suffixIcon: searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      searchController.clear();
                                      setModalState(() {
                                        searchQuery = '';
                                      });
                                    },
                                    child: Icon(Icons.clear_rounded, color: subTextColor, size: 18),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),

                    // Contact List Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Text(
                        'CONTACTS ON DAILY NEWS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: subTextColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),

                    // Contacts List
                    Expanded(
                      child: () {
                        final filteredList = partners.where((p) {
                          final name = (p['name'] ?? '').toString().toLowerCase();
                          final username = (p['username'] ?? '').toString().toLowerCase();
                          return name.contains(searchQuery) || username.contains(searchQuery);
                        }).toList();

                        if (filteredList.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline_rounded, size: 48, color: subTextColor),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No contacts found',
                                    style: TextStyle(color: subTextColor, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final partner = filteredList[index];
                            final isSelected = selectedIds.contains(partner['_id']);
                            final String firstLetter = partner['name'] != null && partner['name'].toString().isNotEmpty
                                ? partner['name'][0].toUpperCase()
                                : '?';

                            return InkWell(
                              onTap: () {
                                setModalState(() {
                                  if (isSelected) {
                                    selectedIds.remove(partner['_id']);
                                  } else {
                                    selectedIds.add(partner['_id']);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? accentColor.withOpacity(0.04) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    // Custom Avatar
                                    Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: accentColor.withOpacity(0.12),
                                          backgroundImage: partner['profileImage'] != null && partner['profileImage'].toString().isNotEmpty
                                              ? NetworkImage(partner['profileImage'])
                                              : null,
                                          child: partner['profileImage'] == null || partner['profileImage'].toString().isEmpty
                                              ? Text(
                                                  firstLetter,
                                                  style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 16),
                                                )
                                              : null,
                                        ),
                                        if (isSelected)
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: accentColor,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: modalBg, width: 1.5),
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    // User details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            partner['name'] ?? '',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '@${partner['username'] ?? ''} • ${partner['role'].toString().toUpperCase()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: subTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Checkmark trailing selector
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? accentColor : (isDark ? Colors.white24 : Colors.black26),
                                          width: 2,
                                        ),
                                        color: isSelected ? accentColor : Colors.transparent,
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }(),
                    ),
                  ],
                ),

                // Floating Next/Confirm Button inside the Dialog
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: FloatingActionButton(
                    onPressed: (selectedIds.isNotEmpty && !isSaving)
                        ? () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a group name'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              return;
                            }
                            setModalState(() {
                              isSaving = true;
                            });

                            final res = await _groupChatService.createGroup(
                              name: name,
                              memberIds: selectedIds,
                            );

                            setModalState(() {
                              isSaving = false;
                            });

                            if (res['success'] == true) {
                              Navigator.pop(context);
                              _onRefresh();
                              if (res['group'] != null && res['group']['_id'] != null) {
                                _socketService.socket?.emit('group:notify', {
                                  'groupId': res['group']['_id'],
                                  'event': 'created',
                                });
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['error'] ?? 'Error creating group'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        : null,
                    backgroundColor: selectedIds.isNotEmpty ? accentColor : (isDark ? const Color(0xFF1E2A3C) : Colors.grey[300]),
                    foregroundColor: selectedIds.isNotEmpty ? Colors.white : (isDark ? Colors.white30 : Colors.black26),
                    elevation: selectedIds.isNotEmpty ? 4 : 0,
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward_rounded, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _getEffectiveProfileImage(CallUser user) {
    if (user.profileImage != null && user.profileImage!.isNotEmpty) {
      return user.profileImage;
    }
    // Fallback: search in partners list
    try {
      final partner = _partners.firstWhere(
        (p) => p['_id'] == user.id || p['id'] == user.id,
        orElse: () => null,
      );
      if (partner != null && partner['profileImage'] != null && partner['profileImage'].toString().isNotEmpty) {
        return partner['profileImage'].toString();
      }
    } catch (e) {
      // Ignore
    }
    return null;
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
                    AuthService().getFullUrl(effectiveImage) ?? '',
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

  int _getGroupUnreadCount(Map group) {
    if (group['unreadCounts'] != null && _currentUserId != null) {
      final map = group['unreadCounts'] as Map;
      return (map[_currentUserId] ?? 0) as int;
    }
    if (group['unreadCount'] != null) {
      return (group['unreadCount'] as int);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waTeal = const Color(0xFF00A884);
    final Color waGrey = isDark ? const Color(0xFF8696A0) : Colors.black54;

    return AdminLayout(
      showBottomNav: false,
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
                if (_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + _getGroupUnreadCount(g)) > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? waTeal : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) + _groups.fold<int>(0, (sum, g) => sum + _getGroupUnreadCount(g))}',
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
          const Tab(text: 'STATUS'),
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_tabController.index == 1) ...[
            FloatingActionButton(
              heroTag: 'fab_text_status',
              onPressed: () {
                _statusTabKey.currentState?.pickAndUploadStatus(initialMode: 'TEXT');
              },
              backgroundColor: const Color(0xFF1F2C34),
              mini: true,
              elevation: 4,
              child: const Icon(Icons.edit, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'fab_main',
            onPressed: () {
              if (_tabController.index == 0) {
                _showMessageDialog(context);
              } else if (_tabController.index == 1) {
                _statusTabKey.currentState?.pickAndUploadStatus(initialMode: 'PHOTO');
              } else {
                _showCallDialog(context);
              }
            },
            backgroundColor: waTeal,
            elevation: 4,
            child: Icon(
              _tabController.index == 0
                  ? Icons.message
                  : (_tabController.index == 1 ? Icons.camera_alt : Icons.add_call),
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
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
            
            // Status Tab
            StatusTabContent(key: _statusTabKey, isAdmin: true),
            
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
    // Separate groups and individual conversations
    var filteredConversations = _conversations;
    var filteredGroups = _groups;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredConversations = filteredConversations.where((conv) {
        final otherParticipant = conv.participants.firstWhere(
          (p) => p.id != _currentUserId,
          orElse: () => conv.participants.first,
        );
        return otherParticipant.name.toLowerCase().contains(query);
      }).toList();

      filteredGroups = filteredGroups.where((g) {
        return (g['name'] ?? '').toString().toLowerCase().contains(query);
      }).toList();
    }

    // Sort conversations by last updated
    filteredConversations.sort((a, b) {
      DateTime da = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime db = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    // Sort groups by last updated or last message timestamp
    filteredGroups.sort((a, b) {
      final aMsg = a['lastMessage'];
      final bMsg = b['lastMessage'];
      final String aTimeStr = a['updatedAt'] ?? aMsg?['timestamp'] ?? '';
      final String bTimeStr = b['updatedAt'] ?? bMsg?['timestamp'] ?? '';
      
      DateTime da = DateTime.tryParse(aTimeStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime db = DateTime.tryParse(bTimeStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    if (filteredConversations.isEmpty && filteredGroups.isEmpty) {
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

    final TextStyle headerStyle = TextStyle(
      color: isDark ? const Color(0xFF8A939B) : Colors.grey[600],
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.3,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // ── GROUPS Section (Collapsible Accordion) ──
        if (filteredGroups.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isGroupsExpanded = !_isGroupsExpanded;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('GROUPS', style: headerStyle),
                    Icon(
                      _isGroupsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: isDark ? const Color(0xFF8A939B) : Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredGroups.length,
              separatorBuilder: (context, index) =>
                  Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
              itemBuilder: (context, index) {
                final group = filteredGroups[index] as Map;
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
                      backgroundImage: (group['profileImage'] != null && group['profileImage'].toString().isNotEmpty)
                          ? NetworkImage(AuthService().getFullUrl(group['profileImage'].toString())!)
                          : null,
                      child: (group['profileImage'] == null || group['profileImage'].toString().isEmpty)
                          ? Icon(Icons.groups, size: 28, color: isDark ? Colors.white70 : Colors.grey[600])
                          : null,
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
                            color: _getGroupUnreadCount(group) > 0 ? const Color(0xFF25D366) : Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_getGroupUnreadCount(group) > 0)
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: const BoxDecoration(
                              color: Color(0xFF25D366),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${_getGroupUnreadCount(group)}',
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
                          builder: (context) => GroupChatPage(groupId: group['_id'], name: group['name']),
                        ),
                      );
                      if (mounted) _loadData(silent: true);
                    },
                  ),
                );
              },
            ),
            crossFadeState: _isGroupsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 8),
        ],

        // ── DIRECT MESSAGES Section ──
        if (filteredConversations.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
              child: Text('DIRECT MESSAGES', style: headerStyle),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredConversations.length,
            separatorBuilder: (context, index) =>
                Divider(color: isDark ? const Color(0xFF1F2C34) : Colors.black12, thickness: 0.2, height: 1, indent: 85),
            itemBuilder: (context, index) {
              final conversation = filteredConversations[index];
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
                      backgroundImage: (otherParticipant.profileImage != null && otherParticipant.profileImage!.isNotEmpty)
                          ? NetworkImage(AuthService().getFullUrl(otherParticipant.profileImage)!)
                          : null,
                      child: (otherParticipant.profileImage == null || otherParticipant.profileImage!.isEmpty)
                          ? Text(
                              otherParticipant.name.isNotEmpty ? otherParticipant.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 22, color: Color(0xFF1A73E8), fontWeight: FontWeight.bold),
                            )
                          : null,
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
                        avatar: AuthService().getFullUrl(otherParticipant.profileImage) ?? '',
                        conversationId: conversation.id,
                        receiverId: otherParticipant.id,
                      ),
                    ),
                  );
                  if (mounted) _loadData(silent: true);
                },
              );
            },
          ),
        ],
      ],
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
