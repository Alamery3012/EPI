import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours sampled from the YFCA logo (blue figure and wordmark, orange swoosh),
/// extended into a calm clinical palette. Text colours meet WCAG AA (4.5:1) on
/// the backgrounds they are used on.
class Brand {
  static const blue = Color(0xFF0D7CBC);
  static const blueDark = Color(0xFF0A5C8C);
  static const navy = Color(0xFF0B3954);
  static const blueSoft = Color(0xFFE7F2FA);
  static const orange = Color(0xFFE77632);
  static const orangeSoft = Color(0xFFFDEEE5);
  static const ink = Color(0xFF14212E);
  static const muted = Color(0xFF5E6B78);
  static const surface = Color(0xFFF3F6FA);
  static const line = Color(0xFFE3E9F0);
  static const good = Color(0xFF256B42);
  static const goodSoft = Color(0xFFE5F2EA);
  static const warn = Color(0xFF8A5A12);
  static const warnSoft = Color(0xFFF7EEDF);
  static const bad = Color(0xFFB03427);
  static const badSoft = Color(0xFFFBE9E7);
  static const wait = Color(0xFF6B4FA0);
  static const waitSoft = Color(0xFFF0ECF7);

  /// Header gradient: deep navy into YFCA blue.
  static const headerGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [navy, blueDark, blue],
    stops: [0, 0.55, 1],
  );

  static const cardShadow = [
    BoxShadow(color: Color(0x0F0B3954), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A0B3954), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

const _font = 'Plex';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.orange,
    surface: Colors.white,
    error: Brand.bad,
  ).copyWith(onSurface: Brand.ink, surfaceTint: Colors.transparent);
  final r14 = BorderRadius.circular(14);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _font);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.surface,
    textTheme: base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink, fontFamily: _font),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.surface,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 19, fontWeight: FontWeight.w700, color: Brand.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: Brand.muted),
      floatingLabelStyle: const TextStyle(color: Brand.blueDark, fontWeight: FontWeight.w600),
      border: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: Brand.blue, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: Brand.bad)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Brand.line,
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: r14),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.blueDark,
        backgroundColor: Colors.white,
        minimumSize: const Size(64, 50),
        side: const BorderSide(color: Brand.line),
        shape: RoundedRectangleBorder(borderRadius: r14),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.blueDark,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blueSoft : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blueDark : Brand.ink),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: _font, fontWeight: FontWeight.w600)),
      ),
    ),
    // Ink on orange: white on orange is only 3.0:1.
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.orange,
      foregroundColor: Brand.ink,
      elevation: 3,
      extendedTextStyle: TextStyle(fontFamily: _font, fontSize: 15.5, fontWeight: FontWeight.w700),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Brand.blueSoft,
      labelStyle: const TextStyle(fontFamily: _font, color: Brand.ink, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      side: const BorderSide(color: Brand.line),
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(fontFamily: _font, fontSize: 19, fontWeight: FontWeight.w700, color: Brand.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Brand.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r14),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.blue),
    dividerColor: Brand.line,
    dividerTheme: const DividerThemeData(color: Brand.line, space: 1),
  );
}

/// White rounded card with a soft shadow, the base surface of every screen.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: borderColor == null ? null : Border.all(color: borderColor!),
          boxShadow: color == null ? Brand.cardShadow : null,
        ),
        child: child,
      );
}

/// Status chip: soft tinted background, full-colour text and optional icon.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.11), Colors.white),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
        ]),
      );
}

/// Section heading with the orange accent bar that echoes the logo swoosh.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [
          Container(width: 4, height: 20, decoration: BoxDecoration(color: Brand.orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Brand.ink))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Rounded square with a soft tint behind an icon.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, this.color, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.12), Colors.white),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// Circle with the child's initials.
class Initials extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const Initials(this.name, {super.key, this.color = Brand.blue, this.size = 46});

  static String of(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = parts.first.characters.first;
    final b = parts.length > 1 ? parts[1].characters.first : '';
    return '$a$b';
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Color.alphaBlend(color.withOpacity(0.14), Colors.white), shape: BoxShape.circle),
        child: Text(of(name), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.34)),
      );
}

/// Circular progress of doses given, with text in the middle.
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? center;
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 48,
    this.stroke = 5,
    this.color = Brand.good,
    this.track = Brand.line,
    this.center,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0, 1).toDouble(), stroke, color, track),
          child: Center(child: center),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final Color color;
  final Color track;
  _RingPainter(this.v, this.stroke, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final bg = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, bg);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Gradient header used at the top of the main screens.
class GradientHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GradientHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: Brand.headerGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
      );
}

/// Label/value row used in detail cards.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: Brand.muted),
          const SizedBox(width: 10),
          SizedBox(width: 104, child: Text(label, style: const TextStyle(color: Brand.muted, fontSize: 13.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.ink, fontSize: 14.5))),
        ]),
      );
}
