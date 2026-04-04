import 'package:flutter/services.dart';
import 'package:sint_sentinel/sint_sentinel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/doc_theme.dart';

/// Generates beautifully styled PDFs with configurable branding.
///
/// Features:
/// - Accent bar header with configurable theme
/// - Professional typography (Open Sans family)
/// - Brand footprint on every page
/// - Markdown parsing: headers, bold, lists, horizontal rules, checkboxes
/// - Date stamp on first page
class NeomPdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _semiBold;
  static pw.Font? _light;

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static String _formatDate(DateTime dt) => '${dt.day} de ${_months[dt.month - 1]} ${dt.year}';
  static String _formatDateShort(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  /// Load font assets (call once at startup or lazily)
  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    try {
      final regularData = await rootBundle.load('packages/neom_docs/assets/fonts/OpenSans-Regular.ttf');
      final boldData = await rootBundle.load('packages/neom_docs/assets/fonts/OpenSans-Bold.ttf');
      final semiBoldData = await rootBundle.load('packages/neom_docs/assets/fonts/OpenSans-SemiBold.ttf');
      final lightData = await rootBundle.load('packages/neom_docs/assets/fonts/OpenSans-Light.ttf');

      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
      _semiBold = pw.Font.ttf(semiBoldData);
      _light = pw.Font.ttf(lightData);
    } catch (e, st) {
      Logger().e('neom_docs._ensureFonts failed', error: e, stackTrace: st);
    }
  }

  /// Generate a PDF from markdown-like content.
  ///
  /// Returns the raw PDF bytes ready for download.
  /// [title] is used as the document metadata title.
  /// [content] is the markdown-like text to render.
  /// [theme] allows customizing colors and branding.
  static Future<Uint8List> generateFromMarkdown({
    required String content,
    String title = 'Documento',
    DocTheme theme = DocTheme.standard,
  }) async {
    await _ensureFonts();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        italic: _light,
      ),
    );

    final bodyWidgets = _parseMarkdownToWidgets(content, theme);
    final dateStr = _formatDate(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.only(
          left: 50, right: 50, top: 30, bottom: 40,
        ),
        header: (context) => _buildHeader(title, dateStr, context, theme),
        footer: (context) => _buildFooter(context, theme),
        build: (context) => bodyWidgets,
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════════
  // Markdown → PDF widget parsing
  // ═══════════════════════════════════════════

  /// Parse markdown-like content into PDF widgets
  static List<pw.Widget> _parseMarkdownToWidgets(String content, DocTheme theme) {
    final widgets = <pw.Widget>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();

      // Skip empty lines (add spacing)
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }

      // ── H1: Large title with accent underline ──
      if (line.startsWith('# ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                line.substring(2).trim(),
                style: pw.TextStyle(
                  font: _bold,
                  fontSize: 20,
                  color: PdfColors.grey900,
                  letterSpacing: 0.3,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: 40,
                height: 2.5,
                color: theme.accentColor,
              ),
            ],
          ),
        ));
        continue;
      }

      // ── H2: Section header with accent left border ──
      if (line.startsWith('## ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
          child: pw.Container(
            padding: const pw.EdgeInsets.only(left: 10, top: 2, bottom: 2),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: theme.accentColor, width: 3),
              ),
            ),
            child: pw.Text(
              line.substring(3).trim(),
              style: pw.TextStyle(
                font: _bold,
                fontSize: 15,
                color: PdfColors.grey900,
              ),
            ),
          ),
        ));
        continue;
      }

      // ── H3: Subsection header ──
      if (line.startsWith('### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(
            line.substring(4).trim(),
            style: pw.TextStyle(
              font: _semiBold,
              fontSize: 13,
              color: theme.accentDark,
              letterSpacing: 0.2,
            ),
          ),
        ));
        continue;
      }

      // ── Horizontal rule ──
      if (line.trim() == '---' || line.trim() == '***') {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: pw.Container(
                  width: 4, height: 4,
                  decoration: pw.BoxDecoration(
                    color: theme.accentColor,
                    shape: pw.BoxShape.circle,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              ),
            ],
          ),
        ));
        continue;
      }

      // ── Checkbox list items: - [ ] or - [x] ──
      final checkboxMatch = RegExp(r'^[\s]*[-*]\s+\[([ xX])\]\s+(.*)').firstMatch(line);
      if (checkboxMatch != null) {
        final isChecked = checkboxMatch.group(1)!.toLowerCase() == 'x';
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2, right: 8),
                child: pw.Container(
                  width: 14, height: 14,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: isChecked ? theme.accentColor : PdfColors.grey500,
                      width: 1.5,
                    ),
                    borderRadius: pw.BorderRadius.circular(2),
                    color: isChecked ? theme.accentColor : PdfColors.white,
                  ),
                  alignment: pw.Alignment.center,
                  child: isChecked
                      ? pw.Text('✓', style: pw.TextStyle(
                          font: _bold, fontSize: 9, color: PdfColors.white,
                        ))
                      : pw.SizedBox(),
                ),
              ),
              pw.Expanded(child: _buildRichText(checkboxMatch.group(2)!.trim())),
            ],
          ),
        ));
        continue;
      }

      // ── Bullet list items ──
      final bulletMatch = RegExp(r'^[\s]*[-*•]\s+(.*)').firstMatch(line);
      if (bulletMatch != null) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 5, right: 8),
                child: pw.Container(
                  width: 5, height: 5,
                  decoration: pw.BoxDecoration(
                    color: theme.accentColor,
                    shape: pw.BoxShape.circle,
                  ),
                ),
              ),
              pw.Expanded(child: _buildRichText(bulletMatch.group(1)!.trim())),
            ],
          ),
        ));
        continue;
      }

      // ── Numbered list items ──
      final numberedMatch = RegExp(r'^[\s]*(\d+)\.\s+(.*)').firstMatch(line);
      if (numberedMatch != null) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 22, height: 22,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: theme.accentColor.flatten(),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  numberedMatch.group(1)!,
                  style: pw.TextStyle(
                    font: _bold,
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _buildRichText(numberedMatch.group(2)!.trim())),
            ],
          ),
        ));
        continue;
      }

      // ── Regular paragraph ──
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: _buildRichText(line),
      ));
    }

    return widgets;
  }

  /// Build a RichText widget that handles **bold** inline markers
  static pw.Widget _buildRichText(String text) {
    final parts = text.split(RegExp(r'\*\*'));

    if (parts.length <= 1) {
      return pw.Text(
        text,
        style: pw.TextStyle(
          font: _regular,
          fontSize: 11,
          height: 1.6,
          color: PdfColors.grey800,
        ),
      );
    }

    // Alternating: even indices are normal, odd indices are bold
    final spans = <pw.InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(pw.TextSpan(
        text: parts[i],
        style: pw.TextStyle(
          font: i.isOdd ? _bold : _regular,
          fontSize: 11,
          height: 1.6,
          color: i.isOdd ? PdfColors.grey900 : PdfColors.grey800,
        ),
      ));
    }

    return pw.RichText(
      text: pw.TextSpan(children: spans),
    );
  }

  // ═══════════════════════════════════════════
  // Header & Footer
  // ═══════════════════════════════════════════

  /// Page header with accent bar and branding
  static pw.Widget _buildHeader(String title, String dateStr, pw.Context context, DocTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Accent bar at the very top ──
        pw.Container(
          width: double.infinity,
          height: 4,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [theme.accentColor, theme.accentDark],
            ),
          ),
        ),
        pw.SizedBox(height: 12),

        // ── Title row: document title + brand ──
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      font: _bold,
                      fontSize: 11,
                      color: PdfColors.grey700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (context.pageNumber == 1)
                    pw.Text(
                      dateStr,
                      style: pw.TextStyle(
                        font: _light,
                        fontSize: 9,
                        color: PdfColors.grey500,
                      ),
                    ),
                ],
              ),
            ),
            // Brand mark
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  theme.brandName,
                  style: pw.TextStyle(
                    font: _bold,
                    fontSize: 10,
                    color: theme.accentDark,
                    letterSpacing: 2.5,
                  ),
                ),
                pw.Text(
                  theme.brandVersion,
                  style: pw.TextStyle(
                    font: _light,
                    fontSize: 7,
                    color: PdfColors.grey400,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5, color: PdfColors.grey300),
        pw.SizedBox(height: 14),
      ],
    );
  }

  /// Page footer with branding and page numbers
  static pw.Widget _buildFooter(pw.Context context, DocTheme theme) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.3, color: PdfColors.grey200),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            // Left: branding
            pw.Text(
              theme.footerLeft,
              style: pw.TextStyle(
                font: _light,
                fontSize: 7,
                color: PdfColors.grey400,
                letterSpacing: 0.5,
              ),
            ),
            pw.Spacer(),
            // Center: footprint
            pw.Text(
              theme.footerCenter,
              style: pw.TextStyle(
                font: _regular,
                fontSize: 7,
                color: PdfColors.grey500,
              ),
            ),
            pw.Spacer(),
            // Right: page numbers
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(
                font: _semiBold,
                fontSize: 8,
                color: PdfColors.grey500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // Filename & title detection
  // ═══════════════════════════════════════════

  /// Detect the best filename from the content (first header or default)
  static String suggestFilename(String content, {String prefix = 'neom'}) {
    final headerMatch = RegExp(r'^#{1,3}\s+(.+)', multiLine: true).firstMatch(content);
    if (headerMatch != null) {
      final title = headerMatch.group(1)!.trim();
      final clean = title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .toLowerCase();
      if (clean.isNotEmpty && clean.length <= 50) {
        return '${prefix}_$clean.pdf';
      }
    }
    return '${prefix}_documento_${_formatDateShort(DateTime.now())}.pdf';
  }

  /// Detect a suitable document title from the content
  static String suggestTitle(String content) {
    final headerMatch = RegExp(r'^#{1,3}\s+(.+)', multiLine: true).firstMatch(content);
    if (headerMatch != null) {
      return headerMatch.group(1)!.trim().replaceAll('**', '');
    }
    return 'Documento';
  }
}
