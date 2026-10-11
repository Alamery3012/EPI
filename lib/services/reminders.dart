import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
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
    final groups = <String, List<String>>{};
    for (final s in list) {
      final next = s.schedule.nextVisit;
      if (next == null) continue;
      final overdue = s.schedule.hasOverdue;
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
        (groups['${iso(d)}|$kind'] ??= []).add('${s.child.name} (${s.child.id})');
      }
    }
    final alarms = <Map<String, Object?>>[];
    var id = 1000;
    final keys = groups.keys.toList()..sort();
    for (final k in keys) {
      final parts = k.split('|');
      final d = parseIso(parts[0]);
      final kind = parts[1];
      final names = groups[k]!;
      final title = kind == 'before'
          ? tf('notif_title_before', {'n': app.offsetBefore})
          : kind == 'on'
              ? t('notif_title_on')
              : t('notif_title_after');
      final shown = names.take(5).join('، ');
      final more = names.length > 5 ? ' …' : '';
      alarms.add({
        'id': id++,
        'at': DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch,
        'title': '$title - ${tf('notif_children', {'n': names.length})}',
        'body': '$shown$more',
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
      final doses = s.schedule.doses
          .where((d) => d.actionable || (d.status == DoseStatus.upcoming && d.dueDate == next))
          .map((d) => d.rule.label(Lang.current.value))
          .join(', ');
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
