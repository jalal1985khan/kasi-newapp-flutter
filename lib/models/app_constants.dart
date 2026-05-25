import 'package:flutter/material.dart';
import '../services/api_constants.dart';

class AppConstants {
  static const String apiKey = 'dummy_key_backend_will_use_env';
  static const String baseUrl = '${ApiConstants.baseUrl}api/flutter/news';
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
