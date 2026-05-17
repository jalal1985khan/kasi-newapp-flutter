import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/status_service.dart';
import '../services/auth_service.dart';

class CreateStatusScreen extends StatefulWidget {
  final String initialMode; // 'TEXT', 'PHOTO', 'VIDEO'
  const CreateStatusScreen({super.key, this.initialMode = 'TEXT'});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final StatusService _statusService = StatusService();
  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker();

  late String _currentMode;
  File? _mediaFile;
  VideoPlayerController? _videoController;
  
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  int _colorIndex = 0;
  int _fontIndex = 0;
  bool _isUploading = false;

  // Premium Curated WhatsApp Background Colors for Text Status
  final List<Color> _backgroundColors = [
    const Color(0xFFC29BC8), // Premium Lavender (matching user screenshot)
    const Color(0xFF075E54), // WhatsApp Dark Teal
    const Color(0xFF128C7E), // WhatsApp Light Teal
    const Color(0xFF1F2C34), // Gunmetal Blue
    const Color(0xFF8B1E3F), // Deep Burgundy
    const Color(0xFF2C5E3B), // Emerald Forest
    const Color(0xFFB35416), // Terracotta Orange
    const Color(0xFF4A3E3D), // Soft Charcoal
  ];

  // Curated Premium Text Styles
  final List<TextStyle> _fontStyles = [
    const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold),
    const TextStyle(fontFamily: 'serif', fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
    const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
  ];

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    if (_currentMode != 'TEXT') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickMedia();
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _textController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    try {
      XFile? pickedFile;
      if (_currentMode == 'PHOTO') {
        pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
      } else if (_currentMode == 'VIDEO') {
        pickedFile = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
      }

      if (pickedFile == null) {
        // If they cancel and have no media, fall back to TEXT mode
        if (_mediaFile == null) {
          setState(() {
            _currentMode = 'TEXT';
          });
        }
        return;
      }

      setState(() {
        _mediaFile = File(pickedFile!.path);
      });

      if (_currentMode == 'VIDEO') {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(_mediaFile!)..initialize().then((_) {
          setState(() {});
          _videoController?.setLooping(true);
          _videoController?.play();
        });
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
    }
  }

