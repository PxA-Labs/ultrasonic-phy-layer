// Link resolution and asset/doc-site consistency for the legal documents
// (issue #97).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/legal/legal_documents.dart';

void main() {
  const terms = LegalDocument.termsOfService;
  const privacy = LegalDocument.privacyPolicy;

  group('resolveLegalLink', () {
    test('sibling legal documents open in the app', () {
      expect(resolveLegalLink('PRIVACY_POLICY.md', terms),
          const InAppLegalLink(privacy));
      expect(resolveLegalLink('TERMS_OF_SERVICE.md', privacy),
          const InAppLegalLink(terms));
    });

    test('a same-named file in another folder is not the bundled one', () {
      expect(
        resolveLegalLink('../other/PRIVACY_POLICY.md', terms),
        const ExternalLegalLink(
            'https://pxa-labs.github.io/ultrasonic-phy-layer/other/PRIVACY_POLICY/'),
      );
    });

    test('relative doc links map to MkDocs directory URLs', () {
      expect(
        resolveLegalLink('../testing/HARDWARE_PROFILING_PLAN.md', terms),
        const ExternalLegalLink(
            'https://pxa-labs.github.io/ultrasonic-phy-layer/testing/HARDWARE_PROFILING_PLAN/'),
      );
      expect(
        resolveLegalLink('../testing/PLAN.md#latency', terms),
        const ExternalLegalLink(
            'https://pxa-labs.github.io/ultrasonic-phy-layer/testing/PLAN/#latency'),
      );
      expect(
        resolveLegalLink('../index.md', terms),
        const ExternalLegalLink(
            'https://pxa-labs.github.io/ultrasonic-phy-layer/'),
      );
    });

    test('a bare fragment points into the same page', () {
      expect(
        resolveLegalLink('#4-sharing', privacy),
        const ExternalLegalLink(
            'https://pxa-labs.github.io/ultrasonic-phy-layer/legal/PRIVACY_POLICY/#4-sharing'),
      );
    });

    test('web URLs pass through; other schemes are ignored', () {
      expect(resolveLegalLink('https://github.com/PxA-Labs/x', terms),
          const ExternalLegalLink('https://github.com/PxA-Labs/x'));
      expect(resolveLegalLink('javascript:alert(1)', terms), isNull);
      expect(resolveLegalLink('mailto:a@b.c', terms), isNull);
      expect(resolveLegalLink('   ', terms), isNull);
    });
  });

  test('siteUrl matches the MkDocs page of each document', () {
    expect(privacy.siteUrl,
        'https://pxa-labs.github.io/ultrasonic-phy-layer/legal/PRIVACY_POLICY/');
    expect(terms.siteUrl,
        'https://pxa-labs.github.io/ultrasonic-phy-layer/legal/TERMS_OF_SERVICE/');
  });

  test('legalSiteBase is mkdocs.yml site_url', () {
    final mkdocs = File('../mkdocs.yml').readAsStringSync();
    final siteUrl =
        RegExp(r'^site_url:\s*(\S+)', multiLine: true).firstMatch(mkdocs);
    expect(siteUrl?.group(1), legalSiteBase);
  });

  // The bundled copies are what users read in the app; docs/legal is what
  // the docs site and the store listing link to. They must be identical.
  for (final doc in LegalDocument.values) {
    test('assets/legal/${doc.fileName} is identical to docs/legal', () {
      final bundled = File(doc.assetPath);
      final source = File('../docs/legal/${doc.fileName}');
      expect(bundled.existsSync(), isTrue);
      expect(source.existsSync(), isTrue);
      expect(
        bundled.readAsStringSync(),
        source.readAsStringSync(),
        reason: 'Run: cp ../docs/legal/${doc.fileName} assets/legal/',
      );
    });
  }

  test('pubspec bundles assets/legal/', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/legal/'));
  });
}
