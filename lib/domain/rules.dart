/// Clinical rule tables.
///
/// Milestones and contents follow TOR Section 7 exactly. Minimum ages,
/// intervals, age limits and spacing below are PROVISIONAL placeholders
/// (FRS Section 10, values "TBC") until YFCA/MoPHP issue the approved rule
/// document. They live here, separate from the engine, so the approved
/// values replace them without touching any logic (FRS-SCH-11, 12).
library;

class Milestone {
  final int index;
  final String ar;
  final String en;
  final int days;
  const Milestone(this.index, this.ar, this.en, this.days);
}

class DoseRule {
  final String code;
  final String series;
  final int doseNo;
  final String ar;
  final String en;
  final int milestone;
  final int targetDays;
  final int minAgeDays;
  final int? maxAgeDays;
  final int? minIntervalDays; // after the previous dose of the same series
  final bool liveInjectable;
  final String? afterCode; // a dose of another series that must come first
  final int? afterIntervalDays;

  const DoseRule({
    required this.code,
    required this.series,
    required this.doseNo,
    required this.ar,
    required this.en,
    required this.milestone,
    required this.targetDays,
    required this.minAgeDays,
    this.maxAgeDays,
    this.minIntervalDays,
    this.liveInjectable = false,
    this.afterCode,
    this.afterIntervalDays,
  });

  String label(String lang) => lang == 'ar' ? ar : en;
}

class RuleSet {
  static const String version = '0.1-provisional';
  static const String approvalRef =
      'PROVISIONAL - TOR §7 baseline; limits pending YFCA approval';

  /// Live injectable vaccines not given on the same day must be this far apart.
  static const int liveSpacingDays = 28;

  /// Grace period after the due date before a dose counts as overdue.
  static const int overdueAfterDays = 7;

  /// Children older than this are outside the routine schedule (FRS-REG-03).
  static const int maxChildAgeDays = 1825;

  static const List<Milestone> milestones = [
    Milestone(0, 'عند الولادة', 'Birth', 0),
    Milestone(1, '6 أسابيع', '6 weeks', 42),
    Milestone(2, '10 أسابيع', '10 weeks', 70),
    Milestone(3, '14 أسبوعًا', '14 weeks', 98),
    Milestone(4, '9 أشهر', '9 months', 270),
    Milestone(5, '18 شهرًا', '18 months', 540),
  ];

