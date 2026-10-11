// End-to-end walkthrough of v0.2.0 on an Android emulator in CI.
// Covers setup, registration, the clinical flow (overdue child, visit,
// catch-up), documents, intake, settings, English layout and the PIN lock,
// saving a screenshot at each step. Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:epi_app/app_state.dart';
import 'package:epi_app/core/dates.dart';
import 'package:epi_app/data/models.dart';
import 'package:epi_app/data/repo.dart';
import 'package:epi_app/main.dart' as app_main;
import 'package:epi_app/services/card_pdf.dart';

late final IntegrationTestWidgetsFlutterBinding binding;
final failures = <String>[];
var shotNo = 0;

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t, 6);
  shotNo++;
  try {
    await binding.takeScreenshot('${shotNo.toString().padLeft(2, '0')}_$name');
  } catch (e) {
    debugPrint('screenshot $name failed: $e');
  }
}

/// Runs one part of the walkthrough; a failure is recorded with a screenshot
/// and the walkthrough carries on, so one bug does not hide the others.
Future<void> step(WidgetTester t, String name, Future<void> Function() body) async {
  try {
    await body();
    debugPrint('STEP OK  $name');
  } catch (e, st) {
    failures.add('$name: $e');
    debugPrint('STEP FAIL $name: $e\n$st');
    await shot(t, 'FAIL_$name');
    // Get back to the home screen without ever closing the app.
    for (var i = 0; i < 6 && (app_main.navKey.currentState?.canPop() ?? false); i++) {
      app_main.navKey.currentState!.pop();
      await settle(t, 6);
    }
  }
}

/// The biggest vertical scrollable on screen (the page's main list).
Finder mainScrollable() {
  Element? best;
  var area = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final w = e.widget as Scrollable;
    if (axisDirectionToAxis(w.axisDirection) != Axis.vertical) continue;
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final a = box.size.width * box.size.height;
    if (a > area) {
      area = a;
      best = e;
    }
  }
  return find.byElementPredicate((e) => identical(e, best));
}

/// Scrolls the main list (down, then up) until [f] is built and visible.
/// Lists build only what is on screen, so off-screen items must be revealed.
Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    try {
      await t.scrollUntilVisible(f, 300, scrollable: mainScrollable(), maxScrolls: 30);
    } catch (_) {
      await t.scrollUntilVisible(f, -300, scrollable: mainScrollable(), maxScrolls: 30);
    }
  }
  await t.ensureVisible(f.first);
  await settle(t, 3);
}

Future<void> tapKey(WidgetTester t, String key, {int frames = 12}) async {
  final f = find.byKey(Key(key));
  await reveal(t, f);
  await t.tap(f.first);
  await settle(t, frames);
}

Future<void> typeKey(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await reveal(t, f);
  await t.enterText(f.first, text);
  await settle(t, 2);
}

/// Android Back, but never on the home screen (that would close the app).
Future<void> back(WidgetTester t) async {
  if (app_main.navKey.currentState?.canPop() ?? false) {
    await t.binding.handlePopRoute();
  }
  await settle(t, 10);
}

/// Pull-to-refresh on the home list.
Future<void> refreshHome(WidgetTester t) async {
  await t.fling(find.byType(CustomScrollView), const Offset(0, 500), 1200);
  await settle(t, 30);
}

Future<void> scrollTo(WidgetTester t, Finder f) => reveal(t, f);

