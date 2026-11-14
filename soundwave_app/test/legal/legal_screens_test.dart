// In-app privacy policy and terms (issue #97): the offline reader, links
// between and out of the documents, entry points in Settings and onboarding,
// and accessibility in both themes.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/legal/legal_document_screen.dart';
import 'package:soundwave/legal/legal_documents.dart';
import 'package:soundwave/onboarding/onboarding_screen.dart';
import 'package:soundwave/screens/settings.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/theme/soundwave_theme.dart';

import '../engine/mock_native.dart';

Widget reader(LegalDocument doc, {ThemeData? theme}) => withFiles(MaterialApp(
      theme: theme ?? SoundwaveTheme.light,
      home: LegalDocumentScreen(document: doc),
    ));

/// Captures text written to the system clipboard.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// Taps the first [TextSpan] link in a [RichText] whose text contains
/// [linkText].
Future<void> tapLink(WidgetTester tester, String linkText) async {
  final rich = find.byWidgetPredicate((w) {
    if (w is! RichText) return false;
    var hit = false;
    w.text.visitChildren((span) {
      if (span is TextSpan &&
          span.recognizer != null &&
          (span.text ?? '').contains(linkText)) {
        hit = true;
        return false;
      }
      return true;
    });
    return hit;
  });
  // The document is a lazy ListView: scroll until the paragraph is built.
  await tester.scrollUntilVisible(rich, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  expect(rich, findsOneWidget, reason: 'link "$linkText"');
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final full = paragraph.text.toPlainText();
  final offset = full.indexOf(linkText) + 1;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  final local = boxes.first.toRect().center;
  await tester.tapAt(paragraph.localToGlobal(local));
  await tester.pumpAndSettle();
}

/// Serves assets from the package directory synchronously. The real
/// rootBundle reads files with async I/O that does not complete inside
/// testWidgets' fake-async zone; the "bundled in the app" test below checks
/// the real bundle with runAsync.
class FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      SynchronousFuture(ByteData.sublistView(File(key).readAsBytesSync()));

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(File(key).readAsStringSync());
}

Widget withFiles(Widget app) =>
    DefaultAssetBundle(bundle: FileAssetBundle(), child: app);

