import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/news_provider.dart';
import '../models/article.dart';
import 'individual_news_article_screen.dart';

class CategoryScreen extends StatelessWidget {
  final Map<String, dynamic> category;
  const CategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category['icon'] as IconData, size: 20),
            const SizedBox(width: 8),
            Text('${category['label']}'),
          ],
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer<NewsProvider>(
        builder: (context, provider, _) {
          final catKey = category['key']!;

          return RefreshIndicator(
            onRefresh: () => provider.loadCategory(catKey, forceRefresh: true),
            child: Builder(
              builder: (_) {
                final state = provider.categoryStates[catKey];
                if (state == LoadState.loading || state == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state == LoadState.error) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text('Failed to load ${category['label']} news'),
                        TextButton(
                          onPressed: () =>
                              provider.loadCategory(catKey, forceRefresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final articles = provider.articlesForCategory(catKey);
                if (articles.isEmpty) {
                  return const Center(child: Text('No articles available'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: articles.length,
                  itemBuilder: (ctx, i) =>
                      _CategoryArticleTile(article: articles[i]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CategoryArticleTile extends StatelessWidget {
  final Article article;
  const _CategoryArticleTile({required this.article});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndividualNewsArticleScreen(article: article),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.urlToImage != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: article.urlToImage!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.sourceName != null)
                    Text(
                      article.sourceName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (article.description != null &&
                      article.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
