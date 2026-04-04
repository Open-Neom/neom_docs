# neom_docs

[![pub package](https://img.shields.io/pub/v/neom_docs.svg)](https://pub.dev/packages/neom_docs)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Document generation for Flutter. Convert markdown to PDF, DOCX, and XLSX with professional styling and customizable themes.

## Features

- **PDF** — Markdown to styled PDF with accent headers, Open Sans typography, page footers, and date stamping
- **DOCX** — Markdown to valid OOXML Word documents (headings, bold, bullet/numbered lists)
- **XLSX** — CSV to Excel spreadsheets with smart type detection and header styling
- **DOCX parsing** — Extract plain text from uploaded DOCX files
- **Theming** — Customizable colors, branding, and footer text via `DocTheme`
- **Cross-platform download** — Web (Blob + URL), mobile/desktop stubs

## Installation

```yaml
dependencies:
  neom_docs: ^1.0.0
```

## Usage

### PDF Generation

```dart
import 'package:neom_docs/neom_docs.dart';

final pdfBytes = await NeomPdfService.generateFromMarkdown(
  content: '# Quarterly Report\n\n## Summary\n\n- Revenue up 15%\n- **Record** user growth',
  title: 'Q1 Report',
);

// Suggest a filename from content
final filename = NeomPdfService.suggestFilename(content);

// Download in browser
downloadPdfBytes(pdfBytes, filename);
```

### DOCX Generation

```dart
final docxBytes = NeomDocxService.generateFromMarkdown(
  content: '# Project Plan\n\n1. Research\n2. Design\n3. Build',
  title: 'Plan',
);

downloadFileBytes(docxBytes, 'plan.docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
```

### XLSX Generation

```dart
final markdown = '''
Here is the data:

\`\`\`csv
Name,Score,Grade
Alice,95,A
Bob,82,B
Charlie,71,C
\`\`\`
''';

final csv = NeomExcelService.extractCsvFromMarkdown(markdown);
if (csv != null) {
  final xlsxBytes = NeomExcelService.generateFromCsv(csvContent: csv);
  downloadFileBytes(xlsxBytes, 'scores.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
```

### DOCX Text Extraction

```dart
// Read text from an uploaded DOCX file
final text = NeomDocxService.extractText(docxFileBytes);
```

### Custom Theming

```dart
final theme = DocTheme(
  accentColor: PdfColor.fromHex('#FF6B35'),
  accentDark: PdfColor.fromHex('#CC5529'),
  brandName: 'My App',
  brandVersion: 'v2.0',
  footerLeft: 'My Company',
  footerCenter: 'Generated with My App',
);

final pdfBytes = await NeomPdfService.generateFromMarkdown(
  content: markdownText,
  theme: theme,
);
```

## Markdown Support

### PDF
Headers (H1-H3), **bold**, bullet lists, numbered lists, checkboxes, horizontal rules

### DOCX
Headers (H1-H3), **bold**, bullet lists, numbered lists

### XLSX
CSV with quoted fields, escaped quotes, numeric type detection

## Dependencies

| Package | Purpose |
|---------|---------|
| `pdf` | PDF generation engine |
| `excel` | XLSX creation |
| `docx_to_text` | DOCX text extraction |
| `sint_sentinel` | Logger |

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
