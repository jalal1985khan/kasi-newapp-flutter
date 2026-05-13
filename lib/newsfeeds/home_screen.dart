import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/news_provider.dart';
import '../models/app_constants.dart';
import '../models/article.dart';
import 'widgets/news_card_section2.dart';
import 'widgets/news_card_section3.dart';
import 'widgets/search_dialog.dart';
import 'widgets/secret_admin_tap.dart';
import 'category_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load all news on first launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NewsProvider>().initialLoad();
    });
  }

  void _openSearch() {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => const SearchDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => context.read<NewsProvider>().refreshAll(),
          child: CustomScrollView(
            slivers: [
              // ── App bar + search ──────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily News',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      // ── SECTION 1: Search bar ─────────────
                      GestureDetector(
                        onTap: _openSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.grey),
                              const SizedBox(width: 10),
                              Text(
                                'Search news...',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── SECTION 2: Category filter + news ─────────
              SliverToBoxAdapter(child: _Section2()),

              // ── SECTION 3: All categories preview ─────────
              SliverToBoxAdapter(child: _Section3()),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverToBoxAdapter(child: SecretAdminTap()),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class _Section2 extends StatelessWidget {
  const _Section2();

  @override
  Widget build(BuildContext context) {
    return Consumer<NewsProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category horizontal scroll
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: AppConstants.categories.length,
                itemBuilder: (ctx, i) {
                  final cat = AppConstants.categories[i];
                  final isSelected = provider.selectedCategory == cat['key'];
                  return GestureDetector(
                    onTap: () => provider.setSelectedCategory(cat['key']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            size: 16,
                            color: isSelected ? Colors.white : Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${cat['label']}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // News cards for selected category (first 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Builder(
                builder: (_) {
                  final state =
                      provider.categoryStates[provider.selectedCategory];
                  if (state == LoadState.loading || state == null) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (state == LoadState.error) {
                    return Center(
                      child: Text(
                        'Failed to load ${provider.selectedCategory} news',
                      ),
                    );
                  }
                  final articles = provider.section2Articles;
                  if (articles.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No articles available'),
                      ),
                    );
                  }
                  return Column(
                    children: articles
                        .map((a) => NewsCardSection2(article: a))
                        .toList(),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class _Section3 extends StatelessWidget {
  const _Section3();

  @override
  Widget build(BuildContext context) {
    return Consumer<NewsProvider>(
      builder: (context, provider, _) {
        final items = provider.section3Items;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'More Categories',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (items.isEmpty)
                const Center(child: CircularProgressIndicator())
              else
                ...items.map((item) {
                  return NewsCardSection3(
                    category: item['category'] as Map<String, dynamic>,
                    article: item['article'] as Article,
                    onTap: () {
                      final cat = item['category'] as Map<String, dynamic>;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoryScreen(category: cat),
                        ),
                      );
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
