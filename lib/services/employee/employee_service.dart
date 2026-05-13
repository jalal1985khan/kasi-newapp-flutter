import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../../models/employee_me_response.dart';

class EmployeeService {
  final _dio = DioClient().dio;

  Future<EmployeeMeResponse> getEmployeeMe() async {
    try {
      final response = await _dio.get(ApiConstants.employeeMe);
      if (response.statusCode == 200) {
        return EmployeeMeResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to load employee data');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Unknown error occurred');
    }
  }
}
