import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import '../dio_client.dart';

class AppReleaseInfo {
  final String id;
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String apkFileName;
  final int apkFileSize;
  final bool isSelfUpdateEnabled;
  final String releaseNotes;

  AppReleaseInfo({
    required this.id,
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.apkFileName,
    required this.apkFileSize,
    required this.isSelfUpdateEnabled,
    required this.releaseNotes,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    return AppReleaseInfo(
      id: json['id'] ?? '',
      version: json['version'] ?? '',
      buildNumber: json['buildNumber'] ?? 0,
      apkUrl: json['apkUrl'] ?? '',
      apkFileName: json['apkFileName'] ?? '',
      apkFileSize: json['apkFileSize'] ?? 0,
      isSelfUpdateEnabled: json['isSelfUpdateEnabled'] ?? false,
      releaseNotes: json['releaseNotes'] ?? '',
    );
  }
}

class UpdateCheckResult {
  final bool isUpdateAvailable;
  final AppReleaseInfo? latestRelease;
  final String currentVersion;
  final int currentBuildNumber;

  UpdateCheckResult({
    required this.isUpdateAvailable,
    this.latestRelease,
    required this.currentVersion,
    required this.currentBuildNumber,
  });
}

class UpdateService {
  static final Dio _dio = DioClient().dio;

  /// Helper to compare semantic versions (e.g. "7.0.1" >= "6.1.2")
  static bool isVersionGreaterOrEqual(String current, String latest) {
    try {
      final currentClean = current.replaceAll('v', '').trim();
      final latestClean = latest.replaceAll('v', '').trim();
      
      final currentParts = currentClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = latestClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      final maxLength = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;
      for (int i = 0; i < maxLength; i++) {
        final cVal = i < currentParts.length ? currentParts[i] : 0;
        final lVal = i < latestParts.length ? latestParts[i] : 0;
        if (cVal > lVal) return true;
        if (cVal < lVal) return false;
      }
      return true; // equal
    } catch (_) {
      return current.trim() == latest.trim();
    }
  }

  /// Evaluates if the device's running app matches or exceeds the backend release version and build.
  static bool isAlreadyUpdated({
    required String currentVersion,
    required int currentBuild,
    required String releaseVersion,
    required int releaseBuild,
  }) {
    // If the local build number is equal or greater, it's definitely updated or newer.
    if (currentBuild >= releaseBuild) return true;
    
    // If build number is less, but semantic version is equal or greater (e.g. installed via different builder),
    // we also consider it updated to avoid showing redundant updates.
    if (isVersionGreaterOrEqual(currentVersion, releaseVersion)) return true;
    
    return false;
  }

  /// Queries the public version endpoint and compares against local package info.
  static Future<UpdateCheckResult> checkUpdate() async {
    try {
      // 1. Fetch local package version metadata
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      print('[UpdateService] Local version: $currentVersion, Build: $currentBuild');

      // 2. Query public endpoint `/api/app-version`
      final response = await _dio.get('api/app-version');
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final latestData = response.data['latestRelease'];
        
        if (latestData == null) {
          return UpdateCheckResult(
            isUpdateAvailable: false,
            currentVersion: currentVersion,
            currentBuildNumber: currentBuild,
          );
        }

        final release = AppReleaseInfo.fromJson(latestData);

        // Update is available if:
        // - Uploader enabled dynamic self update toggling (isSelfUpdateEnabled is true)
        // - The app is not already updated
        final isUpdated = isAlreadyUpdated(
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          releaseVersion: release.version,
          releaseBuild: release.buildNumber,
        );
        final isAvailable = release.isSelfUpdateEnabled && !isUpdated;

        print('[UpdateService] Update available: $isAvailable. Backend build: ${release.buildNumber}, version: ${release.version}, Self update enabled: ${release.isSelfUpdateEnabled}');

        return UpdateCheckResult(
          isUpdateAvailable: isAvailable,
          latestRelease: release,
          currentVersion: currentVersion,
          currentBuildNumber: currentBuild,
        );
      } else {
        throw Exception(response.data['error'] ?? 'Invalid response from version API.');
      }
    } catch (e) {
      print('[UpdateService] Failed to check for app updates: $e');
      // Return a negative result on network failure so the user is not blocked
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        return UpdateCheckResult(
          isUpdateAvailable: false,
          currentVersion: packageInfo.version,
          currentBuildNumber: int.tryParse(packageInfo.buildNumber) ?? 0,
        );
      } catch (_) {
        return UpdateCheckResult(
          isUpdateAvailable: false,
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
        );
      }
    }
  }

  /// Initiates OTA update download and triggers native Android installer.
  static Stream<OtaEvent> startOtaUpdate(String url, String apkFileName) {
    try {
      print('[UpdateService] Launching OTA Update download for url: $url');
      return OtaUpdate().execute(
        url,
        destinationFilename: apkFileName,
      );
    } catch (e) {
      print('[UpdateService] Error initiating OTA execute: $e');
      rethrow;
    }
  }
}
