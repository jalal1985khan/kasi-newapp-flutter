import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

class AttachmentPreviewScreen extends StatefulWidget {
  final List<String> filePaths;
  final String userName;

  const AttachmentPreviewScreen({
    super.key,
    required this.filePaths,
    required this.userName,
  });

  @override
  State<AttachmentPreviewScreen> createState() => _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, String> _captions = {};
  final TextEditingController _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _onSend() {
    // Save current caption before sending
    _captions[_currentIndex] = _captionController.text;
    
    final List<Map<String, String>> result = [];
    for (int i = 0; i < widget.filePaths.length; i++) {
      result.add({
        'path': widget.filePaths[i],
        'caption': _captions[i] ?? '',
      });
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color waTeal = Color(0xFF00A884);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.filePaths.length > 1 
              ? '${_currentIndex + 1} of ${widget.filePaths.length}' 
              : widget.userName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.filePaths.length,
              onPageChanged: (index) {
                // Save current caption
                _captions[_currentIndex] = _captionController.text;
                setState(() {
                  _currentIndex = index;
                  // Load next caption
                  _captionController.text = _captions[index] ?? '';
                });
              },
              itemBuilder: (context, index) {
                return _buildFilePreview(widget.filePaths[index]);
              },
            ),
          ),
          _buildInputBar(isDark, waTeal),
        ],
      ),
    );
  }

  Widget _buildFilePreview(String path) {
    final extension = p.extension(path).toLowerCase();
    
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(extension)) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
      );
    } else if (['.mp4', '.mov', '.avi', '.mkv'].contains(extension)) {
      return _VideoPreview(videoPath: path);
    } else {
      return _GenericFilePreview(path: path);
    }
  }

  Widget _buildInputBar(bool isDark, Color waTeal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF202C33),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: TextStyle(color: Colors.white60),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _onSend,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF00A884),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final String videoPath;
  const _VideoPreview({required this.videoPath});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenericFilePreview extends StatelessWidget {
  final String path;
  const _GenericFilePreview({required this.path});

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(path);
    final extension = p.extension(path).toUpperCase().replaceAll('.', '');
    
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: const Color(0xFF202C33),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Color(0xFF00A884), size: 80),
            const SizedBox(height: 20),
            Text(
              fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              extension,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
