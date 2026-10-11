import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from design/DESIGN.md + exported Stitch screens
/// ("Bench Instrument System"). Values follow the screen HTML.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.inset,
    required this.raised,
    required this.hairline,
    required this.text,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.running,
    required this.paused,
    required this.motion,
    required this.fault,
  });

  final Color bg;
  final Color surface; // surface-container-low
  final Color inset; // surface-container-lowest (recessed wells)
  final Color raised; // surface-container-high (headers, chips)
  final Color hairline;
  final Color text;
  final Color textSecondary; // on-surface-variant
  final Color textFaint; // outline
  final Color accent;
  final Color onAccent;
  final Color running;
  final Color paused;
  final Color motion;
  final Color fault;

  static const dark = Palette(
    bg: Color(0xFF16121B),
    surface: Color(0xFF1E1A23),
    inset: Color(0xFF100C15),
    raised: Color(0xFF38333D),
    hairline: Color(0xFF3A3342),
    text: Color(0xFFEDE8E3),
    textSecondary: Color(0xFFDAC2B2),
    textFaint: Color(0xFFA28C7F),
    accent: Color(0xFFE88A3C),
    onAccent: Color(0xFF141019),
    running: Color(0xFF8FAE8A),
    paused: Color(0xFF8A8494),
    motion: Color(0xFF7C93A6),
    fault: Color(0xFFC25B56),
  );

  static const light = Palette(
    bg: Color(0xFFF4F0EA),
    surface: Color(0xFFFBF8F3),
    inset: Color(0xFFF0EAE0),
    raised: Color(0xFFE9E2D6),
    hairline: Color(0xFFD8D0C4),
    text: Color(0xFF141019),
    textSecondary: Color(0xFF5B5361),
    textFaint: Color(0xFF7A7178),
    accent: Color(0xFFB8601A),
    onAccent: Color(0xFFFBF8F3),
    running: Color(0xFF5E7F5A),
    paused: Color(0xFF8A8494),
    motion: Color(0xFF5A7285),
    fault: Color(0xFFA8413C),
  );

  @override
  Palette copyWith({
    Color? bg,
    Color? surface,
    Color? inset,
    Color? raised,
    Color? hairline,
    Color? text,
    Color? textSecondary,
    Color? textFaint,
    Color? accent,
    Color? onAccent,
    Color? running,
    Color? paused,
    Color? motion,
    Color? fault,
  }) {
    return Palette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      inset: inset ?? this.inset,
      raised: raised ?? this.raised,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      running: running ?? this.running,
      paused: paused ?? this.paused,
      motion: motion ?? this.motion,
      fault: fault ?? this.fault,
    );
  }

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    return Palette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      running: Color.lerp(running, other.running, t)!,
      paused: Color.lerp(paused, other.paused, t)!,
      motion: Color.lerp(motion, other.motion, t)!,
      fault: Color.lerp(fault, other.fault, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

/// Typography: Barlow Condensed for labels/buttons/body, JetBrains Mono
/// (tabular figures) for all numeric readouts.
class AppText {
  AppText._();

  static TextStyle dispNumeric = GoogleFonts.jetBrainsMono(
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 44 / 40,
    letterSpacing: -0.02,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle readoutSecondary = GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 20 / 16,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle readoutMicro = GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle panelTitle = GoogleFonts.barlowCondensed(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 24 / 20,
    letterSpacing: 0.02,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 20 / 15,
    letterSpacing: 0.01,
  );

  static TextStyle labelCaps = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 0.08,
  );

  static TextStyle labelMicro = GoogleFonts.barlowCondensed(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 14 / 10,
    letterSpacing: 0.08,
  );

  static TextStyle buttonText = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 16 / 13,
    letterSpacing: 0.06,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      surface: p.bg,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
  );
}
