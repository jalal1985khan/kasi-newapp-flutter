import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../api_constants.dart';
import '../../models/admin/website_resource.dart';

class AdminResourceService {
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
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminResources}'),
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
      print('Error fetching resources: $e');
      return [];
    }
  }

  Future<bool> createResource(String name, String url, int sNo) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminResources}'),
        headers: await _getHeaders(),
        body: json.encode({
          'name': name,
          'url': url,
          'sNo': sNo,
        }),
      );

      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('Error creating resource: $e');
      return false;
    }
  }

  Future<bool> updateResource(String id, Map<String, dynamic> updates) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminResources}/$id'),
        headers: await _getHeaders(),
        body: json.encode(updates),
      );

      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('Error updating resource: $e');
      return false;
    }
  }

  Future<bool> deleteResource(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminResources}/$id'),
        headers: await _getHeaders(),
      );

      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('Error deleting resource: $e');
      return false;
    }
  }
}
