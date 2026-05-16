class SignedInUserDetails {
  final bool success;
  final String? accessToken;
  final String? refreshToken;
  final User? user;

  SignedInUserDetails({
    required this.success,
    this.accessToken,
    this.refreshToken,
    this.user,
  });

  factory SignedInUserDetails.fromJson(Map<String, dynamic> json) {
    return SignedInUserDetails(
      success: json['success'] ?? false,
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'user': user?.toJson(),
    };
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String username;
  final String role;
  final String tenantId;
  final String? employeeId;
  final bool isActive;
  final String? profileImage;



  User({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.role,
    required this.tenantId,
    this.employeeId,
    required this.isActive,
    this.profileImage,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      tenantId: json['tenantId'] ?? '',
      employeeId: json['employeeId'],
      isActive: json['isActive'] ?? false,
      profileImage: json['profileImage'] ?? json['profile_image'] ?? json['avatar'] ?? json['image'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'username': username,
      'role': role,
      'tenantId': tenantId,
      'employeeId': employeeId,
      'isActive': isActive,
      'profileImage': profileImage,
    };
  }
}
