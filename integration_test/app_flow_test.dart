// End-to-end walkthrough run on an Android emulator in CI.
// It completes first-time setup, then visits the main screens and saves a
// screenshot of each. Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:epi_app/main.dart' as app;

late final IntegrationTestWidgetsFlutterBinding binding;

Future<void> settle(WidgetTester t, [int frames = 25]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t, 5);
  try {
    await binding.takeScreenshot(name);
  } catch (e) {
    debugPrint('screenshot $name failed: $e');
  }
}

void main() {
  // Must run before testWidgets() so the integration binding is the one in use.
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPI app walkthrough', (t) async {
    app.main();
    await settle(t, 40);
    await binding.convertFlutterSurfaceToImage();
    await settle(t);
    await shot(t, '01_setup_empty');

    // ---- First-time setup: 10 fields in order ----
    final values = ['TAB01', 'Hanan Al-Sulami', 'Al-Mansoura Health Centre', 'ADN07', 'Aden', 'Al-Mansoura',
      '135790', '135790', '246802', '246802'];
    // The form is a lazy ListView: fill the first empty field on screen,
    // scrolling down when every visible field is already filled.
    final done = <TextEditingController>{};
    for (var i = 0; i < values.length; i++) {
      TextEditingController? ctrl;
      for (var tries = 0; tries < 12 && ctrl == null; tries++) {
        // Tree order = form order; take the first field not filled yet.
        for (final e in find.byType(TextFormField).evaluate()) {
          final c = (e.widget as TextFormField).controller;
          if (c != null && !done.contains(c)) { ctrl = c; break; }
        }
        if (ctrl == null) {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
          await settle(t, 3);
        }
      }
      expect(ctrl, isNotNull, reason: 'setup field ${i + 1}');
      // Stable finder: the field that owns this controller, wherever it scrolls.
      final field = find.byWidgetPredicate((w) => w is TextFormField && identical(w.controller, ctrl));
      await t.ensureVisible(field);
      await settle(t, 2);
      await t.enterText(field, values[i]);
      done.add(ctrl!);
      await settle(t, 2);
    }
    await shot(t, '02_setup_filled');
    for (var tries = 0; tries < 10 && find.byType(FilledButton).evaluate().isEmpty; tries++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(t, 3);
    }
    final save = find.byType(FilledButton).last;
    await t.ensureVisible(save);
    await settle(t, 2);
    await t.tap(save);
    await settle(t, 50);
    await shot(t, '03_home_empty');

    // ---- Register child screen ----
    final fab = find.byType(FloatingActionButton);
    if (fab.evaluate().isNotEmpty) {
      await t.tap(fab.first);
      await settle(t);
      await shot(t, '04_register');
      await t.pageBack();
      await settle(t);
    }

    // ---- English layout ----
    final toggle = find.text('English');
    if (toggle.evaluate().isNotEmpty) {
      await t.tap(toggle.first);
      await settle(t);
      await shot(t, '05_home_english');
      final ar = find.text('العربية');
      if (ar.evaluate().isNotEmpty) {
        await t.tap(ar.first);
        await settle(t);
      }
    }

    // ---- Settings (admin PIN prompt if needed) ----
    final gear = find.byIcon(Icons.settings_outlined);
    if (gear.evaluate().isNotEmpty) {
      await t.tap(gear.first);
      await settle(t);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await shot(t, '06_admin_pin');
        await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '246802');
        await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
        await settle(t);
      }
      await shot(t, '07_settings');
      await t.pageBack();
      await settle(t);
    }

    // ---- Lock screen ----
    final lock = find.byIcon(Icons.lock_outline);
    if (lock.evaluate().isNotEmpty) {
      await t.tap(lock.first);
      await settle(t);
      await shot(t, '08_lock');
    }
  });
}
