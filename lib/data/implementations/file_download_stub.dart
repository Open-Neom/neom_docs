import 'dart:typed_data';

/// Stub for non-web platforms — will use path_provider + share later.
void downloadFileBytes(Uint8List bytes, String filename, String mimeType) {
  // TODO: Implement for mobile using path_provider + share/open
  throw UnsupportedError('File download not yet implemented for this platform');
}
