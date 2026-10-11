import 'package:flutter/material.dart';

/// Colours sampled from the YFCA logo (blue figure and wordmark, orange swoosh).
class Brand {
  static const blue = Color(0xFF0D7CBC);
  static const blueDark = Color(0xFF0A5C8C);
  static const blueSoft = Color(0xFFE6F2FA);
  static const orange = Color(0xFFE77632);
  static const orangeSoft = Color(0xFFFCEDE4);
  static const ink = Color(0xFF1B2A38);
  static const muted = Color(0xFF5E6B78);
  static const surface = Color(0xFFF4F7FA);
  static const line = Color(0xFFDCE3EA);
  static const good = Color(0xFF256B42);
  static const warn = Color(0xFF8A5A12);
  static const bad = Color(0xFFB03427);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.orange,
    surface: Colors.white,
    error: Brand.bad,
  );
  final radius = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.blue,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.blue, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.blueDark,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: Brand.blue),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Brand.blueDark, minimumSize: const Size(48, 48))),
    // Ink on orange: white on orange is only 3.0:1 (design system, Fab card).
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.orange,
      foregroundColor: Brand.ink,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: Brand.line),
    ),
    dividerColor: Brand.line,
  );
}

/// White rounded panel used across screens.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: child,
      );
}

/// Small status pill.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.12), Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3)),
      );
}

/// Orange accent bar under section titles, echoing the logo swoosh.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Brand.ink)),
            const SizedBox(height: 6),
            Container(width: 36, height: 3, decoration: BoxDecoration(color: Brand.orange, borderRadius: BorderRadius.circular(2))),
          ],
        ),
      );
}
