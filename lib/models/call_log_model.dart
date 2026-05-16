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
    return CallLog(
      id: json['_id'],
      tenantId: json['tenantId'] is Map ? json['tenantId']['_id'] : json['tenantId'],
      caller: CallUser.fromJson(json['callerId']),
      receiver: CallUser.fromJson(json['receiverId']),
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
    return CallUser(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Unknown',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      profileImage: json['profileImage'],
    );
  }
}
