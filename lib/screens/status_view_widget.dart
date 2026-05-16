import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/status_model.dart';
import '../services/auth_service.dart';

class CustomStatusView extends StatefulWidget {
  final List<StatusModel> statuses;
  final String userName;
  final String? userAvatar;
  final VoidCallback onComplete;

  const CustomStatusView({
    super.key,
    required this.statuses,
    required this.userName,
    this.userAvatar,
    required this.onComplete,
  });

  @override
  State<CustomStatusView> createState() => _CustomStatusViewState();
}

class _CustomStatusViewState extends State<CustomStatusView> {
  int _currentIndex = 0;
  double _progress = 0.0;
  Timer? _timer;
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;

  @override
  void initState() {
    super.initState();
    _playCurrentStatus();
  }

  void _playCurrentStatus() {
    _timer?.cancel();
    _videoController?.dispose();
    _videoController = null;
    _progress = 0.0;

    final status = widget.statuses[_currentIndex];

    if (status.type == 'video') {
      _isVideoLoading = true;
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_authService.getFullUrl(status.content)!),
      )..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoLoading = false;
              _videoController!.play();
              _startVideoTimer();
            });
          }
        });
    } else {
      _startImageTimer();
    }
  }

  void _startImageTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _progress += 0.01; // 5 seconds
          if (_progress >= 1.0) {
            _nextStatus();
          }
        });
      }
    });
  }

  void _startVideoTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && _videoController != null && _videoController!.value.isInitialized) {
        setState(() {
          _progress = _videoController!.value.position.inMilliseconds /
              _videoController!.value.duration.inMilliseconds;
          if (_progress >= 1.0) {
            _nextStatus();
          }
        });
      }
    });
  }

  void _nextStatus() {
    if (_currentIndex < widget.statuses.length - 1) {
      setState(() {
        _currentIndex++;
        _pageController.jumpToPage(_currentIndex);
        _playCurrentStatus();
      });
    } else {
      _timer?.cancel();
      widget.onComplete();
    }
  }

  void _previousStatus() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _pageController.jumpToPage(_currentIndex);
        _playCurrentStatus();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStatus();
          } else {
            _nextStatus();
          }
        },
        onLongPressStart: (_) {
          _timer?.cancel();
          _videoController?.pause();
        },
        onLongPressEnd: (_) {
          if (widget.statuses[_currentIndex].type == 'video') {
            _videoController?.play();
            _startVideoTimer();
          } else {
            _startImageTimer();
          }
        },
        child: Stack(
          children: [
            // Status Content
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.statuses.length,
              itemBuilder: (context, index) {
                final status = widget.statuses[index];
                if (status.type == 'video') {
                  return Center(
                    child: _videoController != null && _videoController!.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          )
                        : const CircularProgressIndicator(color: Colors.white),
                  );
                } else if (status.type == 'text') {
                  return Container(
                    color: Colors.blueGrey,
                    padding: const EdgeInsets.all(40),
                    alignment: Alignment.center,
                    child: Text(
                      status.content,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  );
                } else {
                  // Image
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _authService.getFullUrl(status.content)!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        },
                      ),
                      if (status.caption != null && status.caption!.isNotEmpty)
                        Positioned(
                          bottom: 50,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.caption!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
                        ),
                    ],
                  );
                }
              },
            ),

            // Top Bar
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: List.generate(widget.statuses.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: LinearProgressIndicator(
                              value: index == _currentIndex
                                  ? _progress
                                  : (index < _currentIndex ? 1.0 : 0.0),
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 2,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: widget.userAvatar != null
                              ? NetworkImage(_authService.getFullUrl(widget.userAvatar)!)
                              : null,
                          child: widget.userAvatar == null ? Text(widget.userName[0]) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