  static const List<DoseRule> doses = [
    // Birth (0-28 days)
    DoseRule(code: 'BCG', series: 'BCG', doseNo: 1, ar: 'بي سي جي', en: 'BCG', milestone: 0, targetDays: 0, minAgeDays: 0, maxAgeDays: 365, liveInjectable: true),
    DoseRule(code: 'OPV0', series: 'OPV0', doseNo: 1, ar: 'شلل فموي - صفرية', en: 'OPV-0', milestone: 0, targetDays: 0, minAgeDays: 0, maxAgeDays: 28),
    DoseRule(code: 'HEPB0', series: 'HEPB0', doseNo: 1, ar: 'التهاب الكبد ب - عند الولادة', en: 'HepB-0', milestone: 0, targetDays: 0, minAgeDays: 0, maxAgeDays: 28),
    // 6 weeks
    DoseRule(code: 'PENTA1', series: 'PENTA', doseNo: 1, ar: 'الخماسي 1', en: 'Penta-1', milestone: 1, targetDays: 42, minAgeDays: 42, maxAgeDays: 1825),
    DoseRule(code: 'OPV1', series: 'OPV', doseNo: 1, ar: 'شلل فموي 1', en: 'OPV-1', milestone: 1, targetDays: 42, minAgeDays: 42, maxAgeDays: 1825),
    DoseRule(code: 'ROTA1', series: 'ROTA', doseNo: 1, ar: 'الروتا 1', en: 'Rota-1', milestone: 1, targetDays: 42, minAgeDays: 42, maxAgeDays: 105),
    DoseRule(code: 'PCV1', series: 'PCV', doseNo: 1, ar: 'المكورات الرئوية 1', en: 'PCV-1', milestone: 1, targetDays: 42, minAgeDays: 42, maxAgeDays: 1825),
    // 10 weeks
    DoseRule(code: 'PENTA2', series: 'PENTA', doseNo: 2, ar: 'الخماسي 2', en: 'Penta-2', milestone: 2, targetDays: 70, minAgeDays: 70, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'OPV2', series: 'OPV', doseNo: 2, ar: 'شلل فموي 2', en: 'OPV-2', milestone: 2, targetDays: 70, minAgeDays: 70, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'ROTA2', series: 'ROTA', doseNo: 2, ar: 'الروتا 2', en: 'Rota-2', milestone: 2, targetDays: 70, minAgeDays: 70, maxAgeDays: 240, minIntervalDays: 28),
    // 14 weeks
    DoseRule(code: 'PENTA3', series: 'PENTA', doseNo: 3, ar: 'الخماسي 3', en: 'Penta-3', milestone: 3, targetDays: 98, minAgeDays: 98, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'OPV3', series: 'OPV', doseNo: 3, ar: 'شلل فموي 3', en: 'OPV-3', milestone: 3, targetDays: 98, minAgeDays: 98, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'PCV2', series: 'PCV', doseNo: 2, ar: 'المكورات الرئوية 2', en: 'PCV-2', milestone: 3, targetDays: 98, minAgeDays: 98, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'IPV1', series: 'IPV', doseNo: 1, ar: 'شلل حقن 1', en: 'IPV-1', milestone: 3, targetDays: 98, minAgeDays: 98, maxAgeDays: 1825),
    // 9 months
    DoseRule(code: 'MR1', series: 'MR', doseNo: 1, ar: 'الحصبة والحصبة الألمانية 1', en: 'MR-1', milestone: 4, targetDays: 270, minAgeDays: 270, maxAgeDays: 1825, liveInjectable: true),
    DoseRule(code: 'PCV3', series: 'PCV', doseNo: 3, ar: 'المكورات الرئوية 3', en: 'PCV-3', milestone: 4, targetDays: 270, minAgeDays: 270, maxAgeDays: 1825, minIntervalDays: 28),
    DoseRule(code: 'VITA1', series: 'VITA', doseNo: 1, ar: 'فيتامين أ - الجرعة 1', en: 'Vitamin A dose 1', milestone: 4, targetDays: 270, minAgeDays: 270, maxAgeDays: 1825),
    // 18 months
    DoseRule(code: 'MR2', series: 'MR', doseNo: 2, ar: 'الحصبة والحصبة الألمانية 2', en: 'MR-2', milestone: 5, targetDays: 540, minAgeDays: 540, maxAgeDays: 1825, minIntervalDays: 28, liveInjectable: true),
    DoseRule(code: 'DTPB', series: 'DTPB', doseNo: 1, ar: 'الثلاثي - جرعة منشطة', en: 'DTP booster', milestone: 5, targetDays: 540, minAgeDays: 540, maxAgeDays: 1825, afterCode: 'PENTA3', afterIntervalDays: 180),
    DoseRule(code: 'OPVB', series: 'OPVB', doseNo: 1, ar: 'شلل فموي - جرعة منشطة', en: 'OPV booster', milestone: 5, targetDays: 540, minAgeDays: 540, maxAgeDays: 1825, afterCode: 'OPV3', afterIntervalDays: 180),
    DoseRule(code: 'VITA2', series: 'VITA', doseNo: 2, ar: 'فيتامين أ - الجرعة 2', en: 'Vitamin A dose 2', milestone: 5, targetDays: 540, minAgeDays: 540, maxAgeDays: 1825, minIntervalDays: 180),
  ];

  static DoseRule? byCode(String code) {
    for (final r in doses) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// The previous dose of the same series, if any.
  static DoseRule? previousInSeries(DoseRule rule) {
    for (final r in doses) {
      if (r.series == rule.series && r.doseNo == rule.doseNo - 1) return r;
    }
    return null;
  }

  static Milestone milestone(int index) => milestones[index];
}
