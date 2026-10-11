import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../core/dates.dart';
import '../domain/child_id.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import '../domain/text_match.dart';
import 'db.dart';
import 'models.dart';

class ChildSummary {
  final Child child;
  final Schedule schedule;
  const ChildSummary(this.child, this.schedule);
}

/// All reads and writes go through here so every change is audited
/// (FRS-REG-10, 12, FRS-SEC-09).
class Repo {
  static Database get _db => AppDb.db;
  static String currentUser = 'worker';

  static String _now() => DateTime.now().toUtc().toIso8601String();

  // ---------- settings ----------
  static Future<String?> getSetting(String key) async {
    final r = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> setSetting(String key, String? value, {bool audit = true}) async {
    final old = await getSetting(key);
    await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    if (audit && old != value && !key.startsWith('pin_') && !key.startsWith('lock_') && !key.startsWith('fail_')) {
      await logAudit('settings_change', 'settings', key, '$old -> $value');
    }
  }

  // ---------- audit ----------
  static Future<void> logAudit(String action, String entity, String? entityId, String? detail,
      {DatabaseExecutor? ex}) async {
    await (ex ?? _db).insert('audit', {
      'ts': _now(),
      'user': currentUser,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'detail': detail,
    });
  }

  static Future<List<AuditEntry>> auditLog({int limit = 500}) async {
    final r = await _db.query('audit', orderBy: 'id DESC', limit: limit);
    return r.map(AuditEntry.fromMap).toList();
  }

  // ---------- facilities ----------
  static Future<List<Facility>> facilities() async {
    final r = await _db.query('facilities', orderBy: 'name');
    return r.map(Facility.fromMap).toList();
  }

  static Future<Facility?> facility(int id) async {
    final r = await _db.query('facilities', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Facility.fromMap(r.first);
  }

  static Future<int> addFacility(String code, String name, String governorate, String district) async {
    final id = await _db.insert('facilities', {
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'governorate': governorate.trim(),
      'district': district.trim(),
    });
    await logAudit('create', 'facility', '$id', '$code $name');
    return id;
  }

  // ---------- children ----------
  static Future<int> _nextSeq(DatabaseExecutor ex) async {
    final r = await ex.rawQuery('SELECT MAX(seq) AS m FROM children');
    return ((r.first['m'] as int?) ?? 0) + 1;
  }

  static Future<String> createChild(Map<String, Object?> fields, String deviceCode) async {
    return _db.transaction((txn) async {
      final seq = await _nextSeq(txn);
      final id = makeChildId(deviceCode, seq);
      await txn.insert('children', {
        ...fields,
        'id': id,
        'seq': seq,
        'created_by': currentUser,
        'created_at': _now(),
      });
      await logAudit('create', 'child', id, jsonEncode(fields), ex: txn);
      return id;
    });
  }

  static Future<void> updateChild(Child before, Map<String, Object?> fields) async {
    final old = before.editable();
    final changes = <String, Object?>{};
    fields.forEach((k, v) {
      if (old[k] != v) changes[k] = v;
    });
    if (changes.isEmpty) return;
    await _db.transaction((txn) async {
      await txn.update('children', {...changes, 'modified_by': currentUser, 'modified_at': _now()},
          where: 'id = ?', whereArgs: [before.id]);
      for (final e in changes.entries) {
        await logAudit('update', 'child', before.id, '${e.key}: ${old[e.key]} -> ${e.value}', ex: txn);
      }
    });
  }

  static Future<void> voidChild(String id, String reason) async {
    await _db.transaction((txn) async {
      await txn.update('children', {'voided': 1, 'void_reason': reason, 'modified_by': currentUser, 'modified_at': _now()},
          where: 'id = ?', whereArgs: [id]);
      await logAudit('void', 'child', id, reason, ex: txn);
    });
  }

  static Future<void> markHistoryDone(String id) async {
    await _db.update('children', {'history_done': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<Child?> child(String id) async {
    final r = await _db.query('children', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Child.fromMap(r.first);
  }

  static Future<List<Child>> activeChildren() async {
    final r = await _db.query('children', where: 'voided = 0', orderBy: 'seq DESC');
    return r.map(Child.fromMap).toList();
  }

  /// Possible duplicates on this device (FRS-REG-07).
  static Future<List<Child>> possibleDuplicates({
    required String name,
    required DateTime dob,
    required String guardianName,
    String? phone,
    String? excludeId,
  }) async {
    final r = await _db.query('children', where: 'voided = 0 AND dob = ?', whereArgs: [iso(dob)]);
    final phoneN = phone == null ? '' : normalizePhone(phone);
    return r.map(Child.fromMap).where((c) {
      if (c.id == excludeId) return false;
      if (!similarNames(c.name, name)) return false;
      final samePhone = phoneN.isNotEmpty && c.phone != null && normalizePhone(c.phone!) == phoneN;
      return samePhone || similarNames(c.guardianName, guardianName);
    }).toList();
  }

  // ---------- doses ----------
  static Future<List<DoseRecord>> doses(String childId) async {
    final r = await _db.query('doses', where: 'child_id = ? AND voided = 0', whereArgs: [childId], orderBy: 'id');
    return r.map(DoseRecord.fromMap).toList();
  }

  static Map<String, DateTime> givenMap(List<DoseRecord> records) {
    final m = <String, DateTime>{};
    for (final d in records) {
      if (d.status == 'given' && d.givenDate != null) m[d.code] = d.givenDate!;
    }
    return m;
  }

  static Future<Schedule> schedule(Child c) async {
    final recs = await doses(c.id);
    return Engine.compute(dob: c.dob, given: givenMap(recs));
  }

  /// Every active child with its schedule, for lists, filters and reminders.
  static Future<List<ChildSummary>> summaries() async {
    final kids = await activeChildren();
    final r = await _db.query('doses', where: "voided = 0 AND status = 'given'");
    final byChild = <String, Map<String, DateTime>>{};
    for (final m in r) {
      final d = DoseRecord.fromMap(m);
      if (d.givenDate != null) (byChild[d.childId] ??= {})[d.code] = d.givenDate!;
    }
    return [for (final c in kids) ChildSummary(c, Engine.compute(dob: c.dob, given: byChild[c.id] ?? const {}))];
  }

  static Future<int> recordVisit({
    required String childId,
    required DateTime date,
    required String site,
    required int? facilityId,
    required List<String> given,
    required Map<String, String> notGivenReasons,
  }) async {
    return _db.transaction((txn) async {
      final visitId = await txn.insert('visits', {
        'child_id': childId,
        'date': iso(date),
        'site': site,
        'facility_id': facilityId,
        'worker': currentUser,
        'created_at': _now(),
      });
      for (final code in given) {
        await txn.insert('doses', {
          'child_id': childId,
          'code': code,
          'status': 'given',
          'given_date': iso(date),
          'visit_id': visitId,
          'source': 'visit',
          'rule_version': RuleSet.version,
          'created_by': currentUser,
          'created_at': _now(),
        });
      }
      for (final e in notGivenReasons.entries) {
        await txn.insert('doses', {
          'child_id': childId,
          'code': e.key,
          'status': 'not_given',
          'visit_id': visitId,
          'source': 'visit',
          'reason': e.value,
          'rule_version': RuleSet.version,
          'created_by': currentUser,
          'created_at': _now(),
        });
      }
      await logAudit('visit', 'child', childId,
          'date=${iso(date)} site=$site given=${given.join(',')} not_given=${notGivenReasons.keys.join(',')}',
          ex: txn);
      return visitId;
    });
  }

  static Future<void> recordHistory(String childId, List<HistoryEntry> entries, String source) async {
    await _db.transaction((txn) async {
      for (final e in entries) {
        await txn.insert('doses', {
          'child_id': childId,
          'code': e.code,
          'status': e.status,
          'given_date': e.date == null ? null : iso(e.date!),
          'source': source,
          'rule_version': RuleSet.version,
          'created_by': currentUser,
          'created_at': _now(),
        });
      }
      await txn.update('children', {'history_done': 1}, where: 'id = ?', whereArgs: [childId]);
      await logAudit('history', 'child', childId,
          entries.map((e) => '${e.code}:${e.status}${e.date == null ? '' : '@${iso(e.date!)}'}').join(' '),
          ex: txn);
    });
  }

  static Future<void> addCampaignDose(String childId, String campaign, DateTime date) async {
    await _db.transaction((txn) async {
      await txn.insert('doses', {
        'child_id': childId,
        'code': 'CAMPAIGN',
        'status': 'campaign',
        'given_date': iso(date),
        'source': 'campaign',
        'campaign_name': campaign,
        'rule_version': RuleSet.version,
        'created_by': currentUser,
        'created_at': _now(),
      });
      await logAudit('campaign', 'child', childId, '$campaign @ ${iso(date)}', ex: txn);
    });
  }

  static Future<void> voidDose(DoseRecord d, String reason) async {
    await _db.transaction((txn) async {
      await txn.update('doses', {'voided': 1, 'void_reason': reason}, where: 'id = ?', whereArgs: [d.id]);
      await logAudit('void', 'dose', d.childId, '${d.code} ${d.givenDate == null ? '' : iso(d.givenDate!)}: $reason',
          ex: txn);
    });
  }

  // ---------- calendar ----------
  static Future<Map<String, int>> calendarEvents() async {
    final r = await _db.query('calendar_events');
    return {for (final m in r) m['child_id'] as String: m['event_id'] as int};
  }

  static Future<void> setCalendarEvent(String childId, int? eventId) async {
    if (eventId == null) {
      await _db.delete('calendar_events', where: 'child_id = ?', whereArgs: [childId]);
    } else {
      await _db.insert('calendar_events', {'child_id': childId, 'event_id': eventId},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
