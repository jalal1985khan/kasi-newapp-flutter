import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/article.dart';
import '../models/app_constants.dart';

class CacheService {
  // Save a list of articles under a key
  Future<void> saveArticles(String key, List<Article> articles) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(articles.map((a) => a.toJson()).toList());
    await prefs.setString(key, encoded);
    // Save timestamp
    await prefs.setInt('${key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  // Load articles from cache; returns null if expired or missing
  Future<List<Article>?> loadArticles(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${key}_ts');
    if (ts == null) return null;

    final age = DateTime.now().millisecondsSinceEpoch - ts;
    final ttlMs = AppConstants.cacheTtlMinutes * 60 * 1000;
    if (age > ttlMs) return null; // Cache expired

    final raw = prefs.getString(key);
    if (raw == null) return null;

    try {
      final List decoded = jsonDecode(raw);
      return decoded.map((j) => Article.fromJson(j)).toList();
    } catch (_) {
      return null;
    }
  }

  // Force clear a specific cache key (used on pull-to-refresh)
  Future<void> clearKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove('${key}_ts');
  }
}
