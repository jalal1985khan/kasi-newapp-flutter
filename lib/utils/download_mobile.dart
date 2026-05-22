import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as dev;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Downloads a file to the most appropriate Android directory.
///
/// - On Android 13+ (SDK 33+): saves to public Downloads, no permission needed.
/// - On Android 10–12 (SDK 29–32): saves to public Downloads using scoped storage.
/// - On Android 9 and below (SDK < 29): requests WRITE_EXTERNAL_STORAGE permission,
///   then saves to public Downloads. Falls back to app-specific external storage
///   if permission is denied.
///
/// Automatically opens the file after saving.
/// Handles duplicate filenames by appending a counter (e.g. report_1.pdf).
///
/// Returns the absolute path where the file was saved, or null on failure.
///
/// Required packages in pubspec.yaml:
/// ```yaml
/// dependencies:
///   device_info_plus: ^10.0.0
///   open_file: ^3.5.10
///   path_provider: ^2.1.0
///   permission_handler: ^11.0.0
/// ```
///
/// Required in AndroidManifest.xml (android/app/src/main/AndroidManifest.xml):
/// ```xml
/// <!-- For Android 9 and below -->
/// <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
///     android:maxSdkVersion="28"/>
/// <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
///     android:maxSdkVersion="28"/>
/// ```
Future<String?> downloadFile(Uint8List bytes, String fileName) async {
  try {
    final directory = await _resolveDownloadDirectory();

    if (directory == null) {
      throw Exception('Could not resolve a download directory on this device.');
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final String filePath = await _resolveUniqueFilePath(directory, fileName);
    final File file = File(filePath);

    await file.writeAsBytes(bytes, flush: true);
    dev.log('File saved: $filePath');

    await _openFile(filePath);

    return filePath;
  } catch (e, stackTrace) {
    dev.log('downloadFile failed', error: e, stackTrace: stackTrace);
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Resolves the best available download directory for the current Android version.
Future<Directory?> _resolveDownloadDirectory() async {
  final int sdkInt = await _getAndroidSdkInt();

  // Android 13+ — scoped storage, no permission required for public Downloads
  if (sdkInt >= 33) {
    return _publicDownloadsDir();
  }

  // Android 10–12 — scoped storage enforced, but public Downloads still accessible
  if (sdkInt >= 29) {
    return _publicDownloadsDir();
  }

  // Android 9 and below — requires WRITE_EXTERNAL_STORAGE permission
  final bool granted = await _requestLegacyStoragePermission();

  if (granted) {
    final Directory? publicDir = _publicDownloadsDir();
    if (publicDir != null) return publicDir;
  } else {
    dev.log(
      'Storage permission denied on Android $sdkInt. '
      'Falling back to app-specific external storage.',
    );
  }

  // Fallback: app-specific external storage (no permission needed, but
  // deleted when app is uninstalled and not visible in Files app)
  return await _appSpecificExternalDirectory();
}

/// Returns the public Downloads directory, or null if it does not exist.
Directory? _publicDownloadsDir() {
  // EXTERNAL_STORAGE env variable is the most reliable way to get the
  // external storage root on Android without a plugin.
  final String root =
      Platform.environment['EXTERNAL_STORAGE'] ?? '/storage/emulated/0';
  final Directory dir = Directory('$root/Download');
  return dir;
}

/// Fallback: app-specific external downloads directory.
Future<Directory?> _appSpecificExternalDirectory() async {
  final List<Directory>? dirs = await getExternalStorageDirectories(
    type: StorageDirectory.downloads,
  );
  if (dirs != null && dirs.isNotEmpty) return dirs.first;

  // Last resort: app-specific external root
  return await getExternalStorageDirectory();
}

/// Requests WRITE_EXTERNAL_STORAGE (only meaningful on Android < 29).
Future<bool> _requestLegacyStoragePermission() async {
  final PermissionStatus status = await Permission.storage.request();

  if (status.isPermanentlyDenied) {
    dev.log(
      'Storage permission permanently denied. '
      'User must enable it from app settings.',
    );
  }

  return status.isGranted;
}

/// Reads the Android SDK version using device_info_plus.
Future<int> _getAndroidSdkInt() async {
  final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
  return info.version.sdkInt;
}

/// Returns a file path that does not collide with an existing file.
///
/// If `dir/fileName` already exists, tries `dir/fileName_1.ext`,
/// `dir/fileName_2.ext`, and so on until a free slot is found.
Future<String> _resolveUniqueFilePath(Directory dir, String fileName) async {
  String candidate = '${dir.path}/$fileName';

  if (!await File(candidate).exists()) return candidate;

  final int dotIndex = fileName.lastIndexOf('.');
  final String name = dotIndex != -1
      ? fileName.substring(0, dotIndex)
      : fileName;
  final String ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';

  int counter = 1;
  while (await File(candidate).exists()) {
    candidate = '${dir.path}/${name}_$counter$ext';
    counter++;
  }

  return candidate;
}

/// Opens the file with the default app registered for its MIME type.
/// Logs a warning if no app can handle the file — does NOT throw,
/// because the file was already saved successfully at this point.
Future<void> _openFile(String filePath) async {
  final OpenResult result = await OpenFile.open(filePath);

  if (result.type != ResultType.done) {
    dev.log(
      'File saved but could not be opened automatically. '
      'Reason: ${result.type} — ${result.message}',
    );
  }
}
