// The bundled legal documents and how links inside them resolve (issue #97).
//
// assets/legal/*.md are byte-for-byte copies of docs/legal/*.md (enforced by
// test/legal/legal_assets_sync_test.dart), so the in-app text and the
// published docs site never drift apart.

/// Where the MkDocs site is published (mkdocs.yml `site_url`).
const legalSiteBase = 'https://pxa-labs.github.io/ultrasonic-phy-layer/';

enum LegalDocument {
  privacyPolicy(
    title: 'Privacy Policy',
    fileName: 'PRIVACY_POLICY.md',
  ),
  termsOfService(
    title: 'Terms of Service',
    fileName: 'TERMS_OF_SERVICE.md',
  );

  final String title;
  final String fileName;

  const LegalDocument({required this.title, required this.fileName});

  String get assetPath => 'assets/legal/$fileName';

  /// Public URL of this document on the docs site.
  String get siteUrl => Uri.parse(legalSiteBase)
      .resolve('legal/${_pageDir(fileName)}')
      .toString();

  static LegalDocument? byFileName(String name) {
    for (final d in values) {
      if (d.fileName == name) return d;
    }
    return null;
  }
}

/// Where tapping a link in a legal document leads.
sealed class LegalLinkTarget {
  const LegalLinkTarget();
}

/// Another bundled legal document, opened in the app.
class InAppLegalLink extends LegalLinkTarget {
  final LegalDocument document;
  const InAppLegalLink(this.document);

  @override
  bool operator ==(Object other) =>
      other is InAppLegalLink && other.document == document;

  @override
  int get hashCode => document.hashCode;

  @override
  String toString() => 'InAppLegalLink(${document.name})';
}

/// A web address. The app has no browser integration and no network access,
/// so the UI offers to copy it.
class ExternalLegalLink extends LegalLinkTarget {
  final String url;
  const ExternalLegalLink(this.url);

  @override
  bool operator ==(Object other) =>
      other is ExternalLegalLink && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ExternalLegalLink($url)';
}

/// Resolves [target] as written in [from]'s Markdown.
///
/// - Links to another bundled document open it in the app.
/// - Absolute http(s) URLs are returned as-is.
/// - Other relative links (e.g. `../testing/PLAN.md#section`) are resolved
///   the way MkDocs publishes them (`use_directory_urls`): `X.md` -> `X/`.
/// - Anything else (mailto:, javascript:, ...) yields null and is shown as
///   plain text.
LegalLinkTarget? resolveLegalLink(String target, LegalDocument from) {
  final t = target.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t);
  if (uri == null) return null;

  if (uri.hasScheme) {
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return ExternalLegalLink(uri.toString());
    }
    return null;
  }

  final path = uri.path;
  if (path.isNotEmpty) {
    final name = path.split('/').last;
    final doc = LegalDocument.byFileName(name);
    // Only same-folder links open in-app; another folder's file with the
    // same name is a different page.
    if (doc != null && !path.contains('/')) return InAppLegalLink(doc);
  }

  final fromPage = Uri.parse(legalSiteBase).resolve('legal/${from.fileName}');
  var resolved = fromPage.resolve(path.isEmpty ? from.fileName : path);
  if (resolved.path.endsWith('.md')) {
    // Trailing empty segment = trailing slash ("X.md" -> "X/").
    final segments = [...resolved.pathSegments];
    final stem = segments.removeLast().replaceFirst(RegExp(r'\.md$'), '');
    if (stem != 'index') segments.add(stem);
    segments.add('');
    resolved = resolved.replace(pathSegments: segments);
  }
  if (uri.hasFragment) resolved = resolved.replace(fragment: uri.fragment);
  return ExternalLegalLink(resolved.toString());
}

/// `NAME.md` -> `NAME/` (MkDocs directory URL); `index.md` -> ``.
String _pageDir(String fileName) {
  final stem = fileName.endsWith('.md')
      ? fileName.substring(0, fileName.length - 3)
      : fileName;
  return stem == 'index' ? '' : '$stem/';
}
