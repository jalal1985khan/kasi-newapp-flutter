import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../providers/news_provider.dart';
import '../../models/article.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../individual_news_article_screen.dart';

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Pre-fill with last query if any
    final provider = context.read<NewsProvider>();
    if (provider.lastSearchQuery.isNotEmpty) {
      _ctrl.text = provider.lastSearchQuery;
    }
    
    _ctrl.addListener(_onSearchChanged);
    
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _search();
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onSearchChanged);
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _search() {
    final q = _ctrl.text.trim();
    if (q.isEmpty || q == context.read<NewsProvider>().lastSearchQuery) return;
    context.read<NewsProvider>().searchNews(q);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            // Search bar row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'Search news...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _search,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Results
            Expanded(
              child: Consumer<NewsProvider>(
                builder: (context, provider, _) {
                  if (provider.searchState == LoadState.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.searchState == LoadState.error) {
                    return Center(
                      child: Text('Error: ${provider.errorMessage}'),
                    );
                  }
                  if (provider.searchResults.isEmpty &&
                      provider.lastSearchQuery.isNotEmpty) {
                    return const Center(child: Text('No results found'));
                  }
                  if (provider.searchResults.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'Search for news articles',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: provider.searchResults.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, i) =>
                        _SearchResultTile(article: provider.searchResults[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Article article;
  const _SearchResultTile({required this.article});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 72,
          height: 56,
          child: article.urlToImage != null
              ? CachedNetworkImage(
                  imageUrl: article.urlToImage!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(color: Colors.grey[200]),
                )
              : Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.newspaper, color: Colors.grey),
                ),
        ),
      ),
      title: Text(
        article.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: article.sourceName != null
          ? Text(
              article.sourceName!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
      onTap: () {
        Navigator.pop(context); // Close dialog first
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndividualNewsArticleScreen(article: article),
          ),
        );
      },
    );
  }
}
