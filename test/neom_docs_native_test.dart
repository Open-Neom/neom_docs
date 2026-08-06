import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_docs/neom_docs.dart';
import 'package:xml/xml.dart';

void main() {
  group('NeomDocxService.extractText (native OOXML)', () {
    test('extracts paragraphs from a python-docx generated fixture', () {
      final bytes = File('test/fixtures/sample.docx').readAsBytesSync();
      final text = NeomDocxService.extractText(bytes);

      final lines = text.split('\n');
      expect(lines[0], 'Informe de Resultados');
      expect(lines[1], 'Texto con negrita y acentos: áéíóú ñ.');
      expect(lines[2], ''); // empty paragraph preserved
      expect(lines[3], 'Primer elemento');
      expect(lines[4], 'Segundo elemento');
    });

    test('roundtrip: generateFromMarkdown → extractText', () {
      final bytes = NeomDocxService.generateFromMarkdown(
        content: '# Título\n\nTexto **negrita** y más\n\n- viñeta uno\n- viñeta dos\n\n1. numerado',
      );
      final text = NeomDocxService.extractText(bytes);

      expect(text, contains('Título'));
      expect(text, contains('Texto negrita y más'));
      expect(text, contains('viñeta uno'));
      expect(text, contains('viñeta dos'));
      expect(text, contains('numerado'));
    });
  });

  group('NeomExcelService (native OOXML)', () {
    const csv = 'Producto,Cantidad,Precio\n'
        'Manzana,10,12.5\n'
        'Caja grande,"1,234",7\n'
        'Texto "con comillas",3,4.5';

    test('generateFromCsv builds valid XLSX structure with typed cells', () {
      final bytes = NeomExcelService.generateFromCsv(csvContent: csv);

      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]));

      final sheetFile = archive.files.firstWhere(
        (f) => f.name == 'xl/worksheets/sheet1.xml',
      );
      final sheet = XmlDocument.parse(
        utf8.decode(sheetFile.content as List<int>),
      );

      // Header cells carry the bold style index s="1"
      final headerRow = sheet.findAllElements('row').first;
      for (final cell in headerRow.findAllElements('c')) {
        expect(cell.getAttribute('s'), '1');
      }

      // Numeric detection: B2 is an int cell, C2 a double cell
      final cells = {
        for (final c in sheet.findAllElements('c')) c.getAttribute('r'): c,
      };
      expect(cells['B2']!.getAttribute('t'), isNull);
      expect(cells['B2']!.getElement('v')!.innerText, '10');
      expect(cells['C2']!.getElement('v')!.innerText, '12.5');
      // "1,234" is normalized to the number 1234 (thousands separator)
      expect(cells['B3']!.getElement('v')!.innerText, '1234');
      // Text with quotes: the simple CSV parser strips quote delimiters
      // (identical behavior to the previous excel-based implementation)
      expect(cells['A4']!.getAttribute('t'), 'inlineStr');
      expect(cells['A4']!.findAllElements('t').single.innerText,
          'Texto con comillas');
    });

    test('readSheets roundtrips generateFromCsv (inlineStr storage)', () {
      final bytes = NeomExcelService.generateFromCsv(csvContent: csv);
      final sheets = NeomExcelService.readSheets(bytes);

      expect(sheets.keys, ['Datos']);
      final rows = sheets['Datos']!;
      expect(rows[0], ['Producto', 'Cantidad', 'Precio']);
      expect(rows[1], ['Manzana', '10', '12.5']);
      expect(rows[2], ['Caja grande', '1234', '7']);
      expect(rows[3], ['Texto con comillas', '3', '4.5']);
    });

    test('readSheets reads sharedStrings-based XLSX (real Excel storage)', () {
      // Minimal XLSX using sharedStrings, as produced by desktop Excel.
      final archive = Archive();
      void add(String name, String content) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add('[Content_Types].xml', '''<?xml version="1.0"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>''');
      add('_rels/.rels', '''<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
      add('xl/workbook.xml', '''<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Hoja1" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
      add('xl/_rels/workbook.xml.rels', '''<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''');
      add('xl/sharedStrings.xml', '''<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">
  <si><t>Nombre</t></si>
  <si><t>Ciudad de México</t></si>
  <si><t>Total</t></si>
</sst>''');
      add('xl/worksheets/sheet1.xml', '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>2</v></c></row>
    <row r="2"><c r="A2" t="s"><v>1</v></c><c r="C2"><v>99.5</v></c></row>
  </sheetData>
</worksheet>''');

      final encoded = ZipEncoder().encode(archive);
      // ignore: dead_null_aware_expression — archive 3.x returns List<int>?
      final sheets = NeomExcelService.readSheets(
        Uint8List.fromList(encoded ?? []),
      );

      expect(sheets.keys, ['Hoja1']);
      // Row 2 has a gap at B2: position-padded with ''
      expect(sheets['Hoja1']![1], ['Ciudad de México', '', '99.5']);
      expect(sheets['Hoja1']![0], ['Nombre', 'Total']);
    });

    test('extractCsvFromMarkdown and suggestFilename keep working', () {
      const md = 'Texto previo\n\n```csv\nA,B\n1,2\n```\n\nTexto posterior';
      expect(NeomExcelService.extractCsvFromMarkdown(md), 'A,B\n1,2');
      expect(NeomExcelService.extractCsvFromMarkdown('sin csv'), isNull);
      expect(
        NeomExcelService.suggestFilename('Ventas por mes\nx,1'),
        'neom_ventas_por_mes.xlsx',
      );
    });

    test('golden artifact for external validation (openpyxl)', () {
      final bytes = NeomExcelService.generateFromCsv(csvContent: csv);
      File('test/out/golden.xlsx').writeAsBytesSync(bytes, flush: true);

      final docxBytes = NeomDocxService.generateFromMarkdown(
        content: '# Reporte\n\nPárrafo con **énfasis**.\n\n- punto',
      );
      File('test/out/generated.docx').writeAsBytesSync(docxBytes, flush: true);
    });
  });
}
