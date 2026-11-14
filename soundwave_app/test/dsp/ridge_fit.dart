// Ridge tracking for spectrogram tests (#91): the peak bin of each row and
// a least-squares line through the ridge.

import 'dart:math' as math;

/// Peak bin of [row] restricted to [lo, hi].
int ridgeBin(List<double> row, int lo, int hi) {
  var best = lo;
  for (var k = lo + 1; k <= hi; k++) {
    if (row[k] > row[best]) best = k;
  }
  return best;
}

class LineFit {
  final double slope, intercept, r2, maxResidual;
  const LineFit(this.slope, this.intercept, this.r2, this.maxResidual);
}

LineFit fitLine(List<double> x, List<double> y) {
  final n = x.length;
  final mx = x.reduce((a, b) => a + b) / n;
  final my = y.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  final slope = sxy / sxx;
  final intercept = my - slope * mx;
  var maxRes = 0.0;
  for (var i = 0; i < n; i++) {
    maxRes = math.max(maxRes, (y[i] - (slope * x[i] + intercept)).abs());
  }
  return LineFit(slope, intercept, sxy * sxy / (sxx * syy), maxRes);
}
