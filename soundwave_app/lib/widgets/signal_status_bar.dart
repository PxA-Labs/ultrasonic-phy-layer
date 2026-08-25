// Signal status bar widget — real-time connection state, SNR bar, throughput readout, and frame statistics.
// Follows OpenSSF secure coding guidelines with robust bounds checks and null-safe rendering.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../engine/signal_metrics.dart';
import '../state/app_state.dart';

/// Interactive and animated signal status bar mounted at the top of the dashboard.
class SignalStatusBar extends StatefulWidget {
  final bool compact;

  const SignalStatusBar({
    super.key,
    this.compact = false,
  });

  @override
  State<SignalStatusBar> createState() => _SignalStatusBarState();
}

class _SignalStatusBarState extends State<SignalStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStatusColor(ModemLinkState state, BuildContext context) {
    switch (state) {
      case ModemLinkState.receiving:
        return const Color(0xFF00E676); // Vibrant Green
      case ModemLinkState.transmitting:
        return const Color(0xFF2979FF); // Vibrant Blue
      case ModemLinkState.listening:
        return const Color(0xFF00E5FF); // Cyan
      case ModemLinkState.error:
        return const Color(0xFFFF5252); // Coral Red
      case ModemLinkState.idle:
        return Colors.grey.shade500;
    }
  }

  Color _getSnrColor(double snr) {
    if (snr <= 0.0) return Colors.grey.shade600;
    if (snr < 6.0) return const Color(0xFFFF5252); // Low SNR - Red
    if (snr < 12.0)
      return const Color(0xFFFFD600); // Moderate SNR - Amber/Yellow
    return const Color(0xFF00E676); // Good SNR - Green
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final metrics = state.metrics;
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(metrics.connectionState, context);
    final snrColor = _getSnrColor(metrics.snr);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Status Dot, State Text, Throughput, and Error Badge
            Row(
              children: [
                // Pulsing Status Dot
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final shouldPulse =
                        metrics.connectionState != ModemLinkState.idle;
                    final scale = shouldPulse ? _pulseAnimation.value : 1.0;
                    final opacity = shouldPulse ? _pulseAnimation.value : 0.7;

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor.withValues(alpha: opacity),
                          boxShadow: shouldPulse
                              ? [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),

                // Connection State Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metrics.statusLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        metrics.connectionState == ModemLinkState.transmitting
                            ? 'Sending ultrasonic packets'
                            : metrics.connectionState ==
                                    ModemLinkState.receiving
                                ? 'Decoding frame…'
                                : metrics.connectionState ==
                                        ModemLinkState.listening
                                    ? '18–20 kHz band active'
                                    : 'Ready',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Throughput Readout
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        metrics.formattedThroughput,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Frame Error / Success Badge
                if (metrics.frameErrors > 0)
                  Tooltip(
                    message:
                        'Frame errors detected (${metrics.frameErrors} / ${metrics.framesDetected})',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 14,
                            color: Color(0xFFFF5252),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Err: ${metrics.frameErrors}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF5252),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (metrics.framesReceived > 0)
                  Tooltip(
                    message: 'Frames decoded: ${metrics.framesReceived}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: Color(0xFF00E676),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Rx: ${metrics.framesReceived}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            if (!widget.compact) ...[
              const SizedBox(height: 10),

              // Live SNR Gradient Bar & Readout
              Row(
                children: [
                  Text(
                    'SNR',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(
                          begin: 0.0,
                          // Scale SNR [0.0 - 30.0 dB] to normalized [0.0 - 1.0]
                          end: (metrics.snr / 30.0).clamp(0.0, 1.0),
                        ),
                        builder: (context, value, _) {
                          return Stack(
                            children: [
                              // Background Track
                              Container(
                                height: 8,
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                              ),
                              // Colored Progress Fill
                              FractionallySizedBox(
                                widthFactor: value,
                                child: Container(
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFF5252),
                                        Color(0xFFFFD600),
                                        Color(0xFF00E676),
                                      ],
                                      stops: [0.0, 0.4, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 54,
                    child: Text(
                      metrics.formattedSnr,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: snrColor,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
