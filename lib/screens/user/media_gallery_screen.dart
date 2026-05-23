import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart';
import 'package:news_cover/services/auth_service.dart';
import 'package:news_cover/services/dio_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:dio/dio.dart';
import 'package:news_cover/services/api_constants.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'pdf_viewer_widget.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String url;
  final String? originalUrl;
  final String type;
  final String? fileName;
  final String senderName;
  final String? userRole;

  const MediaGalleryScreen({
    super.key,
    required this.url,
    this.originalUrl,
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
  bool _isVideoReadyCheckLoading = false;

  // Unified document states
  bool _isDocLoading = true;
  String? _docError;
  String? _localDocPath;
  double _docDownloadProgress = 0.0;

  // Inline Google Docs WebView states
  WebViewController? _inlineWebViewController;
  bool _inlineWebViewLoading = true;

  // Helper to extract extension robustly
  String _getResolvedExtension() {
    // 1. Try to extract from widget.fileName
    if (widget.fileName != null && widget.fileName!.contains('.')) {
      final ext = widget.fileName!.split('.').last.toLowerCase();
      if (ext.isNotEmpty && ext.length <= 5) {
        return ext;
      }
    }
    // 2. Try to extract from URL path
    try {
      final uri = Uri.tryParse(_absoluteUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final lastSeg = uri.pathSegments.last;
        if (lastSeg.contains('.')) {
          final ext = lastSeg.split('.').last.toLowerCase();
          if (ext.isNotEmpty && ext.length <= 5) {
            return ext;
          }
        }
      }
    } catch (_) {}
    // 3. Fallback based on widget.type
    if (widget.type == 'pdf') return 'pdf';
    if (widget.type == 'document') return 'docx';
    return 'docx';
  }

  // Helper to dynamically get authenticated or clean Dio client
  Dio _getDioClientForUrl(String url) {
    if (!url.startsWith(ApiConstants.baseUrl) &&
        (url.contains('digitaloceanspaces.com') ||
         url.contains('amazonaws.com') ||
         url.contains('cloudinary.com') ||
         url.contains('google.com'))) {
      debugPrint("🌐 External URL detected: $url. Using clean Dio client without authorization interceptor.");
      return Dio(BaseOptions(
        connectTimeout: const Duration(minutes: 20),
        receiveTimeout: const Duration(minutes: 20),
        followRedirects: true,
      ));
    }
    debugPrint("🔒 Internal URL detected: $url. Using shared authenticated Dio client.");
    return DioClient().dio;
  }

  @override
  void initState() {
    super.initState();

    final ext = _getResolvedExtension();
    
    // Identify if the file should be handled as a document/spreadsheet
    _isDocument = widget.type == 'pdf' || 
                  widget.type == 'document' || 
                  widget.type == 'attachment' || 
                  widget.type == 'file' ||
                  ext == 'pdf' ||
                  ext == 'xlsx' ||
                  ext == 'xls' ||
                  ext == 'docx' ||
                  ext == 'doc' ||
                  ext == 'ppt' ||
                  ext == 'pptx' ||
                  ext == 'csv' ||
                  ext == 'txt' ||
                  ext == 'md';

    _resolveInitialUrl();
  }

  Future<void> _resolveInitialUrl() async {
    // For documents, prefer originalUrl (Spaces) instead of Cloudinary preview thumbnail
    String targetUrl = widget.url;
    if (_isDocument && widget.originalUrl != null) {
      targetUrl = widget.originalUrl!;
      _absoluteUrl = AuthService().getFullUrl(targetUrl) ?? targetUrl;
      setState(() {});
    } else if (widget.type == 'video') {
      // For videos, we WANT to use Cloudinary for fast, web-optimized playback (moov atom at start).
      // However, because Cloudinary processes asynchronously, it might return 404 for the first ~20 seconds.
      if (widget.url.contains('res.cloudinary.com')) {
        setState(() => _isVideoReadyCheckLoading = true);
        
        // Convert the preview image URL to the actual video URL
        String cloudinaryVideoUrl = widget.url.replaceAll(RegExp(r'\.jpg|\.png'), '.mp4');
        cloudinaryVideoUrl = cloudinaryVideoUrl.replaceAll('/f_jpg/', '/'); // Strip f_jpg so it hits the default eager MP4 cache!
        
        try {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(milliseconds: 1500),
            receiveTimeout: const Duration(milliseconds: 1500),
          ));
          final response = await dio.head(cloudinaryVideoUrl);
          if (response.statusCode == 200) {
            targetUrl = cloudinaryVideoUrl;
            debugPrint("✅ Cloudinary video is ready! Using fast playback: $targetUrl");
          } else {
            debugPrint("⏳ Cloudinary video not ready yet (status ${response.statusCode}). Falling back to Spaces.");
            targetUrl = widget.originalUrl ?? widget.url;
          }
        } catch (e) {
          debugPrint("⏳ Cloudinary video HEAD failed or timed out (1.5s). Still processing. Falling back to Spaces.");
          targetUrl = widget.originalUrl ?? widget.url;
        }
        
        setState(() => _isVideoReadyCheckLoading = false);
      } else if (widget.originalUrl != null && widget.originalUrl!.isNotEmpty) {
        targetUrl = widget.originalUrl!;
      }
      
      // Resolve potentially relative URL to fully qualified absolute URL
      _absoluteUrl = AuthService().getFullUrl(targetUrl) ?? targetUrl;
    } else {
      // Resolve potentially relative URL to fully qualified absolute URL
      _absoluteUrl = AuthService().getFullUrl(targetUrl) ?? targetUrl;

      // Cloudinary Hack: If the backend saved a PDF as a .png URL, Cloudinary will only return page 1.
      // We rewrite the URL to end with .pdf to force Cloudinary to return the full original PDF document!
      if (_absoluteUrl.contains('res.cloudinary.com') && widget.fileName?.toLowerCase().endsWith('.pdf') == true) {
        if (_absoluteUrl.toLowerCase().endsWith('.png') || _absoluteUrl.toLowerCase().endsWith('.jpg')) {
          debugPrint("🔄 Rewriting Cloudinary URL to fetch original multi-page PDF instead of PNG thumbnail.");
          _absoluteUrl = _absoluteUrl.substring(0, _absoluteUrl.lastIndexOf('.')) + '.pdf';
        }
      }
    }

    if (_isDocument) {
      final ext = _getResolvedExtension();
      if (ext == 'pdf') {
        _initCustomPdfViewer(); // Use PDF.js web viewer for PDFs to prevent native rendering errors
      } else {
        _initInlineDocs(); // Use Microsoft viewer for ALL other office documents to avoid skeleton loaders, restricted inside app
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Initialize Native Base64 Injected PDF.js Viewer ──
  Future<void> _initCustomPdfViewer() async {
    try {
      if (mounted) setState(() => _inlineWebViewLoading = true);

      final dio = _getDioClientForUrl(_absoluteUrl);
      List<int> bytes;
      
      try {
        final response = await dio.get(
          _absoluteUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = response.data as List<int>;
      } on DioException catch (e) {
        // If Cloudinary rejects the .pdf extension with a 401 (Delivery of PDFs is restricted in their account), 
        // fallback to the original .png thumbnail!
        if (e.response?.statusCode == 401 && _absoluteUrl.endsWith('.pdf') && widget.url.endsWith('.png')) {
          debugPrint("⚠️ Cloudinary blocked the .pdf request (401). Falling back to .png thumbnail.");
          _absoluteUrl = AuthService().getFullUrl(widget.url) ?? widget.url;
          final fallbackResponse = await dio.get(
            _absoluteUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          bytes = fallbackResponse.data as List<int>;
        } else {
          rethrow;
        }
      }
      
      // Verify if it's actually a PDF
      final headerStr = String.fromCharCodes(bytes.take(200));
      final base64Data = base64Encode(bytes);

      if (!headerStr.contains('%PDF-')) {
        // Cloudinary sometimes rasterizes PDFs into PNGs if uploaded to /image/upload/
        // If the server returned an image, gracefully render it as an image!
        if (headerStr.contains('PNG') || headerStr.contains('JFIF') || headerStr.contains('Exif') || (bytes.isNotEmpty && bytes[0] == 0xFF)) {
          debugPrint("📸 Detected Image instead of PDF. Displaying as image.");
          final htmlContent = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
            </head>
            <body style="background-color: #000; margin: 0; display: flex; justify-content: center; align-items: center; min-height: 100vh;">
                <img src="data:image/png;base64,$base64Data" style="max-width: 100%; max-height: 100vh; object-fit: contain;">
            </body>
            </html>
          """;
          _inlineWebViewController = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadHtmlString(htmlContent);
            
          if (mounted) setState(() => _inlineWebViewLoading = false);
          return;
        }

        // If it's a completely invalid response, show the error
        final errorText = headerStr.replaceAll('\n', '<br>');
        final htmlContent = """
          <!DOCTYPE html>
          <html>
          <head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
          <body style="background-color: #000; color: #ff5555; padding: 20px; font-family: sans-serif;">
              <h2>Server returned invalid PDF data:</h2>
              <p style="color: #aaa; font-family: monospace;">$errorText...</p>
          </body>
          </html>
        """;
        _inlineWebViewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(htmlContent);
          
        if (mounted) setState(() => _inlineWebViewLoading = false);
        return;
      }

      final base64Pdf = base64Encode(bytes);

      final htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/2.16.105/pdf.min.js"></script>
            <style>
                body { background-color: #000; margin: 0; padding: 10px; display: flex; flex-direction: column; align-items: center; }
                canvas { max-width: 100%; height: auto; margin-bottom: 16px; box-shadow: 0 4px 8px rgba(0,0,0,0.5); }
            </style>
        </head>
        <body>
            <div id="pdf-container"></div>
            <script>
                var binaryString = atob('$base64Pdf');
                var len = binaryString.length;
                var bytes = new Uint8Array(len);
                for (var i = 0; i < len; i++) {
                    bytes[i] = binaryString.charCodeAt(i);
                }
                
                var loadingTask = pdfjsLib.getDocument({data: bytes});
                loadingTask.promise.then(function(pdf) {
                    var container = document.getElementById('pdf-container');
                    for (var pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
                        pdf.getPage(pageNum).then(function(page) {
                            var scale = 1.5;
                            var viewport = page.getViewport({scale: scale});
                            var canvas = document.createElement('canvas');
                            var context = canvas.getContext('2d');
                            canvas.height = viewport.height;
                            canvas.width = viewport.width;
                            container.appendChild(canvas);
                            var renderContext = { canvasContext: context, viewport: viewport };
                            page.render(renderContext);
                        });
                    }
                }).catch(function(error) {
                    document.body.innerHTML = '<h2 style="color:red;text-align:center;">Failed to load PDF<br>' + error.message + '</h2>';
                });
            </script>
        </body>
        </html>
      """;

      _inlineWebViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(htmlContent);

      if (mounted) setState(() => _inlineWebViewLoading = false);
    } catch (e) {
      debugPrint("❌ Error rendering custom PDF: $e");
      if (mounted) setState(() => _inlineWebViewLoading = false);
    }
  }

  // ── Initialize Microsoft Office Inline WebView ──
  void _initInlineDocs() {
    // Append parameters to forcefully disable Microsoft's native Download/Print buttons and enforce Mobile View natively.
    final msDocsUrl = "https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(_absoluteUrl)}&wdMobile=1&wdPrint=0&wdEmbedCode=0&wdDownloadButton=0";
    try {
      _inlineWebViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // Force a Mobile User-Agent so Microsoft Office Web Viewer loads the "Mobile Reading View"
        // which naturally scales to 100% screen width and reflows text!
        ..setUserAgent("Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36")
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _inlineWebViewLoading = true;
                });
              }
            },
            onPageFinished: (String url) {
              // Inject CSS to hide Microsoft Viewer's top header, bottom bar, and maximize the document view
              _inlineWebViewController?.runJavaScript("""
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                  meta = document.createElement('meta');
                  meta.name = 'viewport';
                  document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';

                var style = document.createElement('style');
                style.innerHTML = `
                  #AppHeaderPanel, .WACHeader, .Hero-Header, .CommandBar, 
                  #WACBottomPanel, #MobileBottomBar, .App-BottomBar, 
                  #StatusBar, .WACStatusBar, #WACStatusBarPanel, .App-StatusBar,
                  [id*="Download"], [class*="Download"], [aria-label*="Download"], a[download], 
                  [id*="Print"], [class*="Print"] { 
                      display: none !important; 
                      pointer-events: none !important; 
                      opacity: 0 !important; 
                  }
                  #WACViewPanel, .WACViewPanel, #AppView, .AppView, #AppBody, body, html {
                      top: 0 !important;
                      bottom: 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      height: 100vh !important;
                      width: 100vw !important;
                  }
                `;
                document.head.appendChild(style);
              """);
              
              if (mounted) {
                setState(() {
                  _inlineWebViewLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint("🌐 Inline WebView Resource Error: ${error.description}");
            },
          ),
        )
        ..loadRequest(Uri.parse(msDocsUrl));
    } catch (e) {
      debugPrint("❌ Error initializing inline WebViewController: $e");
    }
  }

  // ── Secure Download to Temp Cache for Inline Rendering ──
  Future<void> _initDocumentViewer() async {
    try {
      if (mounted) {
        setState(() {
          _isDocLoading = true;
          _docError = null;
          _docDownloadProgress = 0.0;
        });
      }

      final tempDir = await getTemporaryDirectory();
      final ext = _getResolvedExtension();
      String safeFileName = widget.fileName ?? 'document';
      if (!safeFileName.toLowerCase().endsWith('.$ext')) {
        safeFileName = "$safeFileName.$ext";
      }
      final cleanFileName = safeFileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      
      // Ensure unique filename by appending timestamp
      _localDocPath = "${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName";

      debugPrint("📥 Downloading secure document for preview: $_absoluteUrl");
      final dio = _getDioClientForUrl(_absoluteUrl);
      await dio.download(
        _absoluteUrl,
        _localDocPath!,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _docDownloadProgress = received / total;
            });
          }
        },
      );

      // Verify the downloaded file is not an error page or empty
      final file = File(_localDocPath!);
      final bytes = await file.readAsBytes();
      if (bytes.length < 500) {
        final content = String.fromCharCodes(bytes.take(200));
        if (content.contains("Unauthorized") || 
            content.contains("<html") || 
            content.contains("<xml") || 
            content.contains("error")) {
          throw Exception("The file download failed or access was denied by the server.");
        }
      }

      if (mounted) {
        setState(() {
          _isDocLoading = false;
        });
      }
    } catch (e) {
      final errorMsg = "Could not preview file in-app.\n\n"
          "URL: $_absoluteUrl\n"
          "Path: ${_localDocPath ?? 'Not Set'}\n"
          "Error: $e\n\n"
          "Tap 'Open Natively' below to open it.";
      debugPrint("❌ Error downloading document for inline preview: $errorMsg");
      if (mounted) {
        setState(() {
          _docError = errorMsg;
          _isDocLoading = false;
        });
      }
    }
  }

      // External open methods completely removed per user request

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
        actions: [], // Removed external/download buttons entirely
      ),
      body: Stack(
        children: [
          Center(
            child: _absoluteUrl.isEmpty
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00A884)),
                      SizedBox(height: 16),
                      Text('Media is processing...', style: TextStyle(color: Colors.white)),
                    ],
                  )
                : widget.type == 'image'
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
                            ? _buildDocumentViewer()
                            : const Text('Unsupported media type', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentViewer() {
    final ext = _getResolvedExtension();

    if (_inlineWebViewController != null) {
      return WebViewWidget(controller: _inlineWebViewController!);
    } else {
      return const Center(
        child: Text('Preview loading.', style: TextStyle(color: Colors.white70)),
      );
    }
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool inline;
  const VideoPlayerWidget({super.key, required this.url, this.inline = false});

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
    
    if (widget.inline) {
      // In-line video acts as a thumbnail, no controls, no autoplay, muted.
      _videoPlayerController.setVolume(0.0);
      setState(() {});
      return;
    }

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
    if (widget.inline) {
      return _videoPlayerController.value.isInitialized
          ? Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoPlayerController.value.aspectRatio,
                  child: VideoPlayer(_videoPlayerController),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
    }

    return _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
        ? Chewie(controller: _chewieController!)
        : const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
  }
}
