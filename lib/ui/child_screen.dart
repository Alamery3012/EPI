import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import '../services/card_pdf.dart';
import '../services/native.dart';
import '../services/reminders.dart';
import '../services/xlsx.dart';
import 'common.dart';
import 'intake_screen.dart';
import 'register_screen.dart';
import 'visit_screen.dart';

/// Child record: progress, next visit, schedule timeline, dose history and
/// documents (FRS-SCH, FRS-HIS-07, FRS-VIS, FRS-DOC).
class ChildScreen extends StatefulWidget {
  final String childId;
  const ChildScreen({super.key, required this.childId});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  Child? _child;
  Facility? _facility;
  Schedule? _schedule;
  List<DoseRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Repo.child(widget.childId);
    if (c == null) return;
    final recs = await Repo.doses(c.id);
    final f = await Repo.facility(c.facilityId);
    if (!mounted) return;
    setState(() {
      _child = c;
      _facility = f;
      _records = recs;
      _schedule = Engine.compute(dob: c.dob, given: Repo.givenMap(recs));
    });
  }

  List<DoseRecord> get _campaign => _records.where((r) => r.status == 'campaign').toList();

  Future<void> _afterChange() async {
    await _load();
    await Reminders.rebuild();
  }

  Future<void> _recordVisit() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => VisitScreen(child: _child!)));
    if (saved == true) {
      await _afterChange();
      if (mounted) toast(context, t('visit_saved'));
    }
  }

  Future<void> _intake() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => IntakeScreen(childId: _child!.id)));
    await _afterChange();
  }

  Future<void> _edit() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(editing: _child)));
    await _afterChange();
  }

  Future<void> _void() async {
    if (!await requireAdmin(context) || !mounted) return;
    final reason = await promptText(context, t('void_child'), t('void_reason'));
    if (reason == null) return;
    await Repo.voidChild(_child!.id, reason);
    await Reminders.rebuild();
    if (mounted) Navigator.pop(context);
  }

  /// A dose recorded in error is voided with a reason, never deleted (FRS-VIS-05).
  Future<void> _voidDose(DoseRecord rec) async {
    final reason = await promptText(context, t('void_dose'), t('void_reason'));
    if (reason == null) return;
    await Repo.voidDose(rec, reason);
    await _afterChange();
    if (mounted) toast(context, t('voided'));
  }

  Future<void> _campaignDose() async {
    final name = await promptText(context, t('campaign_dose'), t('campaign_name'));
    if (name == null || !mounted) return;
    final date = await pickDate(context, first: _child!.dob);
    if (date == null) return;
    await Repo.addCampaignDose(_child!.id, name, date);
    await _afterChange();
  }

  Future<void> _excel() async {
    if (!await confirmDialog(context, t('export_excel'), t('export_warning'))) return;
    final bytes = XlsxExport.build(
      child: _child!,
      facility: _facility,
      schedule: _schedule!,
      campaignDoses: _campaign,
      user: Repo.currentUser,
    );
    final path = await NativeBridge.saveToDownloads(
      bytes,
      'EPI_${_child!.id}_${iso(today())}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await Repo.logAudit('export_xlsx', 'child', _child!.id, path);
    if (mounted) toast(context, tf('saved_to', {'p': path}));
  }

  /// A4 card in Arabic or English, printed or shared as PDF (FRS-DOC-04, 07, 08, 09).
  Future<void> _card() async {
    final choice = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => _CardSheet(initialLang: Lang.current.value),
    );
    if (choice == null || !mounted) return;
    final (lang, action) = choice;
    if (!await confirmDialog(context, t('print_card'), t('export_warning'))) return;
    final bytes = await CardPdf.build(
      child: _child!,
      facility: _facility,
      schedule: _schedule!,
      campaignDoses: _campaign,
      language: lang,
    );
    final name = 'EPI_card_${_child!.id}.pdf';
    if (action == 'share') {
      await Repo.logAudit('share_card', 'child', _child!.id, lang);
      await Printing.sharePdf(bytes: bytes, filename: name);
    } else {
      await Repo.logAudit('print_card', 'child', _child!.id, lang);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    }
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final c = _child, s = _schedule;
    if (c == null || s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final lang = Lang.current.value;
    final given = _records.where((r) => r.status == 'given').toList()
      ..sort((a, b) => (b.givenDate ?? DateTime(0)).compareTo(a.givenDate ?? DateTime(0)));
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(c, s, lang),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _nextVisitCard(s, lang),
              if (!c.historyDone) ...[
                const SizedBox(height: 12),
                Panel(
                  color: Brand.orangeSoft,
                  child: Row(children: [
                    const IconBadge(Icons.history, Brand.orange, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t('past_intake_needed'), style: const TextStyle(fontWeight: FontWeight.w500))),
                    TextButton(key: const Key('child_start_intake'), onPressed: _intake, child: Text(t('start_intake'))),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('child_record_visit'),
                onPressed: _recordVisit,
                icon: const Icon(Icons.vaccines),
                label: Text(t('record_visit')),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('child_card'),
                    onPressed: _card,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(t('card_short')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('child_excel'),
                    onPressed: _excel,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text(t('excel_short')),
                  ),
                ),
              ]),
              SectionTitle(t('schedule'), trailing: Text('${s.givenCount}/${s.trackableCount}', style: const TextStyle(color: Brand.muted))),
              _legend(),
              const SizedBox(height: 10),
              for (final m in RuleSet.milestones) _milestone(m, s, lang, m.index == RuleSet.milestones.last.index),
              SectionTitle(t('child_info')),
              Panel(
                child: Column(children: [
                  InfoRow(Icons.person_outline, t('guardian'), '${c.guardianName} · ${t('rel_${c.guardianRelation ?? 'other'}')}'),
                  if (c.phone != null) InfoRow(Icons.phone_outlined, t('phone'), c.phone!),
                  if (_facility != null) InfoRow(Icons.local_hospital_outlined, t('facility'), '${_facility!.name} · ${_facility!.district}'),
                  if ((c.area ?? '').isNotEmpty) InfoRow(Icons.place_outlined, t('area'), c.area!),
                  if (c.birthWeight != null) InfoRow(Icons.monitor_weight_outlined, t('birth_weight'), '${c.birthWeight} g'),
                  if ((c.nameLatin ?? '').isNotEmpty) InfoRow(Icons.translate, t('child_name_latin'), c.nameLatin!),
                  InfoRow(Icons.history_edu_outlined, t('registered_by'), '${c.createdBy} · ${c.createdAt.substring(0, 10)}'),
                ]),
              ),
              SectionTitle(t('dose_history')),
              if (given.isEmpty)
                Panel(child: Text(t('no_doses_yet'), style: const TextStyle(color: Brand.muted)))
              else
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    for (var i = 0; i < given.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      _historyRow(given[i], lang),
                    ],
                  ]),
                ),
              if (_campaign.isNotEmpty) ...[
                SectionTitle(t('campaign_dose')),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [for (final r in _campaign) _historyRow(r, lang, campaign: true)]),
                ),
              ],
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.rule_folder_outlined, size: 15, color: Brand.muted),
                const SizedBox(width: 6),
                Text('${t('rule_version')}: ${s.ruleVersion}', style: const TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _header(Child c, Schedule s, String lang) => GradientHeader(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const BackButton(color: Colors.white),
            const Spacer(),
            const LangToggle(light: true),
            PopupMenuButton<String>(
              key: const Key('child_menu'),
              iconColor: Colors.white,
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit();
                  case 'campaign':
                    _campaignDose();
                  case 'void':
                    _void();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t('edit_child')))),
                PopupMenuItem(value: 'campaign', child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(t('campaign_dose')))),
                PopupMenuItem(
                    value: 'void',
                    child: ListTile(
                        leading: const Icon(Icons.block, color: Brand.bad),
                        title: Text(t('void_child'), style: const TextStyle(color: Brand.bad)))),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text(Initials.of(c.name),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.sex == 'M' ? Brand.blue : Brand.orange)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 4),
                  Text(c.id,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text('${c.sex == 'M' ? t('male') : t('female')} · ${ageText(c.dob, lang)} · ${fmt(c.dob)}',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              ProgressRing(
                value: s.progress,
                size: 74,
                stroke: 7,
                color: Colors.white,
                track: Colors.white.withOpacity(0.25),
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${(s.progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, height: 1.1)),
                  Text(t('done_short'), style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                ]),
              ),
            ]),
          ),
        ]),
      );

  Widget _nextVisitCard(Schedule s, String lang) {
    final next = s.nextVisit;
    final doses = s.nextVisitDoses;
    final overdue = s.hasOverdue;
    final color = overdue ? Brand.bad : (s.hasDue ? Brand.blueDark : Brand.good);
    if (next == null) {
      return Panel(
        child: Row(children: [
          const IconBadge(Icons.verified, Brand.good),
          const SizedBox(width: 12),
          Expanded(child: Text(t('schedule_complete'), style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
    }
    final days = daysBetween(today(), next);
    final when = days <= 0 ? t('today') : tf('in_days', {'n': days});
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(overdue ? Icons.warning_amber_rounded : Icons.event_available, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('next_visit'), style: const TextStyle(color: Brand.muted, fontSize: 13)),
              Text('${fmt(next)} · $when', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: color)),
            ]),
          ),
          if (overdue) statusPill(DoseStatus.overdue) else if (s.hasDue) statusPill(DoseStatus.due),
        ]),
        if (doses.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in doses)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.vaccines_outlined, size: 15, color: statusLook(d.status).$2),
                  const SizedBox(width: 5),
                  Text(d.rule.label(lang), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
          ]),
        ],
        if (s.firstMissedMilestone != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.flag_outlined, size: 16, color: Brand.bad),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tf('first_missed', {
                  'm': lang == 'ar' ? RuleSet.milestone(s.firstMissedMilestone!).ar : RuleSet.milestone(s.firstMissedMilestone!).en
                }),
                style: const TextStyle(color: Brand.bad, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _legend() => Wrap(spacing: 12, runSpacing: 6, children: [
        for (final st in [DoseStatus.given, DoseStatus.due, DoseStatus.overdue, DoseStatus.upcoming, DoseStatus.waiting])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(statusIcon(st), size: 14, color: statusLook(st).$2),
            const SizedBox(width: 4),
            Text(statusLook(st).$1, style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ]),
      ]);

  /// One milestone of the vertical timeline.
  Widget _milestone(Milestone m, Schedule s, String lang, bool last) {
    final items = s.doses.where((d) => d.rule.milestone == m.index).toList();
    final DoseStatus agg = items.every((d) => d.status == DoseStatus.given)
        ? DoseStatus.given
        : items.any((d) => d.status == DoseStatus.overdue)
            ? DoseStatus.overdue
            : items.any((d) => d.status == DoseStatus.due)
                ? DoseStatus.due
                : items.any((d) => d.status == DoseStatus.waiting)
                    ? DoseStatus.waiting
                    : items.every((d) => d.status == DoseStatus.notEligible || d.status == DoseStatus.given)
                        ? DoseStatus.notEligible
                        : DoseStatus.upcoming;
    final color = statusLook(agg).$2;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            const SizedBox(height: 14),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: agg == DoseStatus.given ? color : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
              ),
              child: Icon(agg == DoseStatus.given ? Icons.check : statusIcon(agg),
                  size: 16, color: agg == DoseStatus.given ? Colors.white : color),
            ),
            if (!last) Expanded(child: Container(width: 2.5, margin: const EdgeInsets.only(top: 4), color: Brand.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(lang == 'ar' ? m.ar : m.en,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Brand.ink)),
                  ),
                  Text('${items.where((d) => d.status == DoseStatus.given).length}/${items.length}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                for (final d in items) _doseRow(d, lang),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _doseRow(DoseState d, String lang) {
    final sub = switch (d.status) {
      DoseStatus.given => tf('given_on', {'d': fmt(d.givenDate)}),
      DoseStatus.notEligible => t('noelig_hint'),
      DoseStatus.waiting => tf('waiting_until', {'d': fmt(d.dueDate)}),
      _ => tf('due_on', {'d': fmt(d.dueDate)}),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(statusIcon(d.status), size: 20, color: statusLook(d.status).$2),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.rule.label(lang), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            Text(sub, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
          ]),
        ),
        statusPill(d.status),
      ]),
    );
  }

  Widget _historyRow(DoseRecord r, String lang, {bool campaign = false}) {
    final rule = RuleSet.byCode(r.code);
    final title = campaign ? (r.campaignName ?? '') : (rule?.label(lang) ?? r.code);
    final src = switch (r.source) {
      'card' => t('src_card'),
      'caregiver' => t('src_caregiver'),
      'campaign' => t('campaign_dose'),
      _ => t('src_visit'),
    };
    return ListTile(
      leading: IconBadge(campaign ? Icons.campaign_outlined : Icons.vaccines_outlined, campaign ? Brand.orange : Brand.good, size: 38),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${fmt(r.givenDate)} · $src · ${r.createdBy}', style: const TextStyle(fontSize: 12.5)),
      trailing: IconButton(
        tooltip: t('void_dose'),
        icon: const Icon(Icons.remove_circle_outline, color: Brand.muted),
        onPressed: () => _voidDose(r),
      ),
    );
  }
}

/// Bottom sheet: card language and print or share.
class _CardSheet extends StatefulWidget {
  final String initialLang;
  const _CardSheet({required this.initialLang});

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  late String _lang = widget.initialLang;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('print_card'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('card_sheet_hint'), style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(t('arabic'))),
                ButtonSegment(value: 'en', label: Text(t('english'))),
              ],
              selected: {_lang},
              onSelectionChanged: (v) => setState(() => _lang = v.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('card_print'),
              onPressed: () => Navigator.pop(context, (_lang, 'print')),
              icon: const Icon(Icons.print_outlined),
              label: Text(t('print_or_pdf')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('card_share'),
              onPressed: () => Navigator.pop(context, (_lang, 'share')),
              icon: const Icon(Icons.share_outlined),
              label: Text(t('share_pdf')),
            ),
          ]),
        ),
      );
}
