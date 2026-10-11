import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import 'common.dart';

/// Records one visit: date, site, facility and doses (FRS-VIS-01..04). Only
/// doses valid on the chosen date can be selected; the others show why.
class VisitScreen extends StatefulWidget {
  final Child child;
  const VisitScreen({super.key, required this.child});

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  DateTime _date = today();
  String _site = 'fixed';
  int? _facilityId;
  List<Facility> _facilities = [];
  Map<String, DateTime> _given = {};
  Schedule? _schedule;
  final Set<String> _ticked = {};
  final Map<String, String> _reasons = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _facilityId = app.defaultFacilityId ?? widget.child.facilityId;
    _load();
  }

  Future<void> _load() async {
    final recs = await Repo.doses(widget.child.id);
    final fac = await Repo.facilities();
    final g = Repo.givenMap(recs);
    if (!mounted) return;
    setState(() {
      _given = g;
      _facilities = fac;
      if (_facilityId != null && !fac.any((f) => f.id == _facilityId)) _facilityId = fac.isEmpty ? null : fac.first.id;
      _schedule = Engine.compute(dob: widget.child.dob, given: g, asOf: _date);
    });
  }

  String? _blockReason(DoseRule r) {
    // Validate against doses given before this visit plus the ones ticked now,
    // so same-day live vaccines and series order are both respected.
    final others = Map<String, DateTime>.from(_given);
    for (final code in _ticked) {
      if (code != r.code) others[code] = _date;
    }
    final e = Engine.validateGiven(code: r.code, date: _date, dob: widget.child.dob, given: others, asOf: today());
    return e == null ? null : t(e);
  }

  Future<void> _save() async {
    final reasons = Map<String, String>.from(_reasons)..removeWhere((k, _) => _ticked.contains(k));
    if (_ticked.isEmpty && reasons.isEmpty) {
      toast(context, t('select_one'));
      return;
    }
    for (final code in _ticked) {
      final r = RuleSet.byCode(code)!;
      final b = _blockReason(r);
      if (b != null) {
        toast(context, '${r.label(Lang.current.value)}: $b');
        return;
      }
    }
    setState(() => _busy = true);
    await Repo.recordVisit(
      childId: widget.child.id,
      date: _date,
      site: _site,
      facilityId: _facilityId,
      given: _ticked.toList(),
      notGivenReasons: reasons,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final s = _schedule;
    final lang = Lang.current.value;
    final open = s == null ? <DoseState>[] : s.doses.where((d) => d.status != DoseStatus.given && d.status != DoseStatus.notEligible).toList();
    final ready = open.where((d) => _blockReason(d.rule) == null || _ticked.contains(d.rule.code)).toList();
    final later = open.where((d) => !ready.contains(d)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(t('record_visit')), actions: const [LangToggle()]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x140B3954), blurRadius: 16, offset: Offset(0, -4))]),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tf('n_selected', {'n': _ticked.length}), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(fmt(_date), style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              ]),
            ),
            SizedBox(
              width: 170,
              child: FilledButton.icon(
                key: const Key('visit_save'),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(t('save_visit')),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Panel(
            child: Row(children: [
              Initials(widget.child.name, color: widget.child.sex == 'M' ? Brand.blue : Brand.orange, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.child.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  Text('${widget.child.id} · ${ageText(widget.child.dob, lang, at: _date)}',
                      style: const TextStyle(color: Brand.muted, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(children: [
              DateField(
                label: t('visit_date'),
                value: _date,
                onTap: () async {
                  final d = await pickDate(context, initial: _date, first: widget.child.dob);
                  if (d != null) {
                    setState(() {
                      _date = d;
                      _ticked.clear();
                    });
                    _load();
                  }
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'fixed', label: Text(t('site_fixed')), icon: const Icon(Icons.local_hospital_outlined)),
                  ButtonSegment(value: 'outreach', label: Text(t('site_outreach')), icon: const Icon(Icons.directions_walk)),
                ],
                selected: {_site},
                onSelectionChanged: (v) => setState(() => _site = v.first),
              ),
              if (_facilities.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _facilityId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('facility'), prefixIcon: const Icon(Icons.local_hospital_outlined)),
                  items: [for (final f in _facilities) DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _facilityId = v),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.badge_outlined, size: 18, color: Brand.muted),
                const SizedBox(width: 8),
                Text('${t('health_worker')}: ${Repo.currentUser}', style: const TextStyle(color: Brand.muted)),
              ]),
            ]),
          ),
          SectionTitle(t('doses_today')),
          if (s == null) const Center(child: CircularProgressIndicator()),
          if (s != null && ready.isEmpty)
            Panel(
              child: Row(children: [
                const IconBadge(Icons.event_busy, Brand.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(t('no_doses_available'), style: const TextStyle(color: Brand.muted))),
              ]),
            ),
          for (final d in ready) _doseTile(d, lang),
          if (later.isNotEmpty) ...[
            SectionTitle(t('not_yet_today')),
            for (final d in later) _doseTile(d, lang),
          ],
        ],
      ),
    );
  }

  Widget _doseTile(DoseState d, String lang) {
    final ticked = _ticked.contains(d.rule.code);
    final block = ticked ? null : _blockReason(d.rule);
    final color = statusLook(d.status).$2;
    void toggle() => setState(() => ticked ? _ticked.remove(d.rule.code) : _ticked.add(d.rule.code));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: ticked ? Brand.goodSoft : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ticked ? Brand.good : Colors.transparent, width: 2),
          boxShadow: Brand.cardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            key: Key('dose_${d.rule.code}'),
            borderRadius: BorderRadius.circular(18),
            onTap: block != null ? null : toggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ticked ? Brand.good : (block != null ? Brand.surface : Color.alphaBlend(color.withOpacity(0.12), Colors.white)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(ticked ? Icons.check : Icons.vaccines_outlined,
                      color: ticked ? Colors.white : (block != null ? Brand.muted : color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.rule.label(lang),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: block != null ? Brand.muted : Brand.ink)),
                    const SizedBox(height: 2),
                    Text(block ?? tf('due_on', {'d': fmt(d.dueDate)}),
                        style: TextStyle(color: block != null ? Brand.warn : Brand.muted, fontSize: 12.5)),
                  ]),
                ),
                statusPill(d.status),
              ]),
            ),
          ),
          if (!ticked && d.actionable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: DropdownButtonFormField<String>(
                value: _reasons[d.rule.code],
                isExpanded: true,
                decoration: InputDecoration(labelText: t('not_given_reason'), isDense: true),
                items: [
                  for (final k in ['r_sick', 'r_stock', 'r_refused', 'r_other'])
                    DropdownMenuItem(value: k.substring(2), child: Text(t(k))),
                ],
                onChanged: (v) => setState(() {
                  if (v == null) {
                    _reasons.remove(d.rule.code);
                  } else {
                    _reasons[d.rule.code] = v;
                  }
                }),
              ),
            ),
        ]),
      ),
    );
  }
}
