import 'dart:typed_data';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:developer' as dev;

Future<String?> downloadFile(Uint8List bytes, String fileName) async {
  try {
    final base64Content = base64Encode(bytes);
    final anchor = html.AnchorElement(
      href:
          "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Content",
    )
      ..setAttribute("download", fileName)
      ..click();
    return "Downloads folder";
  } catch (e, stackTrace) {
    dev.log('File download failed (Web)', error: e, stackTrace: stackTrace);
    rethrow;
  }
}
