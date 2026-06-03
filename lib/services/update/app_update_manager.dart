import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_service.dart';
import '../chat/local_database_service.dart';
import '../../main.dart' show navigatorKey;

/// Global singleton that checks for app updates and shows the compulsory
/// update dialog on ANY screen — works whether or not the user is logged in.
///
/// Usage:
///   AppUpdateManager().checkAndShow();          // poll-based check
///   AppUpdateManager().showFromRelease(release); // real-time socket push
class AppUpdateManager {
  static final AppUpdateManager _instance = AppUpdateManager._internal();
  factory AppUpdateManager() => _instance;
  AppUpdateManager._internal();

  bool _isDialogOpen = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Polls the server, compares build numbers, and shows the update dialog
  /// if a newer version is available. Safe to call from any screen / any auth state.
  Future<void> checkAndShow() async {
    debugPrint('[AppUpdateManager] checkAndShow called. isAndroid: ${Platform.isAndroid}');
    if (!Platform.isAndroid) {
      debugPrint('[AppUpdateManager] Skipping check: platform is not Android.');
      return;
    }
    if (_isDialogOpen) {
      debugPrint('[AppUpdateManager] Skipping check: dialog is already open.');
      return;
    }

    try {
      final result = await UpdateService.checkUpdate();
      debugPrint('[AppUpdateManager] checkUpdate result: isUpdateAvailable=${result.isUpdateAvailable}, latestRelease version=${result.latestRelease?.version}, build=${result.latestRelease?.buildNumber}');
      if (result.isUpdateAvailable && result.latestRelease != null) {
        _showDialog(result.latestRelease!);
      }
    } catch (e) {
      // Silent fail — never block the user because of an update check error
      debugPrint('[AppUpdateManager] checkAndShow error: $e');
    }
  }

  /// Called when a real-time socket event fires with a release payload.
  /// Validates locally before showing dialog.
  Future<void> showFromRelease(Map<String, dynamic> releaseData) async {
    debugPrint('[AppUpdateManager] showFromRelease called with payload: $releaseData. isAndroid: ${Platform.isAndroid}');
    if (!Platform.isAndroid) return;
    if (_isDialogOpen) return;

    try {
      final release = AppReleaseInfo.fromJson(releaseData);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final prefs = await SharedPreferences.getInstance();
      final lastInstalledBuild = prefs.getInt('last_installed_release_build') ?? 0;
      final lastInstalledVersion = prefs.getString('last_installed_release_version') ?? '';

      debugPrint('[AppUpdateManager] showFromRelease check: releaseBuild=${release.buildNumber}, releaseVersion=${release.version}, currentBuild=$currentBuild, currentVersion=$currentVersion, lastInstalledBuild=$lastInstalledBuild, lastInstalledVersion=$lastInstalledVersion');
      
      final isUpdated = UpdateService.isAlreadyUpdated(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        releaseVersion: release.version,
        releaseBuild: release.buildNumber,
      ) || (lastInstalledBuild >= release.buildNumber)
        || (lastInstalledVersion == release.version);
      
      if (release.isSelfUpdateEnabled && !isUpdated) {
        _showDialog(release);
      }
    } catch (e) {
      debugPrint('[AppUpdateManager] showFromRelease error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialog — identical compulsory UI, shown via global navigator
  // ─────────────────────────────────────────────────────────────────────────

  void _showDialog(AppReleaseInfo release, {int retryCount = 0}) {
    final context = navigatorKey.currentContext;
    debugPrint('[AppUpdateManager] _showDialog called. context exists: ${context != null}, _isDialogOpen: $_isDialogOpen, retry: $retryCount');
    if (context == null) {
      if (retryCount < 6) {
        debugPrint('[AppUpdateManager] Navigator context is null. Retrying in 2 seconds...');
        Future.delayed(const Duration(seconds: 2), () {
          _showDialog(release, retryCount: retryCount + 1);
        });
      } else {
        debugPrint('[AppUpdateManager] Failed to show dialog: navigator context remained null after multiple retries.');
      }
      return;
    }
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    double downloadProgress = 0.0;
    String statusMessage = 'Downloading...';
    bool isDownloading = false;
    bool hasFailed = false;
    StreamSubscription<OtaEvent>? subscription;

    void triggerDownload(StateSetter setDialogState) async {
      setDialogState(() {
        isDownloading = true;
        hasFailed = false;
        downloadProgress = 0.0;
        statusMessage = 'Downloading...';
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_installed_release_build', release.buildNumber);
        await prefs.setString('last_installed_release_version', release.version);
        
        final dbService = LocalDatabaseService();
        await dbService.saveMetadata('last_installed_release_build', release.buildNumber.toString());
        await dbService.saveMetadata('last_installed_release_version', release.version);
        debugPrint('[AppUpdateManager] Pre-saved release build ${release.buildNumber} (${release.version}) to SharedPreferences and SQLite DB.');
      } catch (e) {
        debugPrint('[AppUpdateManager] Failed to pre-save release info: $e');
      }

      subscription?.cancel();
      subscription = UpdateService.startOtaUpdate(
        release.apkUrl,
        release.apkFileName,
      ).listen(
        (OtaEvent event) {
          setDialogState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                statusMessage = 'Downloading...';
                downloadProgress = double.tryParse(event.value ?? '0') ?? 0.0;
                break;
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                statusMessage = 'Installing update...';
                downloadProgress = 100.0;
                // Save the successfully downloaded build number in SharedPreferences as a safeguard.
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setInt('last_installed_release_build', release.buildNumber);
                  prefs.setString('last_installed_release_version', release.version);
                  debugPrint('[AppUpdateManager] Successfully marked build ${release.buildNumber} (${release.version}) as installed in SharedPreferences.');
                }).catchError((e) {
                  debugPrint('Failed to save last installed build to SharedPreferences: $e');
                });
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                hasFailed = true;
                statusMessage = 'Update download is already running.';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                hasFailed = true;
                statusMessage = 'Install permissions were not granted.';
                break;
              default:
                hasFailed = true;
                statusMessage = 'Update failed: ${event.value ?? 'Unknown error'}';
                break;
            }
          });
        },
        onError: (error) {
          setDialogState(() {
            hasFailed = true;
            statusMessage = 'Error: $error';
          });
        },
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: false,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header icon
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          color: Color(0xFF4F46E5),
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      const Text(
                        'Update Available',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Version badge
                      Text(
                        'v${release.version} (Build ${release.buildNumber})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (!isDownloading && !hasFailed) ...[
                        // Release notes
                        if (release.releaseNotes.isNotEmpty) ...[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "What's New:",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 100),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF1F5F9)),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                release.releaseNotes,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF475569),
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // File size
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              'File Size: ${(release.apkFileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Update Now button (full width, no skip)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => triggerDownload(setDialogState),
                            child: const Text(
                              'Update Now',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Downloading / Installing / Error state
                        const SizedBox(height: 10),

                        if (!hasFailed) ...[
                          SizedBox(
                            height: 8,
                            width: double.infinity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: downloadProgress / 100.0,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${downloadProgress.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 8),
                        Text(
                          statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hasFailed ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                          ),
                        ),

                        if (hasFailed || statusMessage == 'Installing update...') ...[
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => triggerDownload(setDialogState),
                              child: const Text(
                                'Retry',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Reset flag when dialog closes for any reason
      _isDialogOpen = false;
    });
  }
}
