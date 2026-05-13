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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: modalBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            resource == null ? 'Add New Resource' : 'Edit Resource',
            style: TextStyle(color: textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'Website Name',
                  labelStyle: TextStyle(color: subTextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'URL (e.g. https://google.com)',
                  labelStyle: TextStyle(color: subTextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sNoCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'Serial Number',
                  labelStyle: TextStyle(color: subTextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () async {
                bool success;
                if (resource == null) {
                  success = await _resourceService.createResource(
                    nameCtrl.text,
                    urlCtrl.text,
                    int.tryParse(sNoCtrl.text) ?? 0,
                  );
                } else {
                  success = await _resourceService.updateResource(resource.id, {
                    'name': nameCtrl.text,
                    'url': urlCtrl.text,
                    'sNo': int.tryParse(sNoCtrl.text) ?? 0,
                  });
                }
                if (success && mounted) {
                  Navigator.pop(context);
                  _fetchResources();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteResource(WebsiteResource resource) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: modalBg,
        title: Text('Delete Resource', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to delete ${resource.name}?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoBack()) ? await controller!.goBack() : null : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios, size: 20, color: textColor),
                            onPressed: isSupported && controller != null ? () async => (await controller!.canGoForward()) ? await controller!.goForward() : null : null,
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddEditDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Resource', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_resources.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Text('No resources found.', style: TextStyle(color: subTextColor)),
                  ))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF202C33) : Colors.grey[200]),
                      columns: [
                        DataColumn(label: Text('S.No', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Name', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('URL', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Actions', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
                      ],
                      rows: _resources.map((resource) => DataRow(
                        cells: [
                          DataCell(Text(resource.sNo.toString(), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
                          DataCell(Text(resource.name, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
                          DataCell(SizedBox(
                            width: 150,
                            child: Text(resource.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subTextColor, fontSize: 12)),
                          )),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility_outlined, color: Color(0xFF25D366), size: 20),
                                  onPressed: () => _showWebViewDialog(resource.url),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                  onPressed: () => _showAddEditDialog(resource: resource),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                  onPressed: () => _deleteResource(resource),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}
