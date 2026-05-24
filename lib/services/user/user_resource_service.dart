import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../api_constants.dart';
import '../../models/admin/website_resource.dart';

class UserResourceService {
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getAccessToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<WebsiteResource>> getResources() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.flutterResources}'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List list = data['resources'] ?? [];
          return list.map((item) => WebsiteResource.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching user resources: $e');
      return [];
    }
  }
}
