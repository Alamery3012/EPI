import '../core/dates.dart';
import 'rules.dart';

/// waiting = old enough for the dose, but the minimum interval or live-vaccine
/// spacing has not passed yet (FRS-SCH-02 "contraindicated by spacing").
enum DoseStatus { given, due, overdue, upcoming, waiting, notEligible }

class DoseState {
  final DoseRule rule;
  final DoseStatus status;
  final DateTime? dueDate;
  final DateTime? givenDate;
  final DateTime? earliest;
  const DoseState(this.rule, this.status, {this.dueDate, this.givenDate, this.earliest});

  bool get actionable => status == DoseStatus.due || status == DoseStatus.overdue;
}

class Schedule {
  final List<DoseState> doses;
  final DateTime? nextVisit;
  final int? firstMissedMilestone;
  final String ruleVersion;
  const Schedule(this.doses, this.nextVisit, this.firstMissedMilestone, this.ruleVersion);

  int count(DoseStatus s) => doses.where((d) => d.status == s).length;

  /// Doses that are given, or still possible for this child (progress ring).
  int get givenCount => count(DoseStatus.given);
  int get trackableCount => doses.where((d) => d.status != DoseStatus.notEligible || d.givenDate != null).length;
  double get progress => trackableCount == 0 ? 0 : givenCount / trackableCount;

  /// Every dose that can be given at the next visit, so the family makes as
  /// few trips as possible (FRS-SCH-09).
  List<DoseState> get nextVisitDoses {
    final n = nextVisit;
    if (n == null) return const [];
    return [
      for (final d in doses)
        if (d.status != DoseStatus.given &&
            d.status != DoseStatus.notEligible &&
            !(d.actionable ? n : (d.dueDate ?? n)).isAfter(n))
          d
    ];
  }
  bool get hasOverdue => doses.any((d) => d.status == DoseStatus.overdue);
  bool get hasDue => doses.any((d) => d.actionable);
  DoseState? byCode(String code) {
    for (final d in doses) {
      if (d.rule.code == code) return d;
    }
    return null;
  }
}

/// The clinical engine (FRS-SCH-01..13). It is the only place that calculates
/// dates; it reads values only from [RuleSet].
class Engine {
  static Schedule compute({
    required DateTime dob,
    required Map<String, DateTime> given,
    DateTime? asOf,
  }) {
    final now = asOf ?? today();
    final projected = <String, DateTime?>{};
    final states = <DoseState>[];
    final liveGiven = <String, DateTime>{};
    for (final r in RuleSet.doses) {
      if (r.liveInjectable && given[r.code] != null) liveGiven[r.code] = given[r.code]!;
    }

    for (final r in RuleSet.doses) {
      final g = given[r.code];
      if (g != null) {
        projected[r.code] = g;
        states.add(DoseState(r, DoseStatus.given, givenDate: g, dueDate: g));
        continue;
      }

      var earliest = addDays(dob, r.minAgeDays);
      var blocked = false;

      final prev = RuleSet.previousInSeries(r);
      if (prev != null) {
        final p = projected[prev.code];
        if (p == null) {
          blocked = true;
        } else {
          earliest = maxDate(earliest, addDays(p, r.minIntervalDays ?? 0));
        }
      }
      if (r.afterCode != null) {
        final p = projected[r.afterCode!];
        if (p == null) {
          blocked = true;
        } else {
          earliest = maxDate(earliest, addDays(p, r.afterIntervalDays ?? 0));
        }
      }
      if (blocked) {
        projected[r.code] = null;
        states.add(DoseState(r, DoseStatus.notEligible));
        continue;
      }

      if (r.liveInjectable) {
        for (final e in liveGiven.entries) {
          if (e.key == r.code) continue;
          final g2 = e.value;
          final spacingEnd = addDays(g2, RuleSet.liveSpacingDays);
          final candidate = maxDate(earliest, now);
          if (candidate.isAfter(g2) && candidate.isBefore(spacingEnd)) {
            earliest = maxDate(earliest, spacingEnd);
          }
        }
      }

      final due = maxDate(addDays(dob, r.targetDays), earliest);
      if (r.maxAgeDays != null) {
        final limit = addDays(dob, r.maxAgeDays!);
        if (now.isAfter(limit) || due.isAfter(limit)) {
          projected[r.code] = null;
          states.add(DoseState(r, DoseStatus.notEligible, dueDate: due, earliest: earliest));
          continue;
        }
      }

      if (due.isAfter(now)) {
        projected[r.code] = due;
        // Old enough by age, but held back by an interval or live spacing.
        final byAge = addDays(dob, r.targetDays);
        final status = !byAge.isAfter(now) ? DoseStatus.waiting : DoseStatus.upcoming;
        states.add(DoseState(r, status, dueDate: due, earliest: earliest));
      } else {
        // Due or overdue: catch-up assumes it is given today, so later doses
        // are pushed forward from today (FRS-SCH-08).
        projected[r.code] = now;
        final late = daysBetween(due, now);
        states.add(DoseState(r, late > RuleSet.overdueAfterDays ? DoseStatus.overdue : DoseStatus.due,
            dueDate: due, earliest: earliest));
      }
    }

    DateTime? next;
    for (final s in states) {
      DateTime? d;
      if (s.actionable) d = now;
      if (s.status == DoseStatus.upcoming || s.status == DoseStatus.waiting) d = s.dueDate;
      if (d != null && (next == null || d.isBefore(next))) next = d;
    }

    int? firstMissed;
    for (final s in states) {
      final missed = s.status == DoseStatus.overdue ||
          (s.status == DoseStatus.notEligible && s.givenDate == null && _wasDueBefore(s, dob, now));
      if (missed && (firstMissed == null || s.rule.milestone < firstMissed)) firstMissed = s.rule.milestone;
    }

    return Schedule(states, next, firstMissed, RuleSet.version);
  }

