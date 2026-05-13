import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/chat/chat_service.dart';

class ChatProfileScreen extends StatefulWidget {
  final String name;
  final String? avatar;
  final bool isOnline;

  const ChatProfileScreen({
    super.key, 
    required this.name, 
    this.avatar, 
    this.isOnline = false
  });

  @override
  State<ChatProfileScreen> createState() => _ChatProfileScreenState();
}

class _ChatProfileScreenState extends State<ChatProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  final ChatService _chatService = ChatService();
  String? _currentAvatar;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _currentAvatar = widget.avatar;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() => _isUploading = true);
        
        // Upload the image using the existing ChatService media upload
        final result = await _chatService.uploadMedia(image.path);
        
        if (result['success'] == true) {
          setState(() {
            _currentAvatar = result['url'];
            _isUploading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile image updated successfully')),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating image: $e')),
        );
      }
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color bgColor = isDark ? const Color(0xFF111B21) : Colors.white;
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Profile Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPickerOption(Icons.camera_alt, 'Camera', ImageSource.camera),
                  _buildPickerOption(Icons.photo_library, 'Gallery', ImageSource.gallery),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPickerOption(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _pickImage(source);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF00A884), size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 80,
                  backgroundColor: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Color(0xFF00A884))
                      : _currentAvatar != null && _currentAvatar!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(80),
                              child: Image.network(_currentAvatar!, fit: BoxFit.cover, width: 160, height: 160),
                            )
                          : Text(
                              widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                              style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: isDark ? Colors.white24 : Colors.black12),
                            ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: GestureDetector(
                    onTap: _showPickerOptions,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00A884),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                if (widget.isOnline)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: bgColor, width: 3)
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              widget.name,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                color: widget.isOnline ? const Color(0xFF25D366) : subTextColor, 
                fontSize: 16, 
                fontWeight: FontWeight.w500
              ),
            ),
          ],
        ),
      ),
    );
  }
}
