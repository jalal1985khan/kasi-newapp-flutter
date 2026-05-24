import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../services/chat/group_chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/dio_client.dart';

class GroupInfoPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> members;
  final void Function(String name, List<Map<String, dynamic>> members)? onGroupUpdated;

  const GroupInfoPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.members,
    this.onGroupUpdated,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  final GroupChatService _service = GroupChatService();
  final AuthService _auth = AuthService();
  final SocketService _socket = SocketService();

  late String _groupName;
  late List<Map<String, dynamic>> _members;
  bool _isLoading = false;
  String? _currentUserId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
    _members = List.from(widget.members);
    _loadCurrentUser();
    if (_members.isEmpty) _fetchDetails();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _auth.getUser();
    if (mounted) {
      setState(() {
        _currentUserId = user?['id'] ?? user?['_id'];
        _userRole = user?['role'];
      });
    }
  }

  Future<void> _fetchDetails() async {
    setState(() => _isLoading = true);
    final res = await _service.getGroupDetails(widget.groupId);
    if (!mounted) return;
    setState(() => _isLoading = false);
    final group = res['group'] as Map<String, dynamic>? ?? {};
    final rawMembers = group['members'] as List? ?? [];
    setState(() {
      _groupName = group['name']?.toString() ?? _groupName;
      _members = rawMembers.map<Map<String, dynamic>>((m) {
        final u = m['userId'] as Map<String, dynamic>? ?? {};
        return {
          'userId': u['_id']?.toString() ?? m['userId']?.toString() ?? '',
          'name': u['name']?.toString() ?? 'Member',
          'role': m['role']?.toString() ?? 'member',
          'profileImage': u['profileImage']?.toString(),
          'email': u['email']?.toString(),
        };
      }).toList();
    });
  }

  bool get _isAdmin =>
      _userRole == 'admin' || _userRole == 'super_admin';

  Future<void> _renameGroup() async {
    final ctrl = TextEditingController(text: _groupName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _groupName) return;
    final res = await _service.renameGroup(widget.groupId, newName);
    if (res['success'] == true && mounted) {
      setState(() => _groupName = newName);
      widget.onGroupUpdated?.call(_groupName, _members);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group renamed')));
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final memberId = member['userId']?.toString() ?? '';
    final name = member['name']?.toString() ?? 'Member';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $name from the group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await _service.removeMember(widget.groupId, memberId);
    if (res['success'] == true && mounted) {
      setState(() => _members.removeWhere((m) => m['userId'] == memberId));
      widget.onGroupUpdated?.call(_groupName, _members);
      _socket.emit('group:member:removed', {
        'groupId': widget.groupId,
        'memberId': memberId,
      });
    }
  }

  Future<void> _addMembers() async {
    // Fetch available employees/partners
    final res = await _service.getGroupDetails(widget.groupId);
    // Navigate to a member picker — show all partners not already in group
    final currentIds = _members.map((m) => m['userId']?.toString()).toSet();

    final picked = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _MemberPickerPage(
          currentMemberIds: currentIds.whereType<String>().toList(),
        ),
      ),
    );

    if (picked == null || picked.isEmpty) return;

    setState(() => _isLoading = true);
    final addRes = await _service.addMembers(widget.groupId, picked);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (addRes['success'] == true) {
      _socket.emit('group:members:added', {
        'groupId': widget.groupId,
        'memberIds': picked,
      });
      await _fetchDetails();
      widget.onGroupUpdated?.call(_groupName, _members);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Members added successfully')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(addRes['error']?.toString() ?? 'Failed to add members')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final cardBg = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF202C33) : const Color(0xFF075E54),
        title: const Text('Group Info',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: _renameGroup,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : ListView(
              children: [
                // Group header
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.symmetric(
                      vertical: 24, horizontal: 20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFF00A884),
                        child: Text(
                          _groupName.isNotEmpty
                              ? _groupName[0].toUpperCase()
                              : 'G',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _groupName,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _renameGroup,
                              child: const Icon(Icons.edit,
                                  size: 18, color: Color(0xFF00A884)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_members.length} members',
                        style: TextStyle(color: subColor, fontSize: 14),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Members section
                Container(
                  color: cardBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              '${_members.length} members',
                              style: TextStyle(
                                  color: const Color(0xFF00A884),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            if (_isAdmin)
                              GestureDetector(
                                onTap: _addMembers,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00A884)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.person_add,
                                          size: 16,
                                          color: Color(0xFF00A884)),
                                      SizedBox(width: 4),
                                      Text('Add',
                                          style: TextStyle(
                                              color: Color(0xFF00A884),
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ..._members.map((member) {
                        final memberId = member['userId']?.toString() ?? '';
                        final name = member['name']?.toString() ?? 'Member';
                        final role = member['role']?.toString() ?? 'member';
                        final imageUrl =
                            member['profileImage']?.toString();
                        final isCurrentUser = memberId == _currentUserId;
                        final isHidden = role == 'super_admin' || role == 'hidden';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF00A884),
                            backgroundImage: imageUrl != null &&
                                    imageUrl.isNotEmpty
                                ? NetworkImage(
                                    AuthService().getFullUrl(imageUrl) ??
                                        imageUrl)
                                : null,
                            child: (imageUrl == null || imageUrl.isEmpty)
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'M',
                                    style: const TextStyle(color: Colors.white))
                                : null,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(name,
                                    style: TextStyle(color: textColor)),
                              ),
                              if (isCurrentUser)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text('You',
                                      style: TextStyle(
                                          color: Color(0xFF00A884),
                                          fontSize: 12)),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            isHidden
                                ? 'Super Admin'
                                : role == 'admin'
                                    ? 'Group Admin'
                                    : role == 'employee'
                                        ? 'Member'
                                        : role,
                            style: TextStyle(
                                color: role == 'admin' || isHidden
                                    ? const Color(0xFF00A884)
                                    : subColor,
                                fontSize: 12),
                          ),
                          trailing: (_isAdmin &&
                                  !isCurrentUser &&
                                  !isHidden)
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle,
                                      color: Colors.red, size: 20),
                                  onPressed: () =>
                                      _removeMember(member),
                                )
                              : null,
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Danger zone
                if (_isAdmin)
                  Container(
                    color: cardBg,
                    child: ListTile(
                      leading: const Icon(Icons.delete_forever,
                          color: Colors.red),
                      title: const Text('Delete Group',
                          style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete Group'),
                            content: const Text(
                                'This will permanently delete the group and all messages.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Delete',
                                      style: TextStyle(
                                          color: Colors.white))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _service.deleteGroup(widget.groupId);
                          if (mounted) {
                            Navigator.popUntil(
                                context, (r) => r.isFirst || r.settings.name == '/chat');
                          }
                        }
                      },
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemberPickerPage — pick users to add to the group
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPickerPage extends StatefulWidget {
  final List<String> currentMemberIds;

  const _MemberPickerPage({required this.currentMemberIds});

  @override
  State<_MemberPickerPage> createState() => _MemberPickerPageState();
}

class _MemberPickerPageState extends State<_MemberPickerPage> {
  final AuthService _auth = AuthService();
  List<Map<String, dynamic>> _allUsers = [];
  final Set<String> _selected = {};
  bool _isLoading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      // Use chat partners endpoint to get all available users
      final token = await _auth.getAccessToken();
      final dio = DioClient().dio;
      final res = await dio.get(
        'api/chat/partners',
        options: Options(headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }),
      );
      final partners = res.data['partners'] as List? ?? [];
      if (mounted) {
        setState(() {
          _allUsers = partners
              .map<Map<String, dynamic>>((p) => {
                    'id': p['_id']?.toString() ?? '',
                    'name': p['name']?.toString() ?? 'User',
                    'role': p['role']?.toString() ?? 'employee',
                    'profileImage': p['profileImage']?.toString(),
                  })
              .where((u) => !widget.currentMemberIds.contains(u['id']))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _allUsers;
    return _allUsers
        .where((u) =>
            (u['name'] as String).toLowerCase().contains(_search.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF202C33) : const Color(0xFF075E54),
        title: const Text('Add Members',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: Text('Add (${_selected.length})',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search members',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1F2C34)
                    : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF00A884)))
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final user = _filtered[i];
                      final id = user['id'] as String;
                      final name = user['name'] as String;
                      final imageUrl = user['profileImage'] as String?;
                      final isSelected = _selected.contains(id);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF00A884),
                          backgroundImage:
                              imageUrl != null && imageUrl.isNotEmpty
                                  ? NetworkImage(
                                      AuthService().getFullUrl(imageUrl) ??
                                          imageUrl)
                                  : null,
                          child: (imageUrl == null || imageUrl.isEmpty)
                              ? Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                      color: Colors.white))
                              : null,
                        ),
                        title: Text(name),
                        subtitle: Text(user['role'] as String),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: const Color(0xFF00A884),
                          onChanged: (_) => setState(() {
                            if (isSelected) {
                              _selected.remove(id);
                            } else {
                              _selected.add(id);
                            }
                          }),
                        ),
                        onTap: () => setState(() {
                          if (isSelected) {
                            _selected.remove(id);
                          } else {
                            _selected.add(id);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selected.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF00A884),
              onPressed: () => Navigator.pop(context, _selected.toList()),
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(
                'Add ${_selected.length} member${_selected.length > 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}


