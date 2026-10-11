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

/// Records one visit (FRS-VIS-01..04). Only doses valid on the chosen date can
/// be ticked; the others show why they are blocked.
class VisitScreen extends StatefulWidget {
  final Child child;
  const VisitScreen({super.key, required this.child});

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  DateTime _date = today();
  String _site = 'fixed';
  Map<String, DateTime> _given = {};
  Schedule? _schedule;
  final Set<String> _ticked = {};
  final Map<String, String> _reasons = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recs = await Repo.doses(widget.child.id);
    final g = Repo.givenMap(recs);
    if (!mounted) return;
    setState(() {
      _given = g;
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
    // Recheck every ticked dose with the final set before saving.
    for (final code in _ticked) {
      final r = RuleSet.byCode(code)!;
      if (_blockReason(r) != null) {
        toast(context, '${r.label(Lang.current.value)}: ${_blockReason(r)}');
        return;
      }
    }
    setState(() => _busy = true);
    await Repo.recordVisit(
      childId: widget.child.id,
      date: _date,
      site: _site,
      facilityId: app.defaultFacilityId,
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
    return Scaffold(
      appBar: AppBar(title: Text(t('record_visit')), actions: const [LangToggle()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            color: Brand.blueSoft,
            child: Text('${widget.child.name} · ${widget.child.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
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
          SectionTitle(t('doses_today')),
          if (s == null) const Center(child: CircularProgressIndicator()),
          if (s != null && open.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(t('no_doses_available'), style: const TextStyle(color: Brand.muted))),
          for (final d in open) _doseTile(d, lang),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(t('save'))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _doseTile(DoseState d, String lang) {
    final block = _ticked.contains(d.rule.code) ? null : _blockReason(d.rule);
    final ticked = _ticked.contains(d.rule.code);
    final look = statusLook(d.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(
            value: ticked,
            onChanged: block != null
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _ticked.add(d.rule.code);
                      } else {
                        _ticked.remove(d.rule.code);
                      }
                    }),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(d.rule.label(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(block ?? tf('due_on', {'d': fmt(d.dueDate)}),
                style: TextStyle(color: block != null ? Brand.warn : Brand.muted, fontSize: 12.5)),
            secondary: Pill(look.$1, look.$2),
          ),
          if (!ticked && d.actionable)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
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
