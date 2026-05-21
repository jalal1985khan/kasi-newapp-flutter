import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:news_cover/services/auth_service.dart';

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
  late String _absoluteUrl;

  WebViewController? _webViewController;
  bool _isWebViewLoading = true;
  double _webViewProgress = 0.0;

  @override
  void initState() {
    super.initState();
    // Resolve potentially relative URL to fully qualified absolute URL
    _absoluteUrl = AuthService().getFullUrl(widget.url) ?? widget.url;

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
      _initWebView();
    }
  }

  void _initWebView() {
    final previewUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(_absoluteUrl)}';
    debugPrint("🌐 Loading document preview in WebView: $previewUrl");
    
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _webViewProgress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isWebViewLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isWebViewLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("❌ WebView resource error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(previewUrl));
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
                  _absoluteUrl,
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
                ? VideoPlayerWidget(url: _absoluteUrl)
                : _isDocument
                    ? Stack(
                        children: [
                          if (_webViewController != null)
                            WebViewWidget(controller: _webViewController!),
                          if (_isWebViewLoading)
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(color: Color(0xFF00A884)),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'Opening document in-app...',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${(_webViewProgress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
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
