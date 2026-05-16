import 'package:flutter/material.dart';
import 'package:story_view/story_view.dart';
import '../models/status_model.dart';
import '../services/status_service.dart';
import '../services/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'admin/admin_common_widgets/admin_layout.dart';
import 'user/common_widgets/user_layout.dart';

class StatusScreen extends StatefulWidget {
  final bool isAdmin;
  const StatusScreen({super.key, required this.isAdmin});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
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
    setState(() => _isLoading = true);
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

  Future<void> _pickAndUploadStatus() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image == null) return;

    // First upload to spaces (reusing existing service if available)
    // For now, let's assume we have a generic upload
    setState(() => _isLoading = true);
    final uploadResult = await _authService.uploadProfileImage(image.path);
    
    if (uploadResult['success'] == true) {
      final String imageUrl = uploadResult['url'];
      await _statusService.createStatus(
        content: imageUrl,
        type: 'image',
        caption: '',
      );
      _loadData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${uploadResult['message']}')));
      }
      setState(() => _isLoading = false);
    }
  }

  void _viewStory(UserStatuses userStatus) {
    final List<StoryItem> items = userStatus.statuses.map((s) {
      if (s.type == 'image') {
        return StoryItem.pageImage(
          url: _authService.getFullUrl(s.content)!,
          controller: StoryController(),
          caption: s.caption != null && s.caption!.isNotEmpty ? s.caption : null,
        );
      } else {
        // Fallback for text or other types
        return StoryItem.text(
          title: s.caption ?? 'Status',
          backgroundColor: Colors.blueGrey,
        );
      }
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryPageView(
          storyItems: items,
          controller: StoryController(),
          onComplete: () => Navigator.pop(context),
          onVerticalSwipeComplete: (direction) {
            if (direction == Direction.down) Navigator.pop(context);
          },
          userProfile: StoryUserProfile(
            name: userStatus.user.name,
            avatarUrl: _authService.getFullUrl(userStatus.user.profileImage),
          ),
        ),
      ),
    );
    
    // Mark as viewed
    for (var s in userStatus.statuses) {
      if (_currentUser != null && !s.viewers.contains(_currentUser!['id'])) {
        _statusService.viewStatus(s.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final content = _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
        : RefreshIndicator(
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

    if (widget.isAdmin) {
      return AdminLayout(
        title: 'Status',
        currentIndex: 5, // We'll add this
        onRefresh: _loadData,
        floatingActionButton: FloatingActionButton(
          onPressed: _pickAndUploadStatus,
          backgroundColor: const Color(0xFF00A884),
          child: const Icon(Icons.camera_alt, color: Colors.white),
        ),
        body: content,
      );
    } else {
      return UserLayout(
        title: 'Status',
        currentIndex: 3, // We'll add this
        onRefresh: _loadData,
        body: content,
      );
    }
  }

  Widget _buildMyStatusTile() {
    final myStatus = _allStatuses.firstWhere(
      (us) => us.user.id == _currentUser?['id'] || us.user.id == _currentUser?['_id'],
      orElse: () => UserStatuses(user: StatusUser(id: '', name: 'My Status', role: 'admin'), statuses: []),
    );

    return ListTile(
      onTap: myStatus.statuses.isNotEmpty ? () => _viewStory(myStatus) : _pickAndUploadStatus,
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
      trailing: myStatus.statuses.isNotEmpty 
          ? IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () {
                // Show options to delete
              },
            )
          : null,
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

class StoryUserProfile {
  final String name;
  final String? avatarUrl;
  StoryUserProfile({required this.name, this.avatarUrl});
}

class StoryPageView extends StatelessWidget {
  final List<StoryItem> storyItems;
  final StoryController controller;
  final VoidCallback? onComplete;
  final Function(Direction?)? onVerticalSwipeComplete;
  final StoryUserProfile userProfile;

  const StoryPageView({
    super.key,
    required this.storyItems,
    required this.controller,
    this.onComplete,
    this.onVerticalSwipeComplete,
    required this.userProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          StoryView(
            storyItems: storyItems,
            controller: controller,
            onComplete: onComplete,
            onVerticalSwipeComplete: onVerticalSwipeComplete,
          ),
          Positioned(
            top: 50,
            left: 15,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: userProfile.avatarUrl != null 
                      ? NetworkImage(userProfile.avatarUrl!) 
                      : null,
                  child: userProfile.avatarUrl == null ? Text(userProfile.name[0]) : null,
                ),
                const SizedBox(width: 10),
                Text(
                  userProfile.name,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Positioned(
            top: 45,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
