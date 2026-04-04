import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docx_to_text/docx_to_text.dart';

/// Static service for converting Markdown to DOCX bytes.
///
/// DOCX is an OOXML format = ZIP of XML files.
/// Uses the `archive` package (transitive dependency) to build the ZIP.
///
/// Minimal valid DOCX structure:
///   [Content_Types].xml         — content type declarations (static)
///   _rels/.rels                 — root relationships (static)
///   word/_rels/document.xml.rels — document relationships (static)
///   word/styles.xml             — Heading1/2/3, Normal, Bold styles (static)
///   word/document.xml           — THE CONTENT (dynamic — generated from markdown)
///
/// Pattern: stateless, no DI needed. Reusable across the Neom ecosystem.
class NeomDocxService {
  /// Extract plain text from DOCX bytes.
  ///
  /// Uses the `docx_to_text` package to parse OOXML and return text content.
  /// Useful for reading user-uploaded DOCX files before sending to an LLM.
  static String extractText(Uint8List bytes) {
    return docxToText(bytes);
  }

  /// Convert markdown content to DOCX bytes.
  ///
  /// The markdown is parsed and converted to OOXML paragraph elements.
  /// Supports: # headings, **bold**, - bullets, plain paragraphs.
  static Uint8List generateFromMarkdown({
    required String content,
    String title = 'Documento',
  }) {
    final archive = Archive();

    // Add static XML files
    _addFile(archive, '[Content_Types].xml', _contentTypesXml);
    _addFile(archive, '_rels/.rels', _relsXml);
    _addFile(archive, 'word/_rels/document.xml.rels', _documentRelsXml);
    _addFile(archive, 'word/styles.xml', _stylesXml);
    _addFile(archive, 'word/numbering.xml', _numberingXml);

    // Generate dynamic document.xml from markdown
    final documentXml = _buildDocumentXml(content, title);
    _addFile(archive, 'word/document.xml', documentXml);

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded ?? []);
  }

  /// Add a UTF-8 text file to the archive.
  static void _addFile(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// Build the word/document.xml from markdown content.
  static String _buildDocumentXml(String markdown, String title) {
    final bodyXml = _markdownToOoxml(markdown);

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
  xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
  xmlns:o="urn:schemas-microsoft-com:office:office"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:v="urn:schemas-microsoft-com:vml"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:w10="urn:schemas-microsoft-com:office:word"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
  xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
  xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
  mc:Ignorable="w14 wp14">
  <w:body>
$bodyXml
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>''';
  }

  /// Convert markdown to OOXML <w:p> paragraph elements.
  static String _markdownToOoxml(String markdown) {
    final lines = markdown.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trimRight();

      if (trimmed.isEmpty) {
        buffer.writeln('    <w:p><w:pPr><w:pStyle w:val="Normal"/></w:pPr></w:p>');
        continue;
      }

      if (trimmed.startsWith('### ')) {
        buffer.writeln(_heading(trimmed.substring(4), 'Heading3'));
      } else if (trimmed.startsWith('## ')) {
        buffer.writeln(_heading(trimmed.substring(3), 'Heading2'));
      } else if (trimmed.startsWith('# ')) {
        buffer.writeln(_heading(trimmed.substring(2), 'Heading1'));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        buffer.writeln(_bullet(trimmed.substring(2)));
      } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final text = trimmed.replaceFirst(RegExp(r'^\d+\.\s'), '');
        buffer.writeln(_numbered(text));
      } else {
        buffer.writeln(_paragraph(trimmed));
      }
    }

    return buffer.toString();
  }

  static String _heading(String text, String style) {
    final runs = _parseInlineFormatting(text);
    return '    <w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>$runs</w:p>';
  }

  static String _bullet(String text) {
    final runs = _parseInlineFormatting(text);
    return '''    <w:p><w:pPr><w:pStyle w:val="ListBullet"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>$runs</w:p>''';
  }

  static String _numbered(String text) {
    final runs = _parseInlineFormatting(text);
    return '''    <w:p><w:pPr><w:pStyle w:val="ListNumber"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr>$runs</w:p>''';
  }

  static String _paragraph(String text) {
    final runs = _parseInlineFormatting(text);
    return '    <w:p><w:pPr><w:pStyle w:val="Normal"/></w:pPr>$runs</w:p>';
  }

  static String _parseInlineFormatting(String text) {
    final buffer = StringBuffer();
    final parts = text.split('**');

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;

      final escaped = _escapeXml(part);

      if (i.isOdd) {
        buffer.write('<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">$escaped</w:t></w:r>');
      } else {
        buffer.write('<w:r><w:t xml:space="preserve">$escaped</w:t></w:r>');
      }
    }

    return buffer.toString();
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Suggest a filename from the markdown content.
  static String suggestFilename(String content, {String prefix = 'neom'}) {
    final headingMatch = RegExp(r'^#{1,3}\s+(.+)', multiLine: true).firstMatch(content);
    if (headingMatch != null) {
      final title = headingMatch.group(1)!.trim().toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      if (title.length > 3 && title.length < 40) {
        return '${prefix}_$title.docx';
      }
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${prefix}_documento_$timestamp.docx';
  }

  // ═══════════════════════════════════════════
  // Static XML templates — minimal valid DOCX
  // ═══════════════════════════════════════════

  static const _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>''';

  static const _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>''';

  static const _stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
        <w:sz w:val="24"/>
        <w:szCs w:val="24"/>
        <w:lang w:val="es-MX"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="160" w:line="259" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/><w:color w:val="1F2937"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:before="240" w:after="80"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="30"/><w:szCs w:val="30"/><w:color w:val="374151"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:before="200" w:after="60"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="26"/><w:szCs w:val="26"/><w:color w:val="4B5563"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="ListBullet">
    <w:name w:val="List Bullet"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:after="60"/><w:ind w:left="720" w:hanging="360"/></w:pPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="ListNumber">
    <w:name w:val="List Number"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:after="60"/><w:ind w:left="720" w:hanging="360"/></w:pPr>
  </w:style>
</w:styles>''';

  static const _numberingXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="\u2022"/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
      <w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/></w:rPr>
    </w:lvl>
  </w:abstractNum>
  <w:abstractNum w:abstractNumId="1">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%1."/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';
}
