import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../data/repo.dart';
import 'native.dart';

/// Rebuilds every reminder and calendar event from the database
/// (FRS-REM-01..09). Called after any change and at each unlock, so the
/// result never depends on what was scheduled before.
class Reminders {
  static bool _running = false;

  static Future<void> rebuild() async {
    if (_running) return;
    _running = true;
    try {
      final list = await Repo.summaries();
      await _alarms(list);
      if (app.calendarSync) await _calendar(list);
    } catch (e) {
      debugPrint('reminder rebuild failed: $e');
    } finally {
      _running = false;
    }
  }

  static Future<void> _alarms(List<ChildSummary> list) async {
    final now = DateTime.now();
    final lang = Lang.current.value;
    // date|kind -> lines "name (ID): doses", plus the child IDs for deep links.
    final groups = <String, List<String>>{};
    final ids = <String, List<String>>{};
    for (final s in list) {
      final next = s.schedule.nextVisit;
      if (next == null) continue;
      final overdue = s.schedule.hasOverdue;
      final doses = s.schedule.nextVisitDoses.map((d) => d.rule.label(lang)).join(lang == 'ar' ? '، ' : ', ');
      final plan = <MapEntry<String, int>>[
        if (!overdue) MapEntry('before', -app.offsetBefore),
        const MapEntry('on', 0),
        MapEntry('after', app.offsetAfter),
      ];
      for (final p in plan) {
        final d = addDays(next, p.value);
        final at = DateTime(d.year, d.month, d.day, 9);
        if (!at.isAfter(now)) continue;
        final kind = overdue && p.key == 'on' ? 'after' : p.key;
        final key = '${iso(d)}|$kind';
        (groups[key] ??= []).add('${s.child.name} (${s.child.id}): $doses');
        (ids[key] ??= []).add(s.child.id);
      }
    }
    final alarms = <Map<String, Object?>>[];
    var id = 1000;
    final keys = groups.keys.toList()..sort();
    for (final k in keys) {
      final parts = k.split('|');
      final d = parseIso(parts[0]);
      final kind = parts[1];
      final lines = groups[k]!;
      final title = kind == 'before'
          ? tf('notif_title_before', {'n': app.offsetBefore})
          : kind == 'on'
              ? t('notif_title_on')
              : t('notif_title_after');
      final shown = lines.take(6).join('\n');
      final more = lines.length > 6 ? '\n…' : '';
      alarms.add({
        'id': id++,
        'at': DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch,
        'title': '$title · ${fmt(d)} · ${tf('notif_children', {'n': lines.length})}',
        'body': '$shown$more',
        // One child opens the record; several open the due list (FRS-REM-02, 03).
        'child': lines.length == 1 ? ids[k]!.first : '',
      });
    }
    await NativeBridge.setReminders(alarms);
  }

  static Future<void> _calendar(List<ChildSummary> list) async {
    final existing = await Repo.calendarEvents();
    for (final s in list) {
      final next = s.schedule.nextVisit;
      final eventId = existing[s.child.id];
      if (next == null) {
        if (eventId != null) {
          await NativeBridge.calendarDelete(eventId);
          await Repo.setCalendarEvent(s.child.id, null);
        }
        continue;
      }
      final doses = s.schedule.nextVisitDoses.map((d) => d.rule.label(Lang.current.value)).join(', ');
      final start = DateTime(next.year, next.month, next.day, 9).millisecondsSinceEpoch;
      // Child ID only, no name, in the shared calendar (FRS-REM-10).
      final newId = await NativeBridge.calendarUpsert(
        eventId: eventId,
        title: '${t('app_title')}: ${s.child.id}',
        description: doses,
        startMillis: start,
      );
      if (newId != null && newId != eventId) await Repo.setCalendarEvent(s.child.id, newId);
    }
  }
}
