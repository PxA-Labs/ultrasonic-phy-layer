// Semantics wrapper for the spectrum and waterfall plots (#93): a fixed
// label saying what the plot is, and the current band summary as its value,
// so focusing a plot with a screen reader tells you whether a signal is
// present. The Monitor's readout row carries the live region that announces
// changes; the plots do not, so a change is announced once, not per plot.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../dsp/band_activity.dart';

class BandActivitySemantics extends StatelessWidget {
  final ValueListenable<BandActivity>? activity;
  final String label;
  final Widget child;

  const BandActivitySemantics({
    super.key,
    required this.activity,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final source = activity;
    if (source == null) {
      return Semantics(container: true, label: label, child: child);
    }
    // Rebuilds only the semantics node on a transition; the plot itself
    // (child) is passed through untouched.
    return ValueListenableBuilder<BandActivity>(
      valueListenable: source,
      child: child,
      builder: (context, a, plot) => Semantics(
        container: true,
        label: label,
        value: a.describe(),
        child: plot,
      ),
    );
  }
}
