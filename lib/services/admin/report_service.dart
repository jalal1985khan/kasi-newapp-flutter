import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_constants.dart';
import '../auth_service.dart';

class EmployeeReport {
  final String id;
  final String name;
  final String employeeId;
  final String? email;
  final double debit; // C9
  final double credit; // C5
  final double totalValue; // C8
  final String? accountDetail;
  final DateTime? date;

  EmployeeReport({
    required this.id,
    required this.name,
    required this.employeeId,
    this.email,
    required this.debit,
    required this.credit,
    required this.totalValue,
    this.accountDetail,
    this.date,
  });

  factory EmployeeReport.fromJson(Map<String, dynamic> json) {
    return EmployeeReport(
      id: json['userId'] ?? json['_id'] ?? '',
      name: json['name'] ?? 'Unknown',
      employeeId: json['employeeId'] ?? 'N/A',
      email: json['email'] ?? 'N/A',
      debit: (json['userTotalDebits'] ?? json['impact'] ?? 0).toDouble(),
      credit: (json['userTotalCredits'] ?? json['credits'] ?? 0).toDouble(),
      totalValue: (json['userTotalValue'] ?? json['totalValue'] ?? 0).toDouble(),
      accountDetail: json['accountName'] ?? 'N/A',
      date: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }
}

class AdminReportResponse {
  final bool success;
  final List<EmployeeReport> employees;
  final double totalCredits;
  final double totalDebits;
  final double totalValue;

  AdminReportResponse({
    required this.success,
    required this.employees,
    required this.totalCredits,
    required this.totalDebits,
    required this.totalValue,
  });

  factory AdminReportResponse.fromJson(Map<String, dynamic> json) {
    var list = json['employees'] as List? ?? [];
    List<EmployeeReport> employeeList =
        list.map((i) => EmployeeReport.fromJson(i)).toList();

    return AdminReportResponse(
      success: json['success'] ?? false,
      employees: employeeList,
      totalCredits: (json['totalCredits'] ?? 0).toDouble(),
      totalDebits: (json['totalDebits'] ?? 0).toDouble(), // Added C9 Sum
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class ReportService {
  static Future<AdminReportResponse?> getBulkReport() async {
    try {
      final token = await AuthService().getAccessToken();
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminAccounts}');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdminReportResponse.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error fetching reports: $e');
      return null;
    }
  }
}
