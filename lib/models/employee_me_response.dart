class EmployeeMeResponse {
  final bool success;
  final User? user;
  final EmployeeData? employeeData;
  final List<EmployeeData> records;
  final String? batchId;
  final double totalCredits;
  final double totalDebits;
  final double totalValue;

  EmployeeMeResponse({
    required this.success,
    this.user,
    this.employeeData,
    this.records = const [],
    this.batchId,
    this.totalCredits = 0,
    this.totalDebits = 0,
    this.totalValue = 0,
  });

  factory EmployeeMeResponse.fromJson(Map<String, dynamic> json) {
    var recordsList = <EmployeeData>[];
    if (json['records'] != null) {
      recordsList = (json['records'] as List)
          .map((i) => EmployeeData.fromJson(i))
          .toList();
    }

    return EmployeeMeResponse(
      success: json['success'] ?? false,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      employeeData: json['employeeData'] != null
          ? EmployeeData.fromJson(json['employeeData'])
          : null,
      records: recordsList,
      batchId: json['batchId'],
      totalCredits: (json['totalCredits'] ?? 0).toDouble(),
      totalDebits: (json['totalDebits'] ?? 0).toDouble(),
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class User {
  final String id;
  final String name;
  final String username;
  final String? employeeId;
  final bool isActive;
  final String? profileImage;

  User({
    required this.id,
    required this.name,
    required this.username,
    this.employeeId,
    required this.isActive,
    this.profileImage,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      employeeId: json['employeeId'],
      isActive: json['isActive'] ?? false,
      profileImage: json['profileImage'] ?? json['profile_image'] ?? json['avatar'] ?? json['image'] ?? json['pic'] ?? json['profile_pic'],
    );
  }
}

class EmployeeData {
  final String id;
  final String employeeId;
  final String name;
  final String? batchId;
  final String? transactionType;
  final String? accountName;
  final double credits;
  final double impact;
  final double totalValue;
  final double? units;
  final double? billableUnits;
  final String? transactionStatus;
  final Map<String, dynamic> data; // Dynamic Excel fields
  final bool isEdited;
  final String updatedAt;

  EmployeeData({
    required this.id,
    required this.employeeId,
    required this.name,
    this.batchId,
    this.transactionType,
    this.accountName,
    required this.credits,
    required this.impact,
    required this.totalValue,
    this.units,
    this.billableUnits,
    this.transactionStatus,
    required this.data,
    required this.isEdited,
    required this.updatedAt,
  });

  factory EmployeeData.fromJson(Map<String, dynamic> json) {
    return EmployeeData(
      id: json['id'] ?? json['_id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      name: json['name'] ?? '',
      batchId: json['batchId'],
      transactionType: json['transactionType'],
      accountName: json['accountName'],
      credits: (json['credits'] ?? 0).toDouble(),
      impact: (json['impact'] ?? 0).toDouble(),
      totalValue: (json['totalValue'] ?? 0).toDouble(),
      units: (json['units'] ?? 0).toDouble(),
      billableUnits: (json['billableUnits'] ?? 0).toDouble(),
      transactionStatus: json['transactionStatus'],
      data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : {},
      isEdited: json['isEdited'] ?? false,
      updatedAt: json['updatedAt'] ?? '',
    );
  }
}
