import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import 'common.dart';

/// Guided past-visit intake, milestone by milestone in date order
/// (FRS-HIS-01..07).
class IntakeScreen extends StatefulWidget {
  final String childId;
  const IntakeScreen({super.key, required this.childId});

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _Answer {
  String status = 'unknown'; // given | not_given | unknown
  DateTime? date;
  String? error;
}

class _IntakeScreenState extends State<IntakeScreen> {
  Child? _child;
  List<int> _milestones = [];
  int _step = 0;
  String _source = 'card';
  final Map<String, _Answer> _answers = {};
  bool _busy = false;
  Map<String, DateTime> _alreadyGiven = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Repo.child(widget.childId);
    if (c == null || !mounted) return;
    // Doses already recorded (e.g. at a visit) are shown as given and are not
    // written again.
    final existing = Repo.givenMap(await Repo.doses(c.id));
    if (!mounted) return;
    setState(() {
      _child = c;
      _alreadyGiven = existing;
      _milestones = Engine.passedMilestones(c.dob);
      for (final r in RuleSet.doses) {
        if (!_milestones.contains(r.milestone)) continue;
        final a = _Answer();
        final g = existing[r.code];
        if (g != null) {
          a.status = 'given';
          a.date = g;
        }
        _answers[r.code] = a;
      }
    });
  }

  List<DoseRule> _rulesFor(int milestone) => RuleSet.doses.where((r) => r.milestone == milestone).toList();

  /// Given dates of every milestone up to and including the current one.
  Map<String, DateTime> _givenSoFar({required int upTo}) {
    final m = <String, DateTime>{};
    for (final r in RuleSet.doses) {
      if (r.milestone > upTo) continue;
      final a = _answers[r.code];
      if (a != null && a.status == 'given' && a.date != null) m[r.code] = a.date!;
    }
    return m;
  }

  bool _validateStep() {
    final c = _child!;
    final ms = _milestones[_step];
    var ok = true;
    final given = _givenSoFar(upTo: ms);
    for (final r in _rulesFor(ms)) {
      final a = _answers[r.code]!;
      a.error = null;
      if (a.status != 'given') continue;
      if (a.date == null) {
        a.error = t('err_need_date');
        ok = false;
        continue;
      }
      final others = Map<String, DateTime>.from(given)..remove(r.code);
      final e = Engine.validateGiven(code: r.code, date: a.date!, dob: c.dob, given: others);
      if (e != null) {
        a.error = t(e);
        ok = false;
      }
    }
    setState(() {});
    return ok;
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    if (_step < _milestones.length - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    final entries = [
      for (final e in _answers.entries)
        if (!_alreadyGiven.containsKey(e.key))
          HistoryEntry(e.key, e.value.status, e.value.status == 'given' ? e.value.date : null),
    ];
    await Repo.recordHistory(widget.childId, entries, _source == 'card' ? 'card' : 'caregiver');
    final sch = Engine.compute(dob: _child!.dob, given: _givenSoFar(upTo: 99));
    if (!mounted) return;
    final missed = sch.firstMissedMilestone;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('intake_title')),
        content: Text([
          t('intake_done'),
          if (missed != null) tf('first_missed', {'m': Lang.isAr ? RuleSet.milestone(missed).ar : RuleSet.milestone(missed).en}),
        ].join('\n\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('close')))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final c = _child;
    if (c == null || _milestones.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(t('intake_title'))), body: const Center(child: CircularProgressIndicator()));
    }
    final ms = RuleSet.milestone(_milestones[_step]);
    final lang = Lang.current.value;
    return Scaffold(
      appBar: AppBar(title: Text(t('intake_title')), actions: const [LangToggle()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            color: Brand.blueSoft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${c.id} · ${fmt(c.dob)}', style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 8),
              Text(t('intake_intro')),
            ]),
          ),
          const SizedBox(height: 12),
          if (_step == 0) ...[
            Text(t('intake_source'), style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'card', label: Text(t('src_card'))),
                ButtonSegment(value: 'caregiver', label: Text(t('src_caregiver'))),
              ],
              selected: {_source},
              onSelectionChanged: (s) => setState(() => _source = s.first),
            ),
          ],
          LinearProgressIndicator(
            value: (_step + 1) / _milestones.length,
            backgroundColor: Brand.line,
            color: Brand.blue,
          ),
          SectionTitle('${lang == 'ar' ? ms.ar : ms.en} · ${tf('milestone_of', {'i': _step + 1, 'n': _milestones.length})}'),
          for (final r in _rulesFor(ms.index)) _doseCard(r, c),
          const SizedBox(height: 16),
          Row(children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: Text(t('back'))),
              ),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _next,
                child: Text(_step == _milestones.length - 1 ? t('finish') : t('next')),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _doseCard(DoseRule r, Child c) {
    final a = _answers[r.code]!;
    final locked = _alreadyGiven.containsKey(r.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.label(Lang.current.value), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'given', label: Text(t('h_given'))),
              ButtonSegment(value: 'not_given', label: Text(t('h_not_given'))),
              ButtonSegment(value: 'unknown', label: Text(t('h_unknown'))),
            ],
            selected: {a.status},
            onSelectionChanged: locked
                ? null
                : (s) => setState(() {
                      a.status = s.first;
                      a.error = null;
                    }),
          ),
          if (a.status == 'given') ...[
            const SizedBox(height: 10),
            DateField(
              label: t('given_date'),
              value: a.date,
              error: a.error,
              onTap: () async {
                if (locked) return;
                final d = await pickDate(context, initial: a.date ?? addDays(c.dob, r.targetDays), first: c.dob);
                if (d != null) setState(() => a.date = d);
              },
            ),
          ],
        ]),
      ),
    );
  }
}
