// Parser tests for the bundled legal documents (issue #97).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/legal/legal_documents.dart';
import 'package:soundwave/legal/legal_markdown.dart';

const _i = LegalInline.new;

void main() {
  group('parseLegalInline', () {
    test('plain text is one run', () {
      expect(parseLegalInline('hello world'), [_i('hello world')]);
    });

    test('bold, italic and code', () {
      expect(parseLegalInline('a **b** *c* `d` e'), [
        _i('a '),
        _i('b', bold: true),
        _i(' '),
        _i('c', italic: true),
        _i(' '),
        _i('d', code: true),
        _i(' e'),
      ]);
    });

    test('bold nested in italic and italic nested in bold', () {
      expect(parseLegalInline('*x **y** z*'), [
        _i('x ', italic: true),
        _i('y', italic: true, bold: true),
        _i(' z', italic: true),
      ]);
      expect(parseLegalInline('**a *b* c**'), [
        _i('a ', bold: true),
        _i('b', bold: true, italic: true),
        _i(' c', bold: true),
      ]);
    });

    test('links keep their target and styled text', () {
      expect(
          parseLegalInline('See the [**Privacy** Policy](PRIVACY_POLICY.md).'),
          [
            _i('See the '),
            _i('Privacy', bold: true, link: 'PRIVACY_POLICY.md'),
            _i(' Policy', link: 'PRIVACY_POLICY.md'),
            _i('.'),
          ]);
    });

    test('autolinks', () {
      expect(parseLegalInline('at <https://example.org/x>.'), [
        _i('at '),
        _i('https://example.org/x', link: 'https://example.org/x'),
        _i('.'),
      ]);
    });

    test('code spans are literal', () {
      expect(parseLegalInline('`**not bold**`'), [
        _i('**not bold**', code: true),
      ]);
    });

    test('unmatched markers stay as literal text', () {
      expect(parseLegalInline('2 * 3 and a [bracket'),
          [_i('2 * 3 and a [bracket')]);
      expect(parseLegalInline('<not a url>'), [_i('<not a url>')]);
      expect(parseLegalInline('**open'), [_i('**open')]);
    });
  });

  group('parseLegalMarkdown', () {
    test('headings and soft-wrapped paragraphs', () {
      final blocks =
          parseLegalMarkdown('# Title\n\nline one\nline two\n\n## Sub');
      expect(blocks, hasLength(3));
      expect((blocks[0] as LegalHeading).level, 1);
      expect(legalPlainText((blocks[0] as LegalHeading).content), 'Title');
      expect(legalPlainText((blocks[1] as LegalParagraph).content),
          'line one line two');
      expect((blocks[2] as LegalHeading).level, 2);
    });

    test('bullet lists with continuation lines', () {
      final blocks =
          parseLegalMarkdown('- one\n- two\n  continued\n- three\n\nafter');
      final list = blocks[0] as LegalBulletList;
      expect(list.items.map(legalPlainText), ['one', 'two continued', 'three']);
      expect(blocks[1], isA<LegalParagraph>());
    });

    test('pipe tables, escaped pipes and ragged rows', () {
      final blocks = parseLegalMarkdown(
        '| A | B | C |\n|---|:---:|---|\n| 1 | x \\| y | 3 |\n| only |\n',
      );
      final table = blocks.single as LegalTable;
      expect(table.header.map(legalPlainText), ['A', 'B', 'C']);
      expect(table.rows, hasLength(2));
      expect(table.rows[0].map(legalPlainText), ['1', 'x | y', '3']);
      expect(table.rows[1].map(legalPlainText), ['only', '', '']);
    });

    test('a pipe line without a separator row is a paragraph', () {
      final blocks = parseLegalMarkdown('| not a table |');
      expect(blocks.single, isA<LegalParagraph>());
    });

    test('MkDocs admonitions with an indented body', () {
      final blocks = parseLegalMarkdown(
        '!!! danger "Draft"\n    First line\n    continues.\n\n    Second para.\n\nOutside.',
      );
      final adm = blocks[0] as LegalAdmonition;
      expect(adm.kind, 'danger');
      expect(adm.title, 'Draft');
      expect(adm.body, hasLength(2));
      expect(legalPlainText((adm.body[0] as LegalParagraph).content),
          'First line continues.');
      expect(legalPlainText((blocks[1] as LegalParagraph).content), 'Outside.');
    });

    test('an admonition without a title uses its kind', () {
      final adm =
          parseLegalMarkdown('!!! note\n    Body').single as LegalAdmonition;
      expect(adm.title, 'Note');
    });

    test('CRLF input parses like LF', () {
      expect(parseLegalMarkdown('# A\r\n\r\nb\r\n').length, 2);
    });
  });

  // The real documents, as bundled: every block parses and no Markdown
  // syntax leaks into the rendered text.
  for (final doc in LegalDocument.values) {
    group('bundled ${doc.fileName}', () {
      late List<LegalBlock> blocks;
      setUpAll(() {
        blocks = parseLegalMarkdown(File(doc.assetPath).readAsStringSync());
      });

      test('starts with its title and the draft notice', () {
        final h1 = blocks.first as LegalHeading;
        expect(h1.level, 1);
        expect(legalPlainText(h1.content), contains(doc.title));
        final adm = blocks[1] as LegalAdmonition;
        expect(adm.kind, 'danger');
        expect(adm.title, startsWith('DRAFT'));
      });

      test('has numbered sections', () {
        final sections = blocks
            .whereType<LegalHeading>()
            .where((h) => h.level == 2)
            .map((h) => legalPlainText(h.content))
            .where((t) => RegExp(r'^\d+\. ').hasMatch(t));
        expect(sections.length, greaterThanOrEqualTo(9));
      });

      test('no Markdown markers leak into non-code text', () {
        final residue = RegExp(r'\*\*|(^|\s)\*\S|\]\(|^#|^\|');
        for (final runs in _allRuns(blocks)) {
          for (final r in runs.where((r) => !r.code)) {
            expect(residue.hasMatch(r.text), isFalse,
                reason: 'raw Markdown in "${r.text}"');
          }
        }
      });

      test('every link resolves', () {
        final links = _allRuns(blocks)
            .expand((runs) => runs)
            .map((r) => r.link)
            .whereType<String>();
        for (final l in links) {
          expect(resolveLegalLink(l, doc), isNotNull, reason: l);
        }
      });
    });
  }
}

Iterable<List<LegalInline>> _allRuns(List<LegalBlock> blocks) sync* {
  for (final b in blocks) {
    switch (b) {
      case LegalHeading(:final content):
        yield content;
      case LegalParagraph(:final content):
        yield content;
      case LegalBulletList(:final items):
        yield* items;
      case LegalTable(:final header, :final rows):
        yield* header;
        for (final row in rows) {
          yield* row;
        }
      case LegalAdmonition(:final body):
        yield* _allRuns(body);
    }
  }
}
