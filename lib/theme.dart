import 'package:flutter/material.dart';

/// Default accent before any title has been picked.
const Color kDefaultAccent = Color(0xFF6C5CE7);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kDefaultAccent,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E0B1A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
  );
}

/// Background built from a title's main color: a deep, saturated top
/// fading into near-black at the bottom, so white text always stays readable.
class BackdropPalette {
  final Color top;
  final Color middle;
  final Color bottom;
  final Color accent;

  const BackdropPalette({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.accent,
  });

  factory BackdropPalette.from(Color base) {
    final hsl = HSLColor.fromColor(base);
    final sat = hsl.saturation.clamp(0.35, 0.85);
    Color tone(double lightness, [double satScale = 1]) => hsl
        .withSaturation((sat * satScale).clamp(0.0, 1.0))
        .withLightness(lightness)
        .toColor();

    return BackdropPalette(
      top: tone(0.34),
      middle: tone(0.17, 0.9),
      bottom: tone(0.06, 0.7),
      accent: tone(0.62),
    );
  }

  static final BackdropPalette initial = BackdropPalette.from(kDefaultAccent);
}
