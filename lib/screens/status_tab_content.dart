import 'package:flutter/material.dart';
import 'status_view_widget.dart';
import 'create_status_screen.dart';
import '../models/status_model.dart';
import '../services/status_service.dart';
import '../services/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class StatusTabContent extends StatefulWidget {
  final bool isAdmin;
  const StatusTabContent({super.key, required this.isAdmin});

  @override
  StatusTabContentState createState() => StatusTabContentState();
}

class StatusTabContentState extends State<StatusTabContent> {
  final StatusService _statusService = StatusService();
  final AuthService _authService = AuthService();
  List<UserStatuses> _allStatuses = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final statuses = await _statusService.getStatuses();
      final user = await _authService.getUser();
      if (mounted) {
        setState(() {
          _allStatuses = statuses;
          _currentUser = user;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      print('❌ [StatusTabContent] Error loading data: $e\n$stack');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load status updates: $e')),
        );
      }
    }
  }

  Future<void> pickAndUploadStatus({String initialMode = 'TEXT'}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateStatusScreen(initialMode: initialMode),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  void _viewStory(UserStatuses userStatus) {
    final int userIndex = _allStatuses.indexOf(userStatus);
    if (userIndex == -1) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomStatusView(
          allUserStatuses: _allStatuses,
          initialUserIndex: userIndex,
          onComplete: () => Navigator.pop(context),
        ),
      ),
    );
    
    for (var s in userStatus.statuses) {
      if (_currentUser != null && !s.viewers.contains(_currentUser!['id'])) {
        _statusService.viewStatus(s.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          if (widget.isAdmin) _buildMyStatusTile(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Recent updates', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ..._allStatuses.map((us) => _buildUserStatusTile(us)).toList(),
        ],
      ),
    );
  }

  Widget _buildMyStatusTile() {
    final myStatus = _allStatuses.firstWhere(
      (us) => us.user.id == _currentUser?['id'] || us.user.id == _currentUser?['_id'],
      orElse: () => UserStatuses(user: StatusUser(id: '', name: 'My Status', role: 'admin'), statuses: []),
    );

    return ListTile(
      onTap: myStatus.statuses.isNotEmpty ? () => _viewStory(myStatus) : pickAndUploadStatus,
      leading: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: myStatus.statuses.isNotEmpty 
                  ? Border.all(color: const Color(0xFF00A884), width: 2)
                  : null,
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundImage: AuthService.getProfileImage(_currentUser) != null
                  ? NetworkImage(_authService.getFullUrl(AuthService.getProfileImage(_currentUser))!)
                  : null,
              child: AuthService.getProfileImage(_currentUser) == null 
                  ? const Icon(Icons.person) 
                  : null,
            ),
          ),
          if (myStatus.statuses.isEmpty)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
      title: const Text('My status', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(myStatus.statuses.isNotEmpty 
          ? 'Tap to view status' 
          : 'Tap to add status update'),
    );
  }

  Widget _buildUserStatusTile(UserStatuses us) {
    if (us.user.id == _currentUser?['id'] || us.user.id == _currentUser?['_id']) {
      return const SizedBox.shrink();
    }

    return ListTile(
      onTap: () => _viewStory(us),
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF00A884), width: 2),
        ),
        child: CircleAvatar(
          radius: 25,
          backgroundImage: us.user.profileImage != null
              ? NetworkImage(_authService.getFullUrl(us.user.profileImage)!)
              : null,
          child: us.user.profileImage == null ? Text(us.user.name[0]) : null,
        ),
      ),
      title: Text(us.user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(us.statuses.isNotEmpty
          ? DateFormat('hh:mm a').format(us.statuses.last.createdAt)
          : ''),
    );
  }
}