Future<String> seedChild(String name, String sex, int ageDays, String guardian, List<HistoryEntry> history) async {
  final dob = addDays(today(), -ageDays);
  final id = await Repo.createChild({
    'name': name,
    'name_latin': null,
    'sex': sex,
    'dob': iso(dob),
    'birth_weight': 3100,
    'facility_id': app.defaultFacilityId,
    'area': 'ريمي',
    'guardian_name': guardian,
    'guardian_relation': 'mother',
    'phone': '777123456',
  }, app.deviceCode);
  if (history.isNotEmpty) await Repo.recordHistory(id, history, 'card');
  return id;
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPI app v0.2.0 walkthrough', (t) async {
    app_main.main();
    await settle(t, 40);
    await binding.convertFlutterSurfaceToImage();
    await settle(t);

    // ---------- First-time setup (3 steps) ----------
    await step(t, 'setup', () async {
      await shot(t, 'setup_step1');
      await typeKey(t, 'setup_device', 'TAB01');
      await typeKey(t, 'setup_worker', 'حنان السلمي');
      await tapKey(t, 'setup_next');
      await typeKey(t, 'setup_fname', 'مركز المنصورة الصحي');
      await typeKey(t, 'setup_fcode', 'ADN07');
      await typeKey(t, 'setup_gov', 'عدن');
      await typeKey(t, 'setup_dist', 'المنصورة');
      await shot(t, 'setup_step2');
      await tapKey(t, 'setup_next');
      await typeKey(t, 'setup_wpin', '135790');
      await typeKey(t, 'setup_wpin2', '135790');
      await typeKey(t, 'setup_apin', '246802');
      await typeKey(t, 'setup_apin2', '246802');
      await shot(t, 'setup_step3');
      await tapKey(t, 'setup_next', frames: 50);
      expect(find.byKey(const Key('fab_register')), findsOneWidget, reason: 'home after setup');
      await shot(t, 'home_empty');
    });

    // ---------- Seed realistic children through the data layer ----------
    late String overdueId, intakeId;
    await step(t, 'seed', () async {
      final birth = addDays(today(), -120);
      overdueId = await seedChild('فاطمة أحمد علي', 'F', 120, 'أمل سالم', [
        HistoryEntry('BCG', 'given', birth),
        HistoryEntry('OPV0', 'given', birth),
        HistoryEntry('HEPB0', 'given', birth),
      ]);
      final b2 = addDays(today(), -44);
      await seedChild('سالم خالد بن عوض', 'M', 44, 'نورة سعيد', [
        HistoryEntry('BCG', 'given', b2),
        HistoryEntry('OPV0', 'given', b2),
        HistoryEntry('HEPB0', 'given', b2),
      ]);
      final b3 = addDays(today(), -275);
      await seedChild('مريم عبدالله ناصر', 'F', 275, 'هدى ناصر', [
        for (final c in ['BCG', 'OPV0', 'HEPB0']) HistoryEntry(c, 'given', b3),
        for (final c in ['PENTA1', 'OPV1', 'ROTA1', 'PCV1']) HistoryEntry(c, 'given', addDays(b3, 42)),
        for (final c in ['PENTA2', 'OPV2', 'ROTA2']) HistoryEntry(c, 'given', addDays(b3, 70)),
        for (final c in ['PENTA3', 'OPV3', 'PCV2', 'IPV1']) HistoryEntry(c, 'given', addDays(b3, 98)),
      ]);
      intakeId = await seedChild('محمد سالم عوض', 'M', 150, 'ليلى عوض', const []);
      // Pull to refresh the home list.
      await refreshHome(t);
      await reveal(t, find.byKey(Key('child_$overdueId')));
      expect(find.byKey(Key('child_$overdueId')), findsOneWidget);
      await t.fling(mainScrollable(), const Offset(0, 1500), 2500); // back to top
      await settle(t, 15);
      await shot(t, 'home_children');
    });

    // ---------- Register a newborn through the form ----------
    await step(t, 'register', () async {
      await tapKey(t, 'fab_register');
      await shot(t, 'register_form');
      await typeKey(t, 'reg_name', 'سارة محمد علي');
      await t.tap(find.byIcon(Icons.female));
      await settle(t, 4);
      await tapKey(t, 'reg_dob');
      final ok = find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextButton)).last;
      await t.tap(ok); // today
      await settle(t, 8);
      await typeKey(t, 'reg_guardian', 'منى أحمد');
      await typeKey(t, 'reg_phone', '771234567');
      await shot(t, 'register_filled');
      await tapKey(t, 'reg_save', frames: 40);
      expect(find.byKey(const Key('child_record_visit')), findsOneWidget, reason: 'child record opens after saving');
      await shot(t, 'child_newborn');
      await back(t);
    });

    // ---------- Overdue child: record, visit, documents ----------
    await step(t, 'child_overdue', () async {
      final card = find.byKey(Key('child_$overdueId'));
      await scrollTo(t, card);
      await t.tap(card);
      await settle(t, 25);
      await shot(t, 'child_overdue_top');
      await scrollTo(t, find.text('9 أشهر'));
      await shot(t, 'child_timeline');
    });

    await step(t, 'visit', () async {
      await scrollTo(t, find.byKey(const Key('child_record_visit')));
      await tapKey(t, 'child_record_visit', frames: 20);
      await shot(t, 'visit_open');
      for (final code in ['PENTA1', 'OPV1', 'PCV1']) {
        await tapKey(t, 'dose_$code', frames: 4);
      }
      await shot(t, 'visit_selected');
      await tapKey(t, 'visit_save', frames: 40);
      expect(find.byKey(const Key('child_record_visit')), findsOneWidget, reason: 'back on the child record');
      await shot(t, 'child_after_visit');
    });

    await step(t, 'card_pdf', () async {
      // The A4 card must always be exactly one page (FRS-DOC-04), in both languages.
      final c = (await Repo.child(overdueId))!;
      final recs = await Repo.doses(c.id);
      final sch = await Repo.schedule(c);
      for (final lang in ['ar', 'en']) {
        final bytes = await CardPdf.build(
          child: c,
          facility: await Repo.facility(c.facilityId),
          schedule: sch,
          campaignDoses: recs.where((r) => r.status == 'campaign').toList(),
          language: lang,
        );
        final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
        expect(pages, 1, reason: 'card pages ($lang)');
      }
      await scrollTo(t, find.byKey(const Key('child_card')));
      await tapKey(t, 'child_card', frames: 15);
      await shot(t, 'card_sheet');
      await back(t);
    });

    await step(t, 'excel', () async {
      await tapKey(t, 'child_excel', frames: 10);
      await shot(t, 'excel_warning');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await settle(t, 20);
      await shot(t, 'excel_saved');
      await back(t);
    });

    // ---------- Past-visit intake for a child registered late ----------
    await step(t, 'intake', () async {
      final card = find.byKey(Key('child_$intakeId'));
      await scrollTo(t, card);
      await t.tap(card);
      await settle(t, 25);
      await tapKey(t, 'child_start_intake', frames: 20);
      await shot(t, 'intake_step1');
      for (var i = 0; i < 6 && find.byKey(const Key('intake_close')).evaluate().isEmpty; i++) {
        await tapKey(t, 'intake_next', frames: 15);
      }
      await shot(t, 'intake_done');
      await tapKey(t, 'intake_close', frames: 25);
      await shot(t, 'child_after_intake');
      await back(t);
    });

    // ---------- Settings (admin) ----------
    await step(t, 'settings', () async {
      await scrollTo(t, find.byKey(const Key('home_settings')));
      await tapKey(t, 'home_settings', frames: 20);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '246802');
        await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
        await settle(t, 20);
      }
      await shot(t, 'settings');
      await tapKey(t, 'settings_audit', frames: 20);
      await shot(t, 'audit_log');
      await back(t);
      await back(t);
    });

    // ---------- English layout ----------
    await step(t, 'english', () async {
      await scrollTo(t, find.byKey(const Key('lang_toggle')));
      await tapKey(t, 'lang_toggle', frames: 20);
      await shot(t, 'home_english');
      final card = find.byKey(Key('child_$overdueId'));
      await scrollTo(t, card);
      await t.tap(card);
      await settle(t, 25);
      await shot(t, 'child_english');
      await back(t);
      await scrollTo(t, find.byKey(const Key('lang_toggle')));
      await tapKey(t, 'lang_toggle', frames: 20);
    });

    // ---------- Lock and unlock with the PIN pad ----------
    await step(t, 'lock', () async {
      await scrollTo(t, find.byKey(const Key('home_lock')));
      await tapKey(t, 'home_lock', frames: 20);
      await shot(t, 'lock');
      for (final d in '135790'.split('')) {
        await t.tap(find.byKey(Key('pin_$d')));
        await settle(t, 2);
      }
      await settle(t, 30);
      expect(find.byKey(const Key('fab_register')), findsOneWidget, reason: 'unlocked with the worker PIN');
      await shot(t, 'unlocked_home');
    });

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