void main() {
  testWidgets('both documents are bundled in the app (real rootBundle)',
      (tester) async {
    for (final doc in LegalDocument.values) {
      final text =
          await tester.runAsync(() => rootBundle.loadString(doc.assetPath));
      expect(text, File(doc.assetPath).readAsStringSync());
    }
  });

  group('LegalDocumentScreen', () {
    testWidgets('renders the bundled privacy policy offline', (tester) async {
      await tester.pumpWidget(reader(LegalDocument.privacyPolicy));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget); // app bar
      expect(find.byKey(const Key('legal_admonition_danger')), findsOneWidget);
      expect(find.textContaining('DRAFT'), findsWidgets);
      expect(find.text('Summary'), findsOneWidget);
      // Table rows become cards with "Header: value" lines.
      await tester.scrollUntilVisible(
        find.text('Microphone audio'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Where it goes: '), findsWidgets);
      expect(find.byKey(const Key('legal_load_error')), findsNothing);
    });

    testWidgets('headings are exposed as headers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(reader(LegalDocument.termsOfService));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.text('1. Acceptance'));
      expect(node.getSemanticsData().flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('link to the privacy policy opens it in the app',
        (tester) async {
      await tester.pumpWidget(reader(LegalDocument.termsOfService));
      await tester.pumpAndSettle();
      await tapLink(tester, 'Privacy Policy');
      expect(
        find.byWidgetPredicate((w) =>
            w is LegalDocumentScreen &&
            w.document == LegalDocument.privacyPolicy),
        findsOneWidget,
      );
      expect(find.text('Summary'), findsOneWidget);
    });

    testWidgets('web links are copied, since the app has no network access',
        (tester) async {
      final copied = captureClipboard(tester);
      await tester.pumpWidget(reader(LegalDocument.termsOfService));
      await tester.pumpAndSettle();
      await tapLink(tester, 'https://github.com/PxA-Labs/ultrasonic-phy-layer');
      expect(copied, ['https://github.com/PxA-Labs/ultrasonic-phy-layer']);
      expect(find.textContaining('Link copied'), findsOneWidget);

      await tapLink(tester, 'hardware profiling plan');
      expect(copied.last,
          'https://pxa-labs.github.io/ultrasonic-phy-layer/testing/HARDWARE_PROFILING_PLAN/');
    });

    testWidgets('app bar action copies the published address', (tester) async {
      final copied = captureClipboard(tester);
      await tester.pumpWidget(reader(LegalDocument.privacyPolicy));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('legal_copy_url')));
      await tester.pumpAndSettle();
      expect(copied, [LegalDocument.privacyPolicy.siteUrl]);
    });

    testWidgets('a missing asset shows the published address instead',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DefaultAssetBundle(
          bundle: _EmptyBundle(),
          child:
              const LegalDocumentScreen(document: LegalDocument.termsOfService),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legal_load_error')), findsOneWidget);
      expect(find.textContaining(LegalDocument.termsOfService.siteUrl),
          findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final doc in LegalDocument.values) {
        testWidgets(
            '${doc.title} meets a11y guidelines (${dark ? 'dark' : 'light'})',
            (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(reader(doc,
              theme: dark ? SoundwaveTheme.dark : SoundwaveTheme.light));
          await tester.pumpAndSettle();
          final scrollable = find.byType(Scrollable).first;
          // Check the top (draft notice) and further down (tables, lists).
          for (var i = 0; i < 4; i++) {
            await expectLater(
                tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(
                tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await tester.drag(scrollable, const Offset(0, -500));
            await tester.pumpAndSettle();
          }
          handle.dispose();
        });
      }
    }

    testWidgets('lays out at 200% text scale without overflow', (tester) async {
      for (final doc in LegalDocument.values) {
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: reader(doc),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('entry points', () {
    Widget settingsApp() => ChangeNotifierProvider(
          create: (_) => AppState(audio: MockAudioService()),
          child: withFiles(const MaterialApp(home: SettingsScreen())),
        );

    Future<void> openFromSettings(WidgetTester tester, Key key) async {
      await tester.pumpWidget(settingsApp());
      final tile = find.byKey(key);
      await tester.scrollUntilVisible(tile, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    testWidgets('Settings opens the privacy policy', (tester) async {
      await openFromSettings(tester, const Key('legal_privacy_policy'));
      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
    });

    testWidgets('Settings opens the terms of service', (tester) async {
      await openFromSettings(tester, const Key('legal_terms_of_service'));
      expect(find.text('1. Acceptance'), findsOneWidget);
    });

    testWidgets('Settings opens the open-source licences', (tester) async {
      await openFromSettings(tester, const Key('legal_licenses'));
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets(
        'onboarding links the terms and privacy policy on its last page',
        (tester) async {
      var finished = 0;
      await tester.pumpWidget(withFiles(MaterialApp(
        theme: SoundwaveTheme.light,
        home: OnboardingScreen(
          onFinished: () => finished++,
          requestMicPermission: () async => true,
          showMicPermissionButton: false,
        ),
      )));
      await tester.pumpAndSettle();
      // Only the final page carries the notice.
      expect(find.byKey(const Key('onboarding_legal_notice')), findsNothing);
      for (var i = 1; i < onboardingPages.length; i++) {
        await tester.tap(find.byKey(const Key('onboarding_next')));
        await tester.pumpAndSettle();
      }
      expect(onboardingPages.where((p) => p.showsLegalLinks), hasLength(1));
      expect(find.byKey(const Key('onboarding_legal_notice')), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_terms')));
      await tester.pumpAndSettle();
      expect(find.text('1. Acceptance'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_privacy')));
      await tester.pumpAndSettle();
      expect(find.text('Summary'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Reading the documents does not finish onboarding by itself.
      expect(finished, 0);
      await tester.tap(find.byKey(const Key('onboarding_next')));
      expect(finished, 1);
    });
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: "$key".');
}
