// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Trigger a generic file download in the browser.
///
/// Works for any file type — DOCX, XLSX, PNG, etc.
/// Uses Blob + URL.createObjectURL pattern (same as pdf_download_web).
void downloadFileBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
