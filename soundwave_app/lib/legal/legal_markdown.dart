// Minimal Markdown parser for the bundled legal documents (issue #97).
//
// The privacy policy and terms are maintained once, in docs/legal/, for the
// MkDocs site, and bundled verbatim as app assets so they can be read
// offline (the app makes no network connections). This parser covers
// exactly the subset those documents use:
//
//   # / ## / ### headings, paragraphs (soft-wrapped lines join with a space),
//   "- " bullet lists, pipe tables, MkDocs admonitions
//   (`!!! kind "Title"` followed by 4-space indented lines), and the inline
//   forms **bold**, *italic*, `code`, [text](target) and <https://autolink>.
//
// Anything else is kept as plain paragraph text, so an unsupported construct
// degrades to readable text rather than disappearing.

/// One styled run of inline text.
class LegalInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  /// Link target as written in the Markdown (relative path or URL), or null.
  final String? link;

  const LegalInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });

  @override
  bool operator ==(Object other) =>
      other is LegalInline &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, italic, code, link);

  @override
  String toString() {
    final flags = [
      if (bold) 'b',
      if (italic) 'i',
      if (code) 'c',
      if (link != null) 'link=$link',
    ].join(',');
    return 'LegalInline("$text"${flags.isEmpty ? '' : ' $flags'})';
  }
}

sealed class LegalBlock {
  const LegalBlock();
}

class LegalHeading extends LegalBlock {
  final int level;
  final List<LegalInline> content;
  const LegalHeading(this.level, this.content);
}

class LegalParagraph extends LegalBlock {
  final List<LegalInline> content;
  const LegalParagraph(this.content);
}

class LegalBulletList extends LegalBlock {
  final List<List<LegalInline>> items;
  const LegalBulletList(this.items);
}

class LegalTable extends LegalBlock {
  final List<List<LegalInline>> header;
  final List<List<List<LegalInline>>> rows;
  const LegalTable(this.header, this.rows);
}

class LegalAdmonition extends LegalBlock {
  /// MkDocs admonition type, e.g. `danger`, `warning`, `note`.
  final String kind;
  final String title;
  final List<LegalBlock> body;
  const LegalAdmonition(this.kind, this.title, this.body);
}

/// Plain text of a run list, e.g. for semantics labels and headings.
String legalPlainText(List<LegalInline> runs) => runs.map((r) => r.text).join();

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
final _admonition = RegExp(r'^!!!\s+(\w+)(?:\s+"([^"]*)")?\s*$');
final _tableSeparator =
    RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$');

List<LegalBlock> parseLegalMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  return _parseBlocks(lines);
}

List<LegalBlock> _parseBlocks(List<String> lines) {
  final blocks = <LegalBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(LegalParagraph(parseLegalInline(paragraph.join(' '))));
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    final admonition = _admonition.firstMatch(trimmed);
    if (admonition != null && !line.startsWith(' ')) {
      flushParagraph();
      final kind = admonition.group(1)!;
      final title = admonition.group(2) ?? _capitalize(kind);
      final body = <String>[];
      i++;
      // Body: indented lines, with blank lines allowed inside.
      while (i < lines.length &&
          (lines[i].startsWith('    ') || lines[i].trim().isEmpty)) {
        if (lines[i].trim().isEmpty && !_continuesIndented(lines, i)) break;
        body.add(lines[i].length >= 4 ? lines[i].substring(4) : '');
        i++;
      }
      blocks.add(LegalAdmonition(kind, title, _parseBlocks(body)));
      continue;
    }

    final heading = _heading.firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      blocks.add(LegalHeading(
        heading.group(1)!.length,
        parseLegalInline(heading.group(2)!.trim()),
      ));
      i++;
      continue;
    }

    if (trimmed.startsWith('|') &&
        i + 1 < lines.length &&
        _tableSeparator.hasMatch(lines[i + 1].trim())) {
      flushParagraph();
      final header = _tableCells(trimmed);
      final rows = <List<List<LegalInline>>>[];
      i += 2;
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = _tableCells(lines[i].trim());
        // Pad or trim to the header width so every row is rectangular.
        while (cells.length < header.length) {
          cells.add(const []);
        }
        rows.add(cells.take(header.length).toList());
        i++;
      }
      blocks.add(LegalTable(header, rows));
      continue;
    }

    if (_bullet.hasMatch(line)) {
      flushParagraph();
      final items = <String>[];
      while (i < lines.length) {
        final m = _bullet.firstMatch(lines[i]);
        if (m != null) {
          items.add(m.group(1)!.trim());
        } else if (lines[i].startsWith('  ') &&
            lines[i].trim().isNotEmpty &&
            items.isNotEmpty) {
          // Continuation line of the previous item.
          items[items.length - 1] = '${items.last} ${lines[i].trim()}';
        } else {
          break;
        }
        i++;
      }
      blocks.add(LegalBulletList(items.map(parseLegalInline).toList()));
      continue;
    }

    paragraph.add(trimmed);
    i++;
  }
  flushParagraph();
  return blocks;
}

