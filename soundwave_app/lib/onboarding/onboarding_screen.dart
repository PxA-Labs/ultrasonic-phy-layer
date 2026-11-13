// First-run onboarding tutorial: what ultrasonic TX/RX is, CSS vs OFDM,
// and why Soundwave needs the microphone. Shown once (see UiPreferences)
// and replayable from Settings.

import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// Asks the platform for microphone access; true when granted.
Future<bool> requestMicrophonePermission() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } finally {
    await recorder.dispose();
  }
}

const _micGranted = 'Microphone access granted.';
const _micDenied = 'Microphone access not granted. You can enable it later.';
const _growIn = Duration(milliseconds: 450);

class OnboardingPageData {
  final IconData icon;
  final String title;

  /// Sentences of the page body, joined with spaces when rendered.
  final List<String> body;
  final bool asksMicPermission;

  const OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
    this.asksMicPermission = false,
  });
}

const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    icon: Icons.graphic_eq,
    title: 'Welcome to Soundwave',
    body: [
      'Soundwave sends short text messages between nearby devices',
      'using near-ultrasonic sound (about 18 to 20 kHz),',
      'played through an ordinary speaker and heard by a microphone.',
      'No network, Bluetooth or pairing is involved.',
    ],
  ),
  OnboardingPageData(
    icon: Icons.swap_horiz,
    title: 'How it works',
    body: [
      'Transmit: your message is framed with a checksum and',
      'error-correction data, modulated onto a high-frequency carrier',
      'and played through the speaker.',
      'Receive: the microphone listens for a sync preamble, demodulates',
      'the frame and checks it before showing the message.',
      'Range depends on your hardware and room, so start with the',
      'devices close together. Most adults hear little of this band,',
      'but children and pets may.',
    ],
  ),
  OnboardingPageData(
    icon: Icons.tune,
    title: 'CSS or OFDM',
    body: [
      'CSS (Chirp Spread Spectrum) sweeps each symbol across the band.',
      'It is slower but copes well with noise and echoes.',
      'OFDM splits the band into many subcarriers sent in parallel.',
      'It is faster but needs a quieter channel.',
      'Pick a mode or load a preset in Settings.',
    ],
  ),
  OnboardingPageData(
    icon: Icons.mic,
    title: 'Microphone access',
    body: [
      'To receive messages Soundwave needs the microphone.',
      'Audio is processed on this device to detect and decode frames.',
      'Without it you can still transmit.',
    ],
    asksMicPermission: true,
  ),
  OnboardingPageData(
    icon: Icons.check_circle_outline,
    title: 'You are ready',
    body: [
      'Type a message on the Dashboard and tap Send on one device,',
      'and tap Start Listening on the other.',
      'You can replay this tutorial at any time from Settings.',
    ],
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// Called when the user finishes or skips the tutorial.
  final VoidCallback onFinished;

  /// Injected for tests; defaults to the platform permission prompt.
  final Future<bool> Function() requestMicPermission;

  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.requestMicPermission = requestMicrophonePermission,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool? _micGranted;
  bool _requesting = false;

  bool get _isLast => _page == onboardingPages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _transition(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return reduceMotion ? Duration.zero : const Duration(milliseconds: 300);
  }

  void _goTo(int page) {
    final duration = _transition(context);
    if (duration == Duration.zero) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(
        page,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _next() {
    if (_isLast) {
      widget.onFinished();
    } else {
      _goTo(_page + 1);
    }
  }

  Future<void> _askForMic() async {
    setState(() => _requesting = true);
    bool granted;
    try {
      granted = await widget.requestMicPermission();
    } catch (e) {
      debugPrint('Microphone permission request failed: $e');
      granted = false;
    }
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _micGranted = granted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = onboardingPages.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _OnboardingPage(
                  data: onboardingPages[i],
                  pageNumber: i + 1,
                  pageCount: total,
                  micGranted: _micGranted,
                  requesting: _requesting,
                  onRequestMic: _askForMic,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    key: const Key('onboarding_skip'),
                    onPressed: widget.onFinished,
                    child: const Text('Skip'),
                  ),
                  Expanded(
                    child: _PageDots(current: _page, count: total),
                  ),
                  if (_page > 0)
                    IconButton(
                      key: const Key('onboarding_back'),
                      tooltip: 'Previous page',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _goTo(_page - 1),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('onboarding_next'),
                    onPressed: _next,
                    child: Text(_isLast ? 'Get started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final OnboardingPageData data;
  final int pageNumber;
  final int pageCount;
  final bool? micGranted;
  final bool requesting;
  final VoidCallback onRequestMic;

  const _OnboardingPage({
    required this.data,
    required this.pageNumber,
    required this.pageCount,
    required this.micGranted,
    required this.requesting,
    required this.onRequestMic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : _growIn;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative illustration: grows in once when the page appears.
          ExcludeSemantics(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.6, end: 1.0),
                duration: duration,
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    data.icon,
                    size: 56,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Step $pageNumber of $pageCount',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(data.title, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: 16),
          Text(data.body.join(' '), style: theme.textTheme.bodyLarge),
          if (data.asksMicPermission) ...[
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              key: const Key('onboarding_allow_mic'),
              onPressed: requesting ? null : onRequestMic,
              icon: const Icon(Icons.mic),
              label: const Text('Allow microphone'),
            ),
            if (micGranted != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                container: true,
                child: Text(
                  micGranted == true ? _micGranted : _micDenied,
                  key: const Key('onboarding_mic_result'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int current;
  final int count;

  const _PageDots({required this.current, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: i == current ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == current ? scheme.primary : scheme.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
