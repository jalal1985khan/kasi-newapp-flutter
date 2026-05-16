import 'package:flutter/material.dart';
import '../../services/chat/group_chat_service.dart';
import '../../services/chat/chat_service.dart';
import '../../services/auth_service.dart';

class GroupInfoPage extends StatefulWidget {
  final String groupId;
  final bool isAdmin;

  const GroupInfoPage({super.key, required this.groupId, this.isAdmin = false});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  final GroupChatService _groupChatService = GroupChatService();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _group;
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadGroupDetails();
  }

  Future<void> _loadGroupDetails() async {
    final user = await _authService.getUser();
    _currentUserId = user?['id'] ?? user?['_id'];

    final res = await _groupChatService.getGroupDetails(widget.groupId);
    if (mounted && res['success']) {
      setState(() {
        _group = res['group'];
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _renameGroup() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white38 : Colors.black54;

    final controller = TextEditingController(text: _group?['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Rename Group', style: TextStyle(color: textColor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'New group name',
            hintStyle: TextStyle(color: subTextColor),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00A884))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: subTextColor))),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              final res = await _groupChatService.renameGroup(widget.groupId, newName);
              if (res['success']) {
                _loadGroupDetails();
                if (!mounted) return;
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _addMembers() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white38 : Colors.black54;

    final partners = await _chatService.getPartners();
    if (!mounted) return;

    final existingMemberIds = (_group?['members'] as List?)?.map((m) => m['userId']['_id']).toSet() ?? {};
    final List<String> selectedIds = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(color: modalBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Add Members', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                    TextButton(
                      onPressed: selectedIds.isNotEmpty
                          ? () async {
                              final res = await _groupChatService.addMembers(widget.groupId, selectedIds);
                              if (res['success']) {
                                Navigator.pop(context);
                                _loadGroupDetails();
                              }
                            }
                          : null,
                      child: Text('Add', style: TextStyle(color: selectedIds.isNotEmpty ? const Color(0xFF00A884) : subTextColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: ListView.builder(
                  itemCount: partners.length,
                  itemBuilder: (context, index) {
                    final partner = partners[index];
                    final String id = partner['_id'];
                    if (existingMemberIds.contains(id)) return const SizedBox.shrink();
                    final isSelected = selectedIds.contains(id);
                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: const Color(0xFF00A884),
                      checkColor: Colors.white,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) selectedIds.add(id); else selectedIds.remove(id);
                        });
                      },
                      title: Text(partner['name'], style: TextStyle(color: textColor)),
                      subtitle: Text(partner['role'].toString().toUpperCase(), style: TextStyle(color: subTextColor, fontSize: 12)),
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

  void _removeMember(String memberId, String name) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Remove Member', style: TextStyle(color: textColor)),
        content: Text('Remove $name from the group?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: subTextColor))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _groupChatService.removeMember(widget.groupId, memberId);
      if (res['success']) _loadGroupDetails();
    }
  }

  void _deleteGroup() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Delete Group', style: TextStyle(color: textColor)),
        content: Text('This will delete the group for everyone. Are you sure?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: subTextColor))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _groupChatService.deleteGroup(widget.groupId);
      if (res['success']) {
        if (!mounted) return;
        Navigator.pop(context, 'deleted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white38 : Colors.black54;
    const Color waTeal = Color(0xFF00A884);

    if (_isLoading) return Scaffold(backgroundColor: bgColor, body: const Center(child: CircularProgressIndicator(color: waTeal)));
    if (_group == null) return Scaffold(backgroundColor: bgColor, body: Center(child: Text('Group not found', style: TextStyle(color: textColor))));

    final members = (_group?['members'] as List?) ?? [];
    final isAdmin = _group?['createdBy'] == _currentUserId;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        title: Text('Group Info', style: TextStyle(color: textColor)),
        iconTheme: IconThemeData(color: textColor),
        actions: [
          if (isAdmin) IconButton(icon: const Icon(Icons.edit), onPressed: _renameGroup),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroupDetails,
        color: waTeal,
        backgroundColor: isDark ? const Color(0xFF202C33) : Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 32),
              CircleAvatar(
                radius: 50,
                backgroundColor: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                backgroundImage: (_group != null && _group!['profileImage'] != null && _group!['profileImage'].toString().isNotEmpty)
                    ? NetworkImage(_group!['profileImage'])
                    : null,
                child: (_group == null || _group!['profileImage'] == null || _group!['profileImage'].toString().isEmpty)
                    ? Icon(Icons.groups, size: 50, color: isDark ? Colors.white54 : Colors.grey[400])
                    : null,
              ),
              const SizedBox(height: 16),
              Text(_group?['name'] ?? '', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
              Text('${members.length} members', style: TextStyle(color: subTextColor)),
              const SizedBox(height: 32),

              if (isAdmin)
                ListTile(
                  leading: const CircleAvatar(backgroundColor: waTeal, child: Icon(Icons.person_add, color: Colors.white, size: 20)),
                  title: const Text('Add Members', style: TextStyle(color: waTeal, fontWeight: FontWeight.bold)),
                  onTap: _addMembers,
                ),

              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Align(alignment: Alignment.centerLeft, child: Text('MEMBERS', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00A884), fontSize: 12, letterSpacing: 1))),
              ),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  final userData = member['userId'];
                  final String role = member['role'];
                  final String name = userData['name'];
                  final String id = userData['_id'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                      backgroundImage: (userData != null && userData['profileImage'] != null && userData['profileImage'].toString().isNotEmpty)
                          ? NetworkImage(userData['profileImage'])
                          : null,
                      child: (userData == null || userData['profileImage'] == null || userData['profileImage'].toString().isEmpty)
                          ? Text(name[0].toUpperCase(), style: TextStyle(color: isDark ? Colors.white70 : Colors.black45))
                          : null,
                    ),
                    title: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                    subtitle: Text(role.toUpperCase(), style: TextStyle(color: subTextColor, fontSize: 11)),
                    trailing: (isAdmin && id != _currentUserId)
                        ? IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20), onPressed: () => _removeMember(id, name))
                        : (id == _group?['createdBy'] ? Text('Owner', style: TextStyle(color: subTextColor.withOpacity(0.5), fontSize: 11)) : null),
                  );
                },
              ),

              if (isAdmin) ...[
                Divider(color: isDark ? Colors.white10 : Colors.black12, height: 48),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Delete Group', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onTap: _deleteGroup,
                ),
              ],
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
