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
import 'package:url_launcher/url_launcher.dart';

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

  // Unified document states
  bool _isDocLoading = true;
  String? _docError;
  String? _localDocPath;
  double _docDownloadProgress = 0.0;

  // Inline Google Docs WebView states for Doc/PDF defaults
  WebViewController? _inlineWebViewController;
  bool _inlineWebViewLoading = true;

  // Native opening state
  bool _isDownloadingForNative = false;
  double _downloadProgress = 0.0;

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
    // Resolve potentially relative URL to fully qualified absolute URL
    _absoluteUrl = AuthService().getFullUrl(widget.url) ?? widget.url;

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

    if (_isDocument) {
      if (ext == 'doc' || ext == 'docx' || ext == 'pdf') {
        _initInlineGoogleDocs();
      } else {
        _initDocumentViewer();
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Initialize Google Docs Inline WebView for Word/PDF ──
  void _initInlineGoogleDocs() {
    final googleDocsUrl = "https://docs.google.com/viewer?url=${Uri.encodeComponent(_absoluteUrl)}&embedded=true";
    try {
      _inlineWebViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
        ..loadRequest(Uri.parse(googleDocsUrl));
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

  // ── Secure Download & Open via default System App ──
  Future<void> _openFileNatively() async {
    try {
      if (mounted) {
        setState(() {
          _isDownloadingForNative = true;
          _downloadProgress = 0.0;
        });
      }

      final tempDir = await getTemporaryDirectory();
      final ext = _getResolvedExtension();
      String safeFileName = widget.fileName ?? 'document';
      if (!safeFileName.toLowerCase().endsWith('.$ext')) {
        safeFileName = "$safeFileName.$ext";
      }
      final cleanFileName = safeFileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final tempFilePath = "${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName";

      final targetPath = _localDocPath ?? tempFilePath;

      // Only download if we don't have the file locally yet
      if (_localDocPath == null || !File(_localDocPath!).existsSync()) {
        final dio = _getDioClientForUrl(_absoluteUrl);
        await dio.download(
          _absoluteUrl,
          targetPath,
          onReceiveProgress: (received, total) {
            if (total != -1 && mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          },
        );
        _localDocPath = targetPath;
      }

      if (mounted) {
        setState(() {
          _isDownloadingForNative = false;
        });
      }

      debugPrint("📂 Opening file natively from temp cache: $targetPath");
      final result = await OpenFile.open(targetPath);
      
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not open file: ${result.message}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error opening file natively: $e");
      if (mounted) {
        setState(() {
          _isDownloadingForNative = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error opening file: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── In-App WebView Preview Fallback (Google Docs Viewer) ──
  void _openInGoogleDocsWebView(BuildContext context, String fileUrl) {
    final googleDocsUrl = "https://docs.google.com/viewer?url=${Uri.encodeComponent(fileUrl)}&embedded=true";
    WebViewController? controller;
    bool isSupported = true;
    
    // Theme options matching MediaGalleryScreen's sleek WhatsApp Dark mode
    const Color modalBg = Color(0xFF111B21);
    const Color textColor = Colors.white;

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(googleDocsUrl));
    } catch (e) {
      isSupported = false;
      debugPrint("❌ Error initializing WebViewController: $e");
    }

    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final currentController = controller;
        bool webViewLoading = true;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isSupported && currentController != null) {
              currentController.setNavigationDelegate(
                NavigationDelegate(
                  onPageStarted: (String url) {
                    if (mounted) {
                      setDialogState(() {
                        webViewLoading = true;
                      });
                    }
                  },
                  onPageFinished: (String url) {
                    if (mounted) {
                      setDialogState(() {
                        webViewLoading = false;
                      });
                    }
                  },
                  onWebResourceError: (WebResourceError error) {
                    debugPrint("🌐 WebView Resource Error: ${error.description}");
                  },
                ),
              );
            }

            return Dialog(
              backgroundColor: modalBg,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: size.width * 0.9,
                height: size.height * 0.95,
                child: Column(
                  children: [
                    // Header Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios, size: 20, color: textColor),
                                onPressed: isSupported && currentController != null
                                    ? () async {
                                        if (await currentController.canGoBack()) {
                                          await currentController.goBack();
                                        }
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios, size: 20, color: textColor),
                                onPressed: isSupported && currentController != null
                                    ? () async {
                                        if (await currentController.canGoForward()) {
                                          await currentController.goForward();
                                        }
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 22, color: textColor),
                                onPressed: isSupported && currentController != null
                                    ? () => currentController.reload()
                                    : null,
                              ),
                            ],
                          ),
                          // File name or title in header
                          if (widget.fileName != null)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  widget.fileName!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: textColor),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(
                      child: Stack(
                        children: [
                          if (isSupported && currentController != null)
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              child: WebViewWidget(controller: currentController),
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline, size: 48, color: Colors.orange),
                                  const SizedBox(height: 16),
                                  const Text('In-app preview not supported here.', style: TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00A884),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Open in Browser'),
                                  ),
                                ],
                              ),
                            ),
                          if (isSupported && currentController != null && webViewLoading)
                            const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF00A884)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Loading preview via Google Docs...',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
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
          },
        );
      },
    );
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
          // Google Docs in-app preview fallback option
          if (_isDocument) ...[
            IconButton(
              icon: const Icon(Icons.chrome_reader_mode_outlined, color: Colors.white),
              tooltip: "Preview in App",
              onPressed: () => _openInGoogleDocsWebView(context, _absoluteUrl),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              tooltip: "Open in System App",
              onPressed: _openFileNatively,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Center(
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
                        ? _buildDocumentViewer()
                        : const Text('Unsupported media type', style: TextStyle(color: Colors.white)),
          ),
          
          // Full screen download progress overlay for external opening fallback
          if (_isDownloadingForNative)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00A884)),
                    const SizedBox(height: 24),
                    const Text(
                      'Downloading securely for preview...',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Unified Document Viewer UI Builder ──
  Widget _buildDocumentViewer() {
    final ext = _getResolvedExtension();
    final isGoogleDocsDefault = ext == 'doc' || ext == 'docx' || ext == 'pdf';

    if (isGoogleDocsDefault) {
      if (_inlineWebViewController != null) {
        return Stack(
          children: [
            WebViewWidget(controller: _inlineWebViewController!),
            if (_inlineWebViewLoading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00A884)),
                    SizedBox(height: 16),
                    Text(
                      'Loading preview via Google Docs...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        );
      } else {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('In-app preview not supported here.', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => launchUrl(Uri.parse(_absoluteUrl), mode: LaunchMode.externalApplication),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A884),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open in Browser'),
              ),
            ],
          ),
        );
      }
    }

    if (_isDocLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00A884)),
          const SizedBox(height: 24),
          const Text(
            'Downloading secure document...',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(
            '${(_docDownloadProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      );
    }

    final isLegacyFormat = ext == 'doc' || ext == 'xls' || ext == 'ppt';

    if (isLegacyFormat) {
      Color legacyColor;
      IconData legacyIcon;
      String legacyAppName;
      
      if (ext == 'xls') {
        legacyColor = const Color(0xFF2E7D32); // Excel Green
        legacyIcon = Icons.table_chart;
        legacyAppName = "Microsoft Excel";
      } else if (ext == 'ppt') {
        legacyColor = const Color(0xFFD84315); // PowerPoint Orange
        legacyIcon = Icons.slideshow;
        legacyAppName = "Microsoft PowerPoint";
      } else {
        legacyColor = const Color(0xFF1565C0); // Word Blue
        legacyIcon = Icons.description;
        legacyAppName = "Microsoft Word";
      }

      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: legacyColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: legacyColor.withValues(alpha: 0.3), width: 2),
              ),
              child: Icon(legacyIcon, color: legacyColor, size: 64),
            ),
            const SizedBox(height: 24),
            Text(
              "Legacy Document Format (.${ext.toUpperCase()})",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "In-app previews for legacy office documents (.doc, .xls, .ppt) are not supported by the preview engine.\n\nTap below to open and view this file natively inside $legacyAppName or your default system reader.",
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: legacyColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 4,
              ),
              icon: const Icon(Icons.open_in_new, size: 20),
              label: Text("Open in $legacyAppName", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: _openFileNatively,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: legacyColor.withValues(alpha: 0.6), width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              icon: const Icon(Icons.chrome_reader_mode_outlined, size: 20),
              label: const Text("Preview in App", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: () => _openInGoogleDocsWebView(context, _absoluteUrl),
            ),
          ],
        ),
      );
    }

    if (_docError != null || _localDocPath == null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 54),
            const SizedBox(height: 16),
            Text(
              _docError ?? "Failed to load document.",
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A884),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 4,
              ),
              icon: const Icon(Icons.open_in_new, size: 20),
              label: const Text("Open Natively", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: _openFileNatively,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              icon: const Icon(Icons.chrome_reader_mode_outlined, size: 20),
              label: const Text("Preview in App", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: () => _openInGoogleDocsWebView(context, _absoluteUrl),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: UniversalFileViewer(
            file: File(_localDocPath!),
          ),
        ),
        
        // Polished bottom card offering a quick system external application open fallback
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2C34),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Having formatting issues?",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Open directly in Excel, Word, or native apps without saving to storage.",
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A884),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text("Open Natively"),
                onPressed: _openFileNatively,
              ),
            ],
          ),
        ),
      ],
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
