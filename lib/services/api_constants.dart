class ApiConstants {
  // Production URLs - UPDATE THESE BEFORE BUILDING APK
  // static const String baseUrl = 'https://your-production-domain.com/';
  // static const String socketUrl = 'https://your-socket-domain.com/';

  // For local testing, use your machine's IP (e.g. http://192.168.1.100:3000)
//  Live Mode
  static const String baseUrl = 'https://test.yugsatya.com/';
  static const String socketUrl = 'https://test.yugsatya.com/';

// Local Testing Endpoint
  // static const String baseUrl = 'http://192.168.1.38:3000/';
  // static const String socketUrl = 'http://192.168.1.38:3001/';

  static const String login = 'api/flutter/auth/login';
  static const String refresh = 'api/flutter/auth/refresh';
  static const String registerFcm = 'api/flutter/auth/register-fcm';
  static const String logout = 'api/flutter/auth/logout';
  static const String changePassword = 'api/flutter/auth/change-password';
  static const String adminCallLogs = 'api/admin/call-logs';
  static const String adminBulkUpload = 'api/admin/upload';
  static const String adminDashboard = 'api/admin/dashboard';
  static const String adminEmployees = 'api/admin/employees';
  static const String adminAccounts = 'api/admin/accounts';
  static const String employeeMe = 'api/flutter/employee/me';
  static const String chatConversations = 'api/chat/conversations';
  static const String adminGroups = 'api/admin/groups';
  static const String adminResources = 'api/admin/resources';
  static const String flutterResources = 'api/flutter/resources';
  static const String uploadSpaces = 'api/upload/spaces';
  
  // Voice call endpoints
  static const String callToken = 'api/flutter/call/token';
  static const String callJoin = 'api/flutter/call/join';
  static const String callEnd = 'api/flutter/call/end';
  static const String callReject = 'api/flutter/call/reject';
  static const String callHistory = 'api/flutter/call/history';
  static const String callIce = 'api/flutter/call/ice';
  static const String callIncoming = 'api/flutter/call/incoming';
}
