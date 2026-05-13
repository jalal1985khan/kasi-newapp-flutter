import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/article.dart';
import '../models/app_constants.dart';

class NewsService {
  Future<List<Article>> fetchTrending() async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/top-headlines'
      '?country=${AppConstants.country}'
      '&pageSize=20'
      '&apiKey=${AppConstants.apiKey}',
    );
    return _fetch(uri);
  }

  Future<List<Article>> fetchCategory(String category) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/top-headlines'
      '?country=${AppConstants.country}'
      '&category=$category'
      '&pageSize=20'
      '&apiKey=${AppConstants.apiKey}',
    );
    return _fetch(uri, category: category);
  }

  Future<List<Article>> fetchSearch(String query) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/everything'
      '?q=${Uri.encodeComponent(query)}'
      '&sortBy=publishedAt'
      '&pageSize=20'
      '&apiKey=${AppConstants.apiKey}',
    );
    return _fetch(uri);
  }

  Future<List<Article>> _fetch(Uri uri, {String? category}) async {
    print('Fetching news from: $uri');
    final response = await http.get(uri);
    print('News API response: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List raw = data['articles'] ?? [];
      return raw
          .map((j) => Article.fromJson(j, category: category))
          .where((a) => a.title.isNotEmpty && a.title != '[Removed]')
          .toList();
    } else {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
  }
}