bool _continuesIndented(List<String> lines, int i) {
  for (var j = i + 1; j < lines.length; j++) {
    if (lines[j].trim().isEmpty) continue;
    return lines[j].startsWith('    ');
  }
  return false;
}

List<List<LegalInline>> _tableCells(String row) {
  var body = row;
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|') && !body.endsWith(r'\|')) {
    body = body.substring(0, body.length - 1);
  }
  final cells = <String>[];
  final cell = StringBuffer();
  for (var k = 0; k < body.length; k++) {
    final ch = body[k];
    if (ch == r'\' && k + 1 < body.length && body[k + 1] == '|') {
      cell.write('|');
      k++;
    } else if (ch == '|') {
      cells.add(cell.toString());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  cells.add(cell.toString());
  return cells.map((c) => parseLegalInline(c.trim())).toList();
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Parses inline Markdown into styled runs. Unmatched markers are kept as
/// literal text.
List<LegalInline> parseLegalInline(String text) {
  final out = <LegalInline>[];
  _parseInlineInto(text, out, bold: false, italic: false, link: null);
  return _merge(out);
}

void _parseInlineInto(
  String text,
  List<LegalInline> out, {
  required bool bold,
  required bool italic,
  required String? link,
}) {
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    out.add(
        LegalInline(plain.toString(), bold: bold, italic: italic, link: link));
    plain.clear();
  }

  var i = 0;
  while (i < text.length) {
    final ch = text[i];

    if (ch == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out.add(LegalInline(text.substring(i + 1, end),
            bold: bold, italic: italic, code: true, link: link));
        i = end + 1;
        continue;
      }
    }

    if (ch == '*' && text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        _parseInlineInto(text.substring(i + 2, end), out,
            bold: true, italic: italic, link: link);
        i = end + 2;
        continue;
      }
    }

    if (ch == '*') {
      final end = _closingItalic(text, i + 1);
      if (end > i + 1) {
        flush();
        _parseInlineInto(text.substring(i + 1, end), out,
            bold: bold, italic: true, link: link);
        i = end + 1;
        continue;
      }
    }

    if (ch == '[' && link == null) {
      final close = text.indexOf('](', i + 1);
      final end = close < 0 ? -1 : text.indexOf(')', close + 2);
      if (close > i && end > close) {
        flush();
        _parseInlineInto(text.substring(i + 1, close), out,
            bold: bold, italic: italic, link: text.substring(close + 2, end));
        i = end + 1;
        continue;
      }
    }

    if (ch == '<' && link == null) {
      final end = text.indexOf('>', i + 1);
      if (end > i) {
        final url = text.substring(i + 1, end);
        if (url.startsWith('https://') || url.startsWith('http://')) {
          flush();
          out.add(LegalInline(url, bold: bold, italic: italic, link: url));
          i = end + 1;
          continue;
        }
      }
    }

    plain.write(ch);
    i++;
  }
  flush();
}

/// Index of the `*` closing an italic span that opened before [from], or -1.
/// A `**` pair inside the span is skipped as nested bold.
int _closingItalic(String text, int from) {
  var k = from;
  while (k < text.length) {
    if (text.startsWith('**', k)) {
      final end = text.indexOf('**', k + 2);
      if (end < 0) return -1;
      k = end + 2;
      continue;
    }
    if (text[k] == '*') return k;
    k++;
  }
  return -1;
}

List<LegalInline> _merge(List<LegalInline> runs) {
  final out = <LegalInline>[];
  for (final r in runs) {
    if (r.text.isEmpty) continue;
    if (out.isNotEmpty) {
      final last = out.last;
      if (last.bold == r.bold &&
          last.italic == r.italic &&
          last.code == r.code &&
          last.link == r.link) {
        out[out.length - 1] = LegalInline(last.text + r.text,
            bold: r.bold, italic: r.italic, code: r.code, link: r.link);
        continue;
      }
    }
    out.add(r);
  }
  return out;
}
