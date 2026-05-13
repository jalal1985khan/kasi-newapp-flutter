import 'dart:typed_data';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart'
    if (dart.library.io) 'download_mobile.dart';

class FileDownloadHelper {
  static Future<String?> saveFile(Uint8List bytes, String fileName) {
    return downloadFile(bytes, fileName);
  }
}
