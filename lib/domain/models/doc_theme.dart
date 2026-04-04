import 'package:pdf/pdf.dart';

/// Theme configuration for document generation.
///
/// Allows customizing colors, branding, and footer text
/// for different apps using neom_docs.
class DocTheme {
  /// Primary accent color
  final PdfColor accentColor;

  /// Secondary/dark accent color
  final PdfColor accentDark;

  /// Brand name shown in header
  final String brandName;

  /// Version string shown in header
  final String brandVersion;

  /// Footer text (left side)
  final String footerLeft;

  /// Footer text (center)
  final String footerCenter;

  const DocTheme({
    this.accentColor = const PdfColor.fromInt(0xFF00E5CC),
    this.accentDark = const PdfColor.fromInt(0xFF009E8E),
    this.brandName = 'Open Neom',
    this.brandVersion = 'v1.0',
    this.footerLeft = 'Open Neom',
    this.footerCenter = 'Generated with neom_docs — Open Neom',
  });

  /// Default theme
  static const standard = DocTheme();
}
