import 'package:flutter/material.dart';
import 'status_view_widget.dart';
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
    final statuses = await _statusService.getStatuses();
    final user = await _authService.getUser();
    if (mounted) {
      setState(() {
        _allStatuses = statuses;
        _currentUser = user;
        _isLoading = false;
      });
    }
  }

  Future<void> pickAndUploadStatus() async {
    // Show options for Image, Video or Text
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
          ],
        ),
      ),
    );

    if (type == null) return;

    if (type == 'text') {
      _showTextStatusDialog();
    } else {
      _pickMedia(type);
    }
  }

  Future<void> _pickMedia(String type) async {
    final ImagePicker picker = ImagePicker();
    XFile? file;
    
    if (type == 'image') {
      file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    } else {
      file = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    }
    
    if (file == null) return;

    if (mounted) setState(() => _isLoading = true);
    final uploadResult = await _authService.uploadProfileImage(file.path);
    
    if (uploadResult['success'] == true) {
      final String mediaUrl = uploadResult['url'];
      await _statusService.createStatus(
        content: mediaUrl,
        type: type,
        caption: '',
      );
      _loadData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${uploadResult['message']}')));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTextStatusDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Text Status'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Type something...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              await _statusService.createStatus(
                content: controller.text,
                type: 'text',
              );
              _loadData();
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }

  void _viewStory(UserStatuses userStatus) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomStatusView(
          statuses: userStatus.statuses,
          userName: userStatus.user.name,
          userAvatar: userStatus.user.profileImage,
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
      subtitle: Text(DateFormat('hh:mm a').format(us.statuses.last.createdAt)),
    );
  }
}
