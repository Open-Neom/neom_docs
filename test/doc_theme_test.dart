// neom_docs is mostly a thin wrapper around the `pdf`, `excel` and `docx`
// packages for generating documents. All meaningful behavior is I/O
// (loading fonts, writing PDFs, writing files) that lives behind
// Flutter's rootBundle and dart:io — untestable in pure unit tests
// without mocking the asset bundle, which the task instructions
// discourage.
//
// The only pure-logic surface is [DocTheme], which is a trivial value
// object with const defaults. We exercise it here to prevent regressions
// in the branding defaults and to ensure the widely-referenced
// `standard` instance stays const-constructible.

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_docs/domain/models/doc_theme.dart';
import 'package:pdf/pdf.dart';

void main() {
  group('DocTheme defaults', () {
    test('standard theme branding defaults', () {
      const t = DocTheme.standard;
      expect(t.brandName, 'Open Neom');
      expect(t.brandVersion, 'v1.0');
      expect(t.footerLeft, 'Open Neom');
      expect(t.footerCenter, contains('Open Neom'));
      expect(t.footerCenter, contains('neom_docs'));
    });

    test('standard accent colors match expected hex', () {
      const t = DocTheme.standard;
      // accentColor is 0xFF00E5CC
      expect(t.accentColor, const PdfColor.fromInt(0xFF00E5CC));
      // accentDark is 0xFF009E8E
      expect(t.accentDark, const PdfColor.fromInt(0xFF009E8E));
    });

    test('custom theme overrides individual fields', () {
      const t = DocTheme(
        brandName: 'Acme',
        brandVersion: 'v9',
        footerLeft: 'Acme Corp',
        footerCenter: 'All rights reserved',
      );
      expect(t.brandName, 'Acme');
      expect(t.brandVersion, 'v9');
      expect(t.footerLeft, 'Acme Corp');
      expect(t.footerCenter, 'All rights reserved');
      // Accent colors default preserved
      expect(t.accentColor, const PdfColor.fromInt(0xFF00E5CC));
    });

    test('DocTheme is const-constructible (compile-time constant)', () {
      // Two const constructions of the same thing should share identity.
      const a = DocTheme();
      const b = DocTheme();
      expect(identical(a, b), isTrue);
    });
  });
}
