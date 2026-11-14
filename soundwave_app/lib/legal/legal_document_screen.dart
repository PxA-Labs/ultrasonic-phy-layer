// Offline reader for the bundled privacy policy and terms (issue #97).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legal_documents.dart';
import 'legal_markdown.dart';

/// Opens [document] in a new route.
Future<void> openLegalDocument(BuildContext context, LegalDocument document) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LegalDocumentScreen(document: document),
    ),
  );
}

class LegalDocumentScreen extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  Future<List<LegalBlock>>? _blocks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _blocks ??= DefaultAssetBundle.of(context)
        .loadString(widget.document.assetPath)
        .then(parseLegalMarkdown);
  }

  Future<void> _onLink(String target) async {
    final resolved = resolveLegalLink(target, widget.document);
    switch (resolved) {
      case InAppLegalLink(:final document):
        await openLegalDocument(context, document);
      case ExternalLegalLink(:final url):
        await _copy(url);
      case null:
        break;
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Link copied: $url')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
        actions: [
          IconButton(
            key: const Key('legal_copy_url'),
            tooltip: 'Copy web address',
            icon: const Icon(Icons.link),
            onPressed: () => _copy(widget.document.siteUrl),
          ),
        ],
      ),
      body: FutureBuilder<List<LegalBlock>>(
        future: _blocks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(document: widget.document);
          }
          final blocks = snapshot.data;
          if (blocks == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: ListView(
              key: const Key('legal_document_body'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                for (final b in blocks) _BlockView(block: b, onLink: _onLink),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final LegalDocument document;
  const _LoadError({required this.document});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'The ${document.title} could not be loaded. '
          'It is also published at ${document.siteUrl}',
          key: const Key('legal_load_error'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

typedef _LinkHandler = void Function(String target);

class _BlockView extends StatelessWidget {
  final LegalBlock block;
  final _LinkHandler onLink;

  const _BlockView({required this.block, required this.onLink});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final b = block;
    switch (b) {
      case LegalHeading(:final level, :final content):
        final style = switch (level) {
          1 => text.headlineSmall,
          2 => text.titleLarge,
          _ => text.titleMedium,
        };
        return Padding(
          padding: EdgeInsets.only(top: level == 1 ? 0 : 20, bottom: 8),
          child: Semantics(
            header: true,
            child: _InlineText(runs: content, style: style, onLink: onLink),
          ),
        );
      case LegalParagraph(:final content):
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _InlineText(
              runs: content, style: text.bodyMedium, onLink: onLink),
        );
      case LegalBulletList(:final items):
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text('•  ', style: text.bodyMedium),
                      ),
                      Expanded(
                        child: _InlineText(
                            runs: item, style: text.bodyMedium, onLink: onLink),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case LegalTable():
        return _TableView(table: b, onLink: onLink);
      case LegalAdmonition(:final kind, :final title, :final body):
        final severe = kind == 'danger' || kind == 'warning';
        final scheme = theme.colorScheme;
        final bg =
            severe ? scheme.errorContainer : scheme.surfaceContainerHighest;
        final fg = severe ? scheme.onErrorContainer : scheme.onSurface;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            key: Key('legal_admonition_$kind'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        severe ? Icons.warning_amber : Icons.info_outline,
                        color: fg,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: text.titleSmall?.copyWith(color: fg),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        bodyColor: fg,
                        displayColor: fg,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final inner in body)
                          _BlockView(block: inner, onLink: onLink),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

/// Tables are shown as one card per row ("Header: value" lines) so they stay
/// readable on a phone and read naturally with a screen reader.
class _TableView extends StatelessWidget {
  final LegalTable table;
  final _LinkHandler onLink;

  const _TableView({required this.table, required this.onLink});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final headers = table.header.map(legalPlainText).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (final row in table.rows)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InlineText(
                    runs: row.first,
                    style: text.titleSmall,
                    onLink: onLink,
                  ),
                  for (var c = 1; c < row.length; c++)
                    if (row[c].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _InlineText(
                          runs: [
                            LegalInline('${headers[c]}: ', bold: true),
                            ...row[c],
                          ],
                          style: text.bodyMedium,
                          onLink: onLink,
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rich text for one run list. Owns the tap recognizers for its links and
/// disposes them with the widget.
class _InlineText extends StatefulWidget {
  final List<LegalInline> runs;
  final TextStyle? style;
  final _LinkHandler onLink;

  const _InlineText({
    required this.runs,
    required this.style,
    required this.onLink,
  });

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  final _recognizers = <int, TapGestureRecognizer>{};

  @override
  void didUpdateWidget(_InlineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runs, widget.runs)) _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.runs.length; i++) {
      final r = widget.runs[i];
      final link = r.link;
      TapGestureRecognizer? recognizer;
      if (link != null) {
        recognizer = _recognizers.putIfAbsent(i, TapGestureRecognizer.new)
          ..onTap = () => widget.onLink(link);
      }
      spans.add(TextSpan(
        text: r.text,
        recognizer: recognizer,
        style: TextStyle(
          fontWeight: r.bold ? FontWeight.w700 : null,
          fontStyle: r.italic ? FontStyle.italic : null,
          fontFamily: r.code ? 'monospace' : null,
          color: link != null ? scheme.primary : null,
          decoration: link != null ? TextDecoration.underline : null,
        ),
      ));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
