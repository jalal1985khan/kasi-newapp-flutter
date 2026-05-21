import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class MediaGalleryScreen extends StatefulWidget {
  final String url;
  final String type;
  final String? fileName;
  final String senderName;
  final String? userRole;

  const MediaGalleryScreen({
    super.key,
    required this.url,
    required this.type,
    this.fileName,
    required this.senderName,
    this.userRole,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  bool _isDocument = false;
  bool _isDownloading = false;
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    // Identify if the file should be handled as a document/spreadsheet
    _isDocument = widget.type == 'pdf' || 
                  widget.type == 'document' || 
                  widget.type == 'attachment' || 
                  widget.type == 'file' ||
                  (widget.fileName?.toLowerCase().endsWith('.pdf') ?? false) ||
                  (widget.fileName?.toLowerCase().endsWith('.xlsx') ?? false) ||
                  (widget.fileName?.toLowerCase().endsWith('.xls') ?? false) ||
                  (widget.fileName?.toLowerCase().endsWith('.docx') ?? false) ||
                  (widget.fileName?.toLowerCase().endsWith('.doc') ?? false);

    if (_isDocument) {
      _openFileLocally();
    }
  }

  Future<void> _openFileLocally() async {
    try {
      final tempDir = await getTemporaryDirectory();
      
      // Extract a safe filename from fileName or url
      String safeName = widget.fileName ?? widget.url.split('/').last.split('?').first;
      if (safeName.isEmpty) {
        safeName = "document_${DateTime.now().millisecondsSinceEpoch}";
      }
      
      // Use URL hash to create a unique directory to prevent local file name collisions
      final urlHash = widget.url.hashCode.toString();
      final cacheDir = Directory('${tempDir.path}/cached_files/$urlHash');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      final filePath = '${cacheDir.path}/$safeName';
      final file = File(filePath);

      // 1. Instant Cache Hit: If already downloaded and exists, open immediately
      if (await file.exists() && await file.length() > 0) {
        debugPrint("📂 Opening document from local cache: $filePath");
        final result = await OpenFilex.open(filePath);
        if (mounted) {
          if (result.type != ResultType.done) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open file: ${result.message}'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          Navigator.pop(context); // Go back immediately since it opened in native viewer
        }
        return;
      }

      // 2. Cache Miss: Download directly from CDN to local path
      if (mounted) {
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0.0;
        });
      }

      debugPrint("📥 Downloading file from CDN: ${widget.url}");
      final dio = Dio();
      await dio.download(
        widget.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = null;
        });
      }

      // 3. Open natively
      final result = await OpenFilex.open(filePath);
      if (mounted) {
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open file: ${result.message}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("❌ Error opening file natively: $e");
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.senderName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (widget.fileName != null)
              Text(
                widget.fileName!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (widget.userRole == 'super_admin')
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Document is already saved locally.')),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: widget.type == 'image'
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  widget.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                        color: const Color(0xFF00A884),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text('Failed to load image', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              )
            : widget.type == 'video'
                ? VideoPlayerWidget(url: widget.url)
                : _isDocument
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFF00A884)),
                          const SizedBox(height: 24),
                          Text(
                            _isDownloading ? 'Downloading file...' : 'Opening document...',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          if (_downloadProgress != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '${(_downloadProgress! * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ],
                      )
                    : const Text('Unsupported media type', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  const VideoPlayerWidget({super.key, required this.url});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      allowFullScreen: true,
      allowMuting: true,
      showControls: true,
      placeholder: const Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
        ? Chewie(controller: _chewieController!)
        : const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
  }
}