  Future<void> _handleSend() async {
    if (_isUploading) return;

    if (_currentMode == 'TEXT') {
      final textContent = _textController.text.trim();
      if (textContent.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please type something for your status update.')),
        );
        return;
      }

      setState(() => _isUploading = true);
      try {
        final success = await _statusService.createStatus(
          content: textContent,
          type: 'text',
          caption: '', // No caption for plain text status
        );

        if (success) {
          if (mounted) Navigator.pop(context, true);
        } else {
          throw Exception('Backend creation failed');
        }
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to publish text status: $e')),
          );
        }
      }
    } else {
      if (_mediaFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a photo or video to upload.')),
        );
        return;
      }

      setState(() => _isUploading = true);
      try {
        // 1. Upload media to Cloudinary/Backend storage
        final uploadResult = await _authService.uploadProfileImage(_mediaFile!.path);
        
        if (uploadResult['success'] == true) {
          final String mediaUrl = uploadResult['url'];
          
          // 2. Create the status post
          final success = await _statusService.createStatus(
            content: mediaUrl,
            type: _currentMode == 'PHOTO' ? 'image' : 'video',
            caption: _captionController.text.trim(),
          );

          if (success) {
            if (mounted) Navigator.pop(context, true);
          } else {
            throw Exception('Backend status creation failed');
          }
        } else {
          throw Exception(uploadResult['message'] ?? 'Upload failed');
        }
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload status update: $e')),
          );
        }
      }
    }
  }

  void _switchMode(String newMode) {
    if (_isUploading) return;
    if (newMode == 'VOICE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice status option coming soon!')),
      );
      return;
    }

    setState(() {
      _currentMode = newMode;
      if (newMode == 'TEXT') {
        _mediaFile = null;
        _videoController?.dispose();
        _videoController = null;
      } else {
        _mediaFile = null;
        _videoController?.dispose();
        _videoController = null;
        _pickMedia();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTextMode = _currentMode == 'TEXT';
    
    return Scaffold(
      backgroundColor: isTextMode ? _backgroundColors[_colorIndex] : Colors.black,
      body: Stack(
        children: [
          // ── Background / Media Preview Area ──────────────────────────────
          Positioned.fill(
            child: isTextMode 
              ? _buildTextEditor()
              : _buildMediaPreview(),
          ),

          // ── Top Action Bar ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close button (X)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black25,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 26),
                  ),
                ),
                
                // Text Styling actions (Only visible in TEXT mode)
                if (isTextMode)
                  Row(
                    children: [
                      // Font changer
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _fontIndex = (_fontIndex + 1) % _fontStyles.length;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: Colors.black25,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Aa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      
                      // Background palette changer
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _colorIndex = (_colorIndex + 1) % _backgroundColors.length;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black25,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.palette, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Bottom Area Controls (Caption & Mode Selector) ───────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caption bar & Privacy card (Only for PHOTO & VIDEO modes)
                  if (!isTextMode && _mediaFile != null)
                    _buildCaptionAndSendRow(),

                  // Text send button (Only for TEXT mode)
                  if (isTextMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20, bottom: 20),
                        child: FloatingActionButton(
                          onPressed: _handleSend,
                          backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ),

                  // Mode Selector Tabs (Exactly matching user screenshot)
                  _buildModeSelectorTabs(),
                ],
              ),
            ),
          ),

          // ── Loading Layer ────────────────────────────────────────────────
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.green),
                        SizedBox(height: 16),
                        Text('Publishing status update...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextEditor() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: TextField(
          controller: _textController,
          textAlign: TextAlign.center,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: _fontStyles[_fontIndex].copyWith(
            color: Colors.white,
            fontSize: 32,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            hintText: 'Type a status',
            hintStyle: TextStyle(color: Colors.white54, fontSize: 32),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_mediaFile == null) {
      return Center(
        child: GestureDetector(
          onTap: _pickMedia,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _currentMode == 'PHOTO' ? Icons.add_a_photo : Icons.video_call,
                  color: Colors.white70,
                  size: 50,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                'Tap to select a ${_currentMode.toLowerCase()}',
                style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentMode == 'PHOTO') {
      return InteractiveViewer(
        child: Image.file(
          _mediaFile!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else if (_currentMode == 'VIDEO') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        );
      } else {
        return const Center(child: CircularProgressIndicator(color: Colors.green));
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildCaptionAndSendRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
      child: Column(
        children: [
          // 1. Caption input container (exactly matching screenshot shape)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2C34), // Premium dark theme background matching whatsapp
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                // Plus icon inside the caption box
                const Icon(Icons.add, color: Colors.white70, size: 24),
                const SizedBox(width: 8),
                
                // Caption text input
                Expanded(
                  child: TextField(
                    controller: _captionController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Add a caption...',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                ),
                
                // @ Mention icon inside caption box
                const Icon(Icons.alternate_email, color: Colors.white70, size: 20),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          // 2. Privacy label & Send Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left rounded card: Status (Contacts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2C34),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.autorenew, color: Colors.white70, size: 16),
                    SizedBox(width: 6),
                    Text('Status (Contacts)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              // Right green circular Send Button
              GestureDetector(
                onTap: _handleSend,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00A884), // Premium WhatsApp green color
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelectorTabs() {
    final modes = ['VIDEO', 'PHOTO', 'TEXT', 'VOICE'];
    
    return Container(
      color: Colors.black.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: modes.map((mode) {
          final isSelected = _currentMode == mode;
          return GestureDetector(
            onTap: () => _switchMode(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                mode,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFE5A93C) : Colors.white60, // highlighted highlighted color matching user screenshot
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
