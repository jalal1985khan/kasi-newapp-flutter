import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'dart:typed_data';

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
                // TODO: Implement download
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download started...')),
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
                            ? loadingProgress.calculatedToHttpProgress
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
                : widget.type == 'pdf' || (widget.fileName?.toLowerCase().endsWith('.pdf') ?? false)
                    ? PdfViewerWidget(url: widget.url)
                    : (widget.type == 'document' || widget.type == 'attachment')
                        ? AppWebViewViewer(url: widget.url)
                        : const Text('Unsupported media type', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

extension on ImageChunkEvent {
  double? get calculatedToHttpProgress =>
      expectedTotalBytes != null ? cumulativeBytesLoaded / expectedTotalBytes! : null;
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
class PdfViewerWidget extends StatefulWidget {
  final String url;
  const PdfViewerWidget({super.key, required this.url});

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  PdfControllerPinch? _pdfController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openData(
          (await Dio().get<List<int>>(
            widget.url,
            options: Options(responseType: ResponseType.bytes),
          )).data!.toUint8List(),
        ),
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
    if (_error != null) return Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.white)));
    return PdfViewPinch(controller: _pdfController!);
  }
}

class AppWebViewViewer extends StatefulWidget {
  final String url;
  const AppWebViewViewer({super.key, required this.url});

  @override
  State<AppWebViewViewer> createState() => _AppWebViewViewerState();
}

class _AppWebViewViewerState extends State<AppWebViewViewer> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final String encodedUrl = Uri.encodeComponent(widget.url);
    final String viewerUrl = 'https://docs.google.com/viewer?url=$encodedUrl&embedded=true';
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(viewerUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
      ],
    );
  }
}

extension ListIntToUint8List on List<int> {
  Uint8List toUint8List() => Uint8List.fromList(this);
}
