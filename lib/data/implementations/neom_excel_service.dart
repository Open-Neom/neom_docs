import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Static service for converting CSV (from LLM output) to XLSX bytes and
/// reading XLSX files back into plain text tables.
///
/// Pattern: stateless, no DI needed. Reusable across the Neom ecosystem.
///
/// XLSX is an OOXML format = ZIP of XML files. This implementation writes
/// and reads the minimal valid structure directly with `archive` + `xml`,
/// with no third-party spreadsheet dependency:
///   [Content_Types].xml          — content type declarations (static)
///   _rels/.rels                  — root relationships (static)
///   xl/workbook.xml              — single sheet declaration (dynamic name)
///   xl/_rels/workbook.xml.rels   — workbook relationships (static)
///   xl/styles.xml                — Normal + Bold cell formats (static)
///   xl/worksheets/sheet1.xml     — THE CONTENT (dynamic — generated from CSV)
///
/// Flow:
///   1. LLM generates CSV inside a ```csv code block
///   2. [extractCsvFromMarkdown] extracts the raw CSV
///   3. [generateFromCsv] converts to XLSX bytes
///   4. Bytes are downloaded via [downloadFileBytes]
class NeomExcelService {
  /// Parse CSV string (from LLM code block) into XLSX bytes.
  ///
  /// First row is treated as header and styled bold.
  /// Numeric values are detected and stored as numbers (not strings).
  static Uint8List generateFromCsv({
    required String csvContent,
    String sheetName = 'Datos',
  }) {
    final archive = Archive();

    _addFile(archive, '[Content_Types].xml', _contentTypesXml);
    _addFile(archive, '_rels/.rels', _relsXml);
    _addFile(archive, 'xl/workbook.xml', _workbookXml(_sanitizeSheetName(sheetName)));
    _addFile(archive, 'xl/_rels/workbook.xml.rels', _workbookRelsXml);
    _addFile(archive, 'xl/styles.xml', _stylesXml);

    final lines = csvContent.trim().split('\n');
    final sheetData = StringBuffer();

    for (var row = 0; row < lines.length; row++) {
      final cells = _parseCsvLine(lines[row]);
      final rowXml = StringBuffer();

      for (var col = 0; col < cells.length; col++) {
        final value = cells[col].trim();
        if (value.isEmpty) continue;

        final ref = '${_columnLetter(col)}${row + 1}';
        // Style index 1 = bold (header row), 0 = normal.
        final style = row == 0 ? ' s="1"' : '';

        // Detect numeric values
        final intVal = int.tryParse(value.replaceAll(',', ''));
        final doubleVal = intVal == null
            ? double.tryParse(value.replaceAll(',', ''))
            : null;

        if (intVal != null) {
          rowXml.write('<c r="$ref"$style><v>$intVal</v></c>');
        } else if (doubleVal != null) {
          rowXml.write('<c r="$ref"$style><v>$doubleVal</v></c>');
        } else {
          rowXml.write(
            '<c r="$ref"$style t="inlineStr">'
            '<is><t xml:space="preserve">${_escapeXml(value)}</t></is></c>',
          );
        }
      }

      sheetData.writeln('    <row r="${row + 1}">$rowXml</row>');
    }

    _addFile(archive, 'xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
$sheetData  </sheetData>
</worksheet>''');

    final encoded = ZipEncoder().encode(archive);
    // ignore: dead_null_aware_expression — archive 3.x returns List<int>?
    return Uint8List.fromList(encoded ?? []);
  }

  /// Read an XLSX file into a map of sheet name → rows of cell texts.
  ///
  /// Supports the two standard string storages (`sharedStrings` and
  /// `inlineStr`), numbers, booleans and formula string results.
  /// Empty cells are position-padded with '' using each cell's reference,
  /// so column alignment is preserved. Dates remain as raw serial numbers.
  static Map<String, List<List<String>>> readSheets(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final file in archive) {
      if (file.isFile) files[file.name] = file.content as List<int>;
    }

    final workbookData = files['xl/workbook.xml'];
    if (workbookData == null) return {};

    // Shared strings table (optional part)
    final sharedStrings = <String>[];
    final sharedData = files['xl/sharedStrings.xml'];
    if (sharedData != null) {
      final sharedDoc = XmlDocument.parse(utf8.decode(sharedData));
      for (final si in sharedDoc.findAllElements('si')) {
        sharedStrings.add(
          si.findAllElements('t').map((node) => node.innerText).join(),
        );
      }
    }

    // Relationship id → worksheet part path
    final relTargets = <String, String>{};
    final relsData = files['xl/_rels/workbook.xml.rels'];
    if (relsData != null) {
      final relsDoc = XmlDocument.parse(utf8.decode(relsData));
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        var target = rel.getAttribute('Target') ?? '';
        if (id == null || target.isEmpty) continue;
        if (target.startsWith('/')) target = target.substring(1);
        if (!target.startsWith('xl/')) target = 'xl/$target';
        relTargets[id] = target;
      }
    }

    final result = <String, List<List<String>>>{};
    final workbookDoc = XmlDocument.parse(utf8.decode(workbookData));

    for (final sheet in workbookDoc.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? 'Sheet';
      final relId = sheet.getAttribute('r:id');
      final path = relTargets[relId];
      final sheetData = path == null ? null : files[path];
      if (sheetData == null) continue;

      final rows = <List<String>>[];
      final sheetDoc = XmlDocument.parse(utf8.decode(sheetData));

      for (final row in sheetDoc.findAllElements('row')) {
        final cells = <String>[];
        for (final cell in row.findAllElements('c')) {
          final ref = cell.getAttribute('r') ?? '';
          final colIndex = _columnIndex(ref);
          while (cells.length <= colIndex) {
            cells.add('');
          }
          cells[colIndex] = _cellText(cell, sharedStrings);
        }
        rows.add(cells);
      }

      result[name] = rows;
    }

    return result;
  }

  /// Extract CSV from markdown ```csv code block.
  ///
  /// Returns null if no CSV code block is found.
  static String? extractCsvFromMarkdown(String markdown) {
    final match = RegExp(r'```(?:csv|CSV)\n([\s\S]*?)```').firstMatch(markdown);
    return match?.group(1)?.trim();
  }

  /// Simple CSV line parser that handles quoted fields.
  ///
  /// Supports:
  ///   - Comma-separated values
  ///   - Quoted fields with commas inside: "value, with comma"
  ///   - Escaped quotes inside quoted fields: "say ""hello"""
  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;
    var i = 0;

    while (i < line.length) {
      final c = line[i];

      if (inQuotes) {
        if (c == '"') {
          // Check for escaped quote ""
          if (i + 1 < line.length && line[i + 1] == '"') {
            current.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
        } else {
          current.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          result.add(current.toString());
          current = StringBuffer();
        } else {
          current.write(c);
        }
      }

      i++;
    }

    result.add(current.toString());
    return result;
  }

  /// Suggest a filename from the CSV content.
  static String suggestFilename(String csv, {String prefix = 'neom'}) {
    final firstLine = csv.split('\n').firstOrNull ?? '';
    final cells = _parseCsvLine(firstLine);
    if (cells.isNotEmpty && cells.first.trim().isNotEmpty) {
      final name = cells.first.trim().toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      if (name.length > 3 && name.length < 40) {
        return '${prefix}_$name.xlsx';
      }
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${prefix}_tabla_$timestamp.xlsx';
  }

  // ═══════════════════════════════════════════
  // Internals
  // ═══════════════════════════════════════════

  /// Add a UTF-8 text file to the archive.
  static void _addFile(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// Text of a worksheet cell, resolving shared strings and booleans.
  static String _cellText(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');

    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((node) => node.innerText).join();
    }

    final value = cell.getElement('v')?.innerText ?? '';
    if (value.isEmpty) return '';

    switch (type) {
      case 's':
        final index = int.tryParse(value);
        return index != null && index < sharedStrings.length
            ? sharedStrings[index]
            : '';
      case 'b':
        return value == '1' ? 'true' : 'false';
      default:
        return value;
    }
  }

  /// Excel-style column letter for a zero-based index (0 → A, 26 → AA).
  static String _columnLetter(int index) {
    final buffer = StringBuffer();
    var remaining = index;
    do {
      buffer.write(String.fromCharCode(0x41 + remaining % 26));
      remaining = remaining ~/ 26 - 1;
    } while (remaining >= 0);
    return buffer.toString().split('').reversed.join();
  }

  /// Zero-based column index from a cell reference like "B7" (→ 1).
  static int _columnIndex(String cellRef) {
    var index = 0;
    for (final code in cellRef.codeUnits) {
      if (code >= 0x41 && code <= 0x5A) {
        index = index * 26 + (code - 0x41 + 1);
      } else {
        break;
      }
    }
    return index - 1;
  }

  /// Excel sheet names: max 31 chars, cannot contain [ ] : * ? / \
  static String _sanitizeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_').trim();
    if (cleaned.isEmpty) return 'Datos';
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ═══════════════════════════════════════════
  // Static XML templates — minimal valid XLSX
  // ═══════════════════════════════════════════

  static const _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

  static const _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static String _workbookXml(String sheetName) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="${_escapeXml(sheetName)}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';

  static const _workbookRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  /// Styles: cellXfs index 0 = Normal, index 1 = Bold (used on header row).
  static const _stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>''';
}
