import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Static service for converting CSV (from LLM output) to XLSX bytes.
///
/// Pattern: stateless, no DI needed. Reusable across the Neom ecosystem.
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
    final workbook = Excel.createExcel();
    final sheet = workbook[sheetName];

    // Remove default Sheet1 if we're using a custom name
    if (sheetName != 'Sheet1') {
      workbook.delete('Sheet1');
    }

    final lines = csvContent.trim().split('\n');
    for (var row = 0; row < lines.length; row++) {
      final cells = _parseCsvLine(lines[row]);
      for (var col = 0; col < cells.length; col++) {
        final value = cells[col].trim();
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );

        // Detect numeric values
        final intVal = int.tryParse(value.replaceAll(',', ''));
        final doubleVal = intVal == null
            ? double.tryParse(value.replaceAll(',', ''))
            : null;

        if (intVal != null) {
          cell.value = IntCellValue(intVal);
        } else if (doubleVal != null) {
          cell.value = DoubleCellValue(doubleVal);
        } else {
          cell.value = TextCellValue(value);
        }

        // Bold header row
        if (row == 0) {
          cell.cellStyle = CellStyle(bold: true);
        }
      }
    }

    return Uint8List.fromList(workbook.encode()!);
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
}