  static bool _wasDueBefore(DoseState s, DateTime dob, DateTime now) =>
      !addDays(dob, s.rule.targetDays).isAfter(now);

  /// Validates recording [code] as given on [date] (FRS-HIS-03, FRS-VIS-02).
  /// Returns an i18n error key, or null when the entry is valid.
  static String? validateGiven({
    required String code,
    required DateTime date,
    required DateTime dob,
    required Map<String, DateTime> given,
    DateTime? asOf,
  }) {
    final now = asOf ?? today();
    final r = RuleSet.byCode(code);
    if (r == null) return 'err_unknown_dose';
    if (date.isAfter(now)) return 'err_future';
    if (date.isBefore(dob)) return 'err_before_dob';
    if (date.isBefore(addDays(dob, r.minAgeDays))) return 'err_min_age';
    if (r.maxAgeDays != null && date.isAfter(addDays(dob, r.maxAgeDays!))) return 'err_max_age';
    final prev = RuleSet.previousInSeries(r);
    if (prev != null) {
      final p = given[prev.code];
      if (p == null) return 'err_prev_missing';
      if (date.isBefore(addDays(p, r.minIntervalDays ?? 0))) return 'err_interval';
    }
    if (r.afterCode != null) {
      final p = given[r.afterCode!];
      if (p == null) return 'err_prev_missing';
      if (date.isBefore(addDays(p, r.afterIntervalDays ?? 0))) return 'err_interval';
    }
    if (r.liveInjectable) {
      for (final other in RuleSet.doses.where((x) => x.liveInjectable && x.code != code)) {
        final g2 = given[other.code];
        if (g2 == null) continue;
        final gap = daysBetween(g2, date).abs();
        if (gap > 0 && gap < RuleSet.liveSpacingDays) return 'err_live_spacing';
      }
    }
    return null;
  }

  /// Milestones whose target age has been reached (for past-visit intake).
  static List<int> passedMilestones(DateTime dob, {DateTime? asOf}) {
    final now = asOf ?? today();
    final age = daysBetween(dob, now);
    return [
      for (final m in RuleSet.milestones)
        if (m.days < age) m.index
    ];
  }
}
