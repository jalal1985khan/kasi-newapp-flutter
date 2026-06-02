import 'package:flutter/material.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/admin/admin_resource_service.dart';
import '../../models/admin/website_resource.dart';

class WebsiteResourcesScreen extends StatefulWidget {
  const WebsiteResourcesScreen({super.key});

  @override
  State<WebsiteResourcesScreen> createState() => _WebsiteResourcesScreenState();
}

class _WebsiteResourcesScreenState extends State<WebsiteResourcesScreen> {
  final AdminResourceService _resourceService = AdminResourceService();
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
  void _showAddEditDialog({WebsiteResource? resource}) {
    final nameCtrl = TextEditingController(text: resource?.name ?? '');
    final urlCtrl = TextEditingController(text: resource?.url ?? '');
    final sNoCtrl = TextEditingController(text: resource?.sNo.toString() ?? '');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF0B141A) : Colors.white;
    final Color cardBg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color accentColor = const Color(0xFF00A884);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          bool isSaving = false;
          String? nameError;
          String? urlError;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.65,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) => Container(
                decoration: BoxDecoration(
                  color: modalBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Drag Indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resource == null ? 'Add Website Resource' : 'Edit Website Resource',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                resource == null
                                    ? 'Create a new resource link for employees'
                                    : 'Modify existing resource parameters',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: isDark ? Colors.white10 : Colors.black12,
                              child: Icon(Icons.close_rounded, size: 18, color: textColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Body List
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(24),
                        children: [
                          // Website Name Input
                          Text(
                            'WEBSITE NAME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: nameError != null ? Colors.redAccent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: TextField(
                              controller: nameCtrl,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: 'Enter name (e.g. Employee HR Portal)',
                                hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                                prefixIcon: Icon(Icons.language_rounded, color: accentColor, size: 22),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          if (nameError != null) ...[
                            const SizedBox(height: 4),
                            Text(nameError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                          ],

                          const SizedBox(height: 20),

                          // URL Input
                          Text(
                            'WEBSITE URL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: urlError != null ? Colors.redAccent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: TextField(
                              controller: urlCtrl,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: 'Enter URL (https://...)',
                                hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                                prefixIcon: Icon(Icons.link_rounded, color: accentColor, size: 22),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          if (urlError != null) ...[
                            const SizedBox(height: 4),
                            Text(urlError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                          ],

                          const SizedBox(height: 20),

                          // Display Order Input
                          Text(
                            'DISPLAY ORDER (SERIAL NO.)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: sNoCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: 'Enter order number (e.g. 1)',
                                hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                                prefixIcon: Icon(Icons.sort_rounded, color: accentColor, size: 22),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Save Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isSaving ? null : () async {
                                final name = nameCtrl.text.trim();
                                final url = urlCtrl.text.trim();

                                setModalState(() {
                                  nameError = name.isEmpty ? 'Website name is required' : null;
                                  urlError = url.isEmpty ? 'URL is required' : null;
                                });

                                if (name.isEmpty || url.isEmpty) return;

                                setModalState(() {
                                  isSaving = true;
                                });

                                bool success;
                                if (resource == null) {
                                  success = await _resourceService.createResource(
                                    name,
                                    url,
                                    int.tryParse(sNoCtrl.text) ?? 0,
                                  );
                                } else {
                                  success = await _resourceService.updateResource(resource.id, {
                                    'name': name,
                                    'url': url,
                                    'sNo': int.tryParse(sNoCtrl.text) ?? 0,
                                  });
                                }

                                if (success && mounted) {
                                  Navigator.pop(context);
                                  _fetchResources();
                                } else {
                                  setModalState(() {
                                    isSaving = false;
                                  });
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      resource == null ? 'Create Resource' : 'Save Changes',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteResource(WebsiteResource resource) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF0B141A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            Text(
              'Delete Resource',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${resource.name}"? This action cannot be undone.',
          style: TextStyle(color: subTextColor, fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );

    if (confirm == true) {
      final success = await _resourceService.deleteResource(resource.id);
      if (success && mounted) _fetchResources();
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
        ..loadRequest(Uri.parse(url));
    } catch (e) {
      isSupported = false;
    }

    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return Dialog(
          backgroundColor: modalBg,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: size.width * 0.9,
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
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoBack()) ? await controller.goBack() : null : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios, size: 20, color: textColor),
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoForward()) ? await controller.goForward() : null : null,
                          ),
                        ],
                      ),
                      IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                Expanded(
                  child: isSupported && controller != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                          child: WebViewWidget(controller: controller),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline, size: 48, color: Colors.orange),
                              const SizedBox(height: 16),
                              Text('WebView not supported here.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => launchUrl(Uri.parse(url)),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white),
                                child: const Text('Open External Browser'),
                              ),
                            ],
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

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;
    final Color cardBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final sortedResources = List<WebsiteResource>.from(_resources)
      ..sort((a, b) => a.sNo.compareTo(b.sNo));

    return AdminLayout(
      showBottomNav: false,
      title: 'Resources',
      currentIndex: 4,
      onRefresh: _fetchResources,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
        : SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Directory Stats Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark 
                          ? [const Color(0xFF1F2C34), const Color(0xFF111B21)] 
                          : [const Color(0xFF00A884).withOpacity(0.06), const Color(0xFF00A884).withOpacity(0.01)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFF00A884).withOpacity(0.12),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A884).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF00A884), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resource Directory',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Quick access portals for employees',
                              style: TextStyle(
                                fontSize: 12,
                                color: subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A884),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_resources.length} Links',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Add New Resource Action Trigger
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddEditDialog(),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add New Resource', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.3)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                      shadowColor: const Color(0xFF00A884).withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Section Title
                Text(
                  'REGISTERED WEB ASSETS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white38 : Colors.black38,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                if (_resources.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_off_rounded, size: 48, color: subTextColor.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text('No web resources found.', style: TextStyle(color: subTextColor, fontSize: 14)),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedResources.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final resource = sortedResources[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              // Elegant S.No badge
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A884).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    resource.sNo.toString(),
                                    style: const TextStyle(
                                      color: Color(0xFF00A884),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Details (Name & URL)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      resource.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      resource.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: subTextColor,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Premium spaced Action Row
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.visibility_outlined,
                                    color: const Color(0xFF25D366),
                                    onTap: () => _showWebViewDialog(resource.url),
                                    tooltip: 'View Resource',
                                  ),
                                  const SizedBox(width: 6),
                                  _buildActionButton(
                                    icon: Icons.edit_rounded,
                                    color: Colors.blueAccent,
                                    onTap: () => _showAddEditDialog(resource: resource),
                                    tooltip: 'Edit',
                                  ),
                                  const SizedBox(width: 6),
                                  _buildActionButton(
                                    icon: Icons.delete_rounded,
                                    color: Colors.redAccent,
                                    onTap: () => _deleteResource(resource),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
    );
  }
}
