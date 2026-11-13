// Colour maps for the waterfall spectrogram (#91).
//
// These encode data (dB level), not UI chrome, so they are fixed palettes
// that read the same in light and dark themes.

import 'dart:typed_data';
import 'dart:ui' show Color;

enum WaterfallColormap {
  viridis('Viridis', [
    0xFF440154,
    0xFF472C7A,
    0xFF3B518B,
    0xFF2C718E,
    0xFF21908D,
    0xFF27AD81,
    0xFF5CC863,
    0xFFAADC32,
    0xFFFDE725,
  ]),
  thermal('Thermal', [
    0xFF000000,
    0xFF1428DC,
    0xFFFFDC00,
    0xFFFFFFFF,
  ]),
  grayscale('Grayscale', [
    0xFF000000,
    0xFFFFFFFF,
  ]);

  final String label;
  final List<int> _stops;

  const WaterfallColormap(this.label, this._stops);

  static final Map<WaterfallColormap, Uint8List> _rgbaCache = {};

  /// 256-entry lookup table, RGBA bytes per entry (rgba8888 pixel order).
  Uint8List get rgbaLut => _rgbaCache.putIfAbsent(this, _buildLut);

  Uint8List _buildLut() {
    final lut = Uint8List(256 * 4);
    final segments = _stops.length - 1;
    for (var i = 0; i < 256; i++) {
      final pos = i / 255 * segments;
      final s = pos.floor().clamp(0, segments - 1);
      final t = pos - s;
      final a = _stops[s];
      final b = _stops[s + 1];
      for (var c = 0; c < 3; c++) {
        final shift = 16 - 8 * c;
        final ca = (a >> shift) & 0xFF;
        final cb = (b >> shift) & 0xFF;
        lut[i * 4 + c] = (ca + (cb - ca) * t).round();
      }
      lut[i * 4 + 3] = 0xFF;
    }
    return lut;
  }

  /// LUT index for a normalised level [t] in [0, 1] (clamped; NaN -> 0).
  static int indexOf(double t) {
    if (!(t > 0)) return 0;
    if (t >= 1) return 255;
    return (t * 255).round();
  }

  /// Colour for a normalised level [t] in [0, 1].
  Color colorAt(double t) {
    final lut = rgbaLut;
    final o = indexOf(t) * 4;
    return Color.fromARGB(lut[o + 3], lut[o], lut[o + 1], lut[o + 2]);
  }
}
