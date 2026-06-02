import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import '../api_constants.dart';
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
        // - The backend build number is higher than the running application build number
        final isAvailable = release.isSelfUpdateEnabled && (release.buildNumber > currentBuild);

        print('[UpdateService] Update available: $isAvailable. Backend build: ${release.buildNumber}, Self update enabled: ${release.isSelfUpdateEnabled}');

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
