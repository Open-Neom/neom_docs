# Changelog

## 1.1.0

Native OOXML implementation — drops the `excel` and `docx_to_text` packages.

### Why

`docx_to_text` 1.0.1 (latest, unmaintained) pins `xml ^6.2.2` and
`excel` 4.0.6 (latest) pins `xml <7` + `archive <4`, which made this
package unresolvable next to `pdf ^3.13.0` (xml ^7) and any module using
`image ^4.9.x` (xml ^7, archive ^4) — e.g. neomage could not run
`flutter pub get`.

### Changes

- **XLSX generation** rewritten natively over `archive` + `xml` (same
  public API: typed cells, bold header row, sheet naming). Output
  validated externally with openpyxl.
- **DOCX text extraction** rewritten natively (same behavior as
  `docxToText`, without its stray debug `print`).
- **New**: `NeomExcelService.readSheets(bytes)` — reads XLSX files
  (sharedStrings and inlineStr storage) into `Map<String, List<List<String>>>`
  for text extraction flows.
- Dependencies: removed `excel`, `docx_to_text`; added `archive`
  (`>=3.6.1 <5.0.0`) and `xml` (`>=6.3.0 <8.0.0`).
- Tests: `test/neom_docs_native_test.dart` — roundtrips, typed-cell
  assertions, sharedStrings reading, python-docx fixture extraction.

## [2026-07-25] - Dependencias Externas

## 1.0.0

Initial public release.

### Features

- **PDF generation** from markdown with professional typography (Open Sans), accent headers, page footers, and date stamping
- **DOCX generation** from markdown to valid OOXML (headings, bold, bullet/numbered lists)
- **XLSX generation** from CSV with smart type detection and header styling
- **DOCX text extraction** via `docx_to_text` for reading uploaded documents
- **Cross-platform file download** — web (Blob + createObjectURL), mobile/desktop stubs
- **Customizable theming** via `DocTheme` (accent colors, brand name, footer text)
- **Filename suggestion** based on document content headings
