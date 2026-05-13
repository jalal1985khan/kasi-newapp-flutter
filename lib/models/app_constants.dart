import 'package:flutter/material.dart';

class AppConstants {
  static const String apiKey = '4565b267d8cf4587817a494339395f0f';
  static const String baseUrl = 'https://newsapi.org/v2';
  static const String country = 'us';

  // The 5 categories
  static const List<Map<String, dynamic>> categories = [
    {'key': 'technology', 'label': 'Technology', 'icon': Icons.computer},
    {'key': 'business', 'label': 'Business', 'icon': Icons.business_center},
    {'key': 'sports', 'label': 'Sports', 'icon': Icons.sports_soccer},
    {'key': 'health', 'label': 'Health', 'icon': Icons.medical_services},
    {'key': 'entertainment', 'label': 'Entertainment', 'icon': Icons.movie},
  ];

  // SharedPreferences cache keys
  static const String prefsTrending = 'cache_trending';
  static const String prefsSearch = 'cache_search';
  static String prefsCategory(String cat) => 'cache_category_$cat';
  static String prefsCategoryTimestamp(String cat) => 'cache_ts_$cat';
  static const String prefsTrendingTimestamp = 'cache_ts_trending';

  // Cache TTL: 1 hour
  static const int cacheTtlMinutes = 60;
}
