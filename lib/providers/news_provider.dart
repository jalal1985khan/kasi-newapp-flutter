import 'package:flutter/material.dart';
import '../models/article.dart';
import '../models/app_constants.dart';
import '../services/news_service.dart';
import '../services/cache_service.dart';

enum LoadState { idle, loading, loaded, error }

class NewsProvider extends ChangeNotifier {
  final NewsService _service = NewsService();
  final CacheService _cache = CacheService();

  // ── Trending ──────────────────────────────────────────────
  List<Article> trendingNews = [];
  LoadState trendingState = LoadState.idle;

  // ── Category news — keyed by category string ─────────────
  // e.g. { 'technology': [...], 'business': [...] }
  Map<String, List<Article>> categoryNews = {};
  Map<String, LoadState> categoryStates = {};

  // ── Search ────────────────────────────────────────────────
  List<Article> searchResults = [];
  LoadState searchState = LoadState.idle;
  String lastSearchQuery = '';

  // ── Selected category for Section 2 ──────────────────────
  String selectedCategory = AppConstants.categories.first['key']!;

  String? errorMessage;

  // ─────────────────────────────────────────────────────────
  // INITIALISE — called once at app start
  // ─────────────────────────────────────────────────────────
  Future<void> initialLoad() async {
    // 1. Load Trending and Selected Category first
    await Future.wait([
      loadTrending(),
      loadCategory(selectedCategory),
    ]);

    // 2. Load other categories in the background sequentially to avoid 429 rate limit
    for (var cat in AppConstants.categories) {
      if (cat['key'] != selectedCategory) {
        // We don't 'await' here to allow background loading, 
        // OR we can await to be safe and sequential.
        // Let's await to be safe against concurrent limits.
        await loadCategory(cat['key']!);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // TRENDING
  // ─────────────────────────────────────────────────────────
  Future<void> loadTrending({bool forceRefresh = false}) async {
    trendingState = LoadState.loading;
    notifyListeners();

    try {
      final oldNews = List<Article>.from(trendingNews);
      if (forceRefresh) await _cache.clearKey(AppConstants.prefsTrending);

      final cached = await _cache.loadArticles(AppConstants.prefsTrending);
      if (cached != null) {
        trendingNews = cached;
        trendingState = LoadState.loaded;
        notifyListeners();
        return;
      }

      final fresh = await _service.fetchTrending();
      
      // If we did a force refresh and the newest article is the same, shuffle the results
      if (forceRefresh && oldNews.isNotEmpty && fresh.isNotEmpty) {
        if (oldNews.first.title == fresh.first.title) {
          fresh.shuffle();
        }
      }
      
      trendingNews = fresh;
      await _cache.saveArticles(AppConstants.prefsTrending, fresh);
      trendingState = LoadState.loaded;
    } catch (e) {
      // Fallback to stale cache if API fails
      final stale = await _cache.loadArticles(AppConstants.prefsTrending, ignoreExpiration: true);
      if (stale != null && stale.isNotEmpty) {
        trendingNews = stale;
        trendingState = LoadState.loaded;
      } else {
        trendingState = LoadState.error;
        errorMessage = e.toString();
      }
    }

    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────
  // CATEGORY
  // ─────────────────────────────────────────────────────────
  Future<void> loadCategory(
    String category, {
    bool forceRefresh = false,
  }) async {
    categoryStates[category] = LoadState.loading;
    notifyListeners();

    try {
      final oldCategoryNews = List<Article>.from(categoryNews[category] ?? []);
      final key = AppConstants.prefsCategory(category);
      if (forceRefresh) await _cache.clearKey(key);

      final cached = await _cache.loadArticles(key);
      if (cached != null) {
        categoryNews[category] = cached;
        categoryStates[category] = LoadState.loaded;
        notifyListeners();
        return;
      }

      final fresh = await _service.fetchCategory(category);
      
      // If we did a force refresh and the newest article is the same, shuffle the results
      if (forceRefresh && oldCategoryNews.isNotEmpty && fresh.isNotEmpty) {
        if (oldCategoryNews.first.title == fresh.first.title) {
          fresh.shuffle();
        }
      }

      categoryNews[category] = fresh;
      await _cache.saveArticles(key, fresh);
      categoryStates[category] = LoadState.loaded;
    } catch (e) {
      // Fallback to stale cache if API fails
      final stale = await _cache.loadArticles(key, ignoreExpiration: true);
      if (stale != null && stale.isNotEmpty) {
        categoryNews[category] = stale;
        categoryStates[category] = LoadState.loaded;
      } else {
        categoryStates[category] = LoadState.error;
        errorMessage = e.toString();
      }
    }

    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────
  // SEARCH
  // ─────────────────────────────────────────────────────────
  Future<void> searchNews(String query) async {
    if (query.trim().isEmpty) return;

    lastSearchQuery = query;
    searchState = LoadState.loading;
    notifyListeners();

    try {
      // Try cache first (keyed by query)
      final cacheKey =
          '${AppConstants.prefsSearch}_${query.toLowerCase().replaceAll(' ', '_')}';
      final cached = await _cache.loadArticles(cacheKey);
      if (cached != null) {
        searchResults = cached;
        searchState = LoadState.loaded;
        notifyListeners();
        return;
      }

      final fresh = await _service.fetchSearch(query);
      searchResults = fresh;
      await _cache.saveArticles(cacheKey, fresh);
      searchState = LoadState.loaded;
    } catch (e) {
      // Fallback to stale cache if API fails
      final stale = await _cache.loadArticles(cacheKey, ignoreExpiration: true);
      if (stale != null && stale.isNotEmpty) {
        searchResults = stale;
        searchState = LoadState.loaded;
      } else {
        searchState = LoadState.error;
        errorMessage = e.toString();
      }
    }

    notifyListeners();
  }

  void clearSearch() {
    searchResults = [];
    searchState = LoadState.idle;
    lastSearchQuery = '';
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────
  void setSelectedCategory(String cat) {
    selectedCategory = cat;
    notifyListeners();
  }

  /// Section 2: first 5 of selected category
  List<Article> get section2Articles {
    final list = categoryNews[selectedCategory] ?? [];
    return list.take(5).toList();
  }

  /// Section 3: 6th article of each category (index 5)
  List<Map<String, dynamic>> get section3Items {
    return AppConstants.categories
        .map((cat) {
          final list = categoryNews[cat['key']!] ?? [];
          return {'category': cat, 'article': list.length > 5 ? list[5] : null};
        })
        .where((item) => item['article'] != null)
        .toList();
  }

  /// Full list for category page
  List<Article> articlesForCategory(String category) {
    return categoryNews[category] ?? [];
  }

  // Pull-to-refresh: refresh everything
  Future<void> refreshAll() async {
    await Future.wait([
      loadTrending(forceRefresh: true),
      ...AppConstants.categories.map(
        (c) => loadCategory(c['key']!, forceRefresh: true),
      ),
    ]);
  }
}
