import 'dart:typed_data';

/// Stub for non-web platforms — will use path_provider + open_file later
void downloadPdfBytes(Uint8List bytes, String filename) {
  // TODO: Implement for mobile using path_provider + share/open
  throw UnsupportedError('PDF download not yet implemented for this platform');
}
