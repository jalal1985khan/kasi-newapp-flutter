import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/user/user_resource_service.dart';
import '../../models/admin/website_resource.dart';
import 'common_widgets/user_drawer.dart';
import 'common_widgets/user_bottom_navigationbar.dart';
import 'user_main_screen.dart';

class UserWebsiteResourcesScreen extends StatefulWidget {
  const UserWebsiteResourcesScreen({super.key});

  @override
  State<UserWebsiteResourcesScreen> createState() => _UserWebsiteResourcesScreenState();
}

class _UserWebsiteResourcesScreenState extends State<UserWebsiteResourcesScreen> {
  final UserResourceService _resourceService = UserResourceService();
  List<WebsiteResource> _resources = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchResources();
  }

  Future<void> _fetchResources() async {
    setState(() => _isLoading = true);
    final resources = await _resourceService.getResources();
    if (mounted) {
      setState(() {
        _resources = resources;
        _isLoading = false;
      });
    }
  }

  void _showWebViewDialog(String url) {
    WebViewController? controller;
    bool isSupported = true;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              // Inject JS to prevent text selection, copying, and context menu
              controller?.runJavaScript(
                "document.documentElement.style.webkitUserSelect='none';"
                "document.documentElement.style.userSelect='none';"
                "document.documentElement.style.webkitTouchCallout='none';"
                "document.oncontextmenu=function(){return false;};"
              );
            },
            onNavigationRequest: (NavigationRequest request) {
              // Block external links if needed, but here we just block going outside the webview (we don't provide a browser launch)
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
    } catch (e) {
      isSupported = false;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental close
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return Dialog(
          backgroundColor: modalBg,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: size.width * 0.95,
            height: size.height * 0.95,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_ios, size: 20, color: textColor),
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoBack()) ? await controller!.goBack() : null : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios, size: 20, color: textColor),
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoForward()) ? await controller!.goForward() : null : null,
                          ),
                        ],
                      ),
                      const Text('Resource Viewer', style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                Expanded(
                  child: isSupported && controller != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          child: WebViewWidget(controller: controller!),
                        )
                      : Center(
                          child: Text(
                            'WebView not supported on this device/platform.',
                            style: TextStyle(color: textColor.withOpacity(0.5)),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color waTeal = const Color(0xFF00A884);
    final Color waDarkBg = const Color(0xFF111B21);
    final Color waDarkSecondary = const Color(0xFF202C33);
    final Color cardBg = isDark ? waDarkSecondary : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? waDarkBg : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Website Resources'),
        backgroundColor: isDark ? waDarkSecondary : waTeal,
        foregroundColor: Colors.white,
      ),
      drawer: const UserDrawer(),
      bottomNavigationBar: UserBottomNavigationBar(
        currentIndex: -1, // Indicates no main tab is active
        onTap: (index) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => UserMainScreen(initialIndex: index)),
          );
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _resources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link_off, size: 80, color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(height: 16),
                      Text(
                        'No resources available',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _resources.length,
                  itemBuilder: (context, index) {
                    final resource = _resources[index];
                    return Card(
                      color: cardBg,
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        onTap: () => _showWebViewDialog(resource.url),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: waTeal.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(Icons.public, color: waTeal, size: 28),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      resource.name,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      resource.url,
                                      style: TextStyle(
                                        color: isDark ? Colors.white54 : Colors.black54,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white30 : Colors.black38),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
