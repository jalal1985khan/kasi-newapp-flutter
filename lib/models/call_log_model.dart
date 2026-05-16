class CallLog {
  final String id;
  final String? tenantId;
  final CallUser caller;
  final CallUser receiver;
  final String status;
  final int duration;
  final int limitSeconds;
  final String? recordingUrl;
  final DateTime createdAt;

  CallLog({
    required this.id,
    this.tenantId,
    required this.caller,
    required this.receiver,
    required this.status,
    required this.duration,
    required this.limitSeconds,
    this.recordingUrl,
    required this.createdAt,
  });

  factory CallLog.fromJson(Map<String, dynamic> json) {
    // Safely extract caller and receiver data
    Map<String, dynamic> callerData = {};
    if (json['callerId'] is Map) {
      callerData = Map<String, dynamic>.from(json['callerId']);
    } else if (json['caller'] is Map) {
      callerData = Map<String, dynamic>.from(json['caller']);
    }

    Map<String, dynamic> receiverData = {};
    if (json['receiverId'] is Map) {
      receiverData = Map<String, dynamic>.from(json['receiverId']);
    } else if (json['receiver'] is Map) {
      receiverData = Map<String, dynamic>.from(json['receiver']);
    }

    return CallLog(
      id: json['_id'] ?? '',
      tenantId: json['tenantId'] is Map ? json['tenantId']['_id'] : json['tenantId'],
      caller: CallUser.fromJson(callerData),
      receiver: CallUser.fromJson(receiverData),
      status: json['status'] ?? 'unknown',
      duration: json['duration'] ?? 0,
      limitSeconds: json['limitSeconds'] ?? 120,
      recordingUrl: json['recordingUrl'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class CallUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? profileImage;

  CallUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.profileImage,
  });

  factory CallUser.fromJson(Map<String, dynamic> json) {
    // Check for nested user object first
    final userMap = json['user'] is Map<String, dynamic> ? json['user'] : null;
    
    return CallUser(
      id: json['_id'] ?? json['id'] ?? userMap?['_id'] ?? userMap?['id'] ?? '',
      name: json['name'] ?? userMap?['name'] ?? 'Unknown',
      email: json['email'] ?? userMap?['email'] ?? '',
      role: json['role'] ?? userMap?['role'] ?? '',
      profileImage: json['profileImage'] ?? json['profile_image'] ?? json['avatar'] ?? json['image'] ?? 
                    userMap?['profileImage'] ?? userMap?['profile_image'] ?? userMap?['avatar'] ?? userMap?['image'],
    );
  }
}
