# Changelog

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
