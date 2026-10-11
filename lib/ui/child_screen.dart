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

/// Child profile: details, schedule, visit recording, documents (FRS-SCH,
/// FRS-VIS, FRS-DOC).
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

  Future<void> _card() async {
    if (!await confirmDialog(context, t('print_card'), t('export_warning'))) return;
    final bytes = await CardPdf.build(child: _child!, facility: _facility, schedule: _schedule!, campaignDoses: _campaign);
    await Repo.logAudit('print_card', 'child', _child!.id, null);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'EPI_card_${_child!.id}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final c = _child, s = _schedule;
    if (c == null || s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final lang = Lang.current.value;
    final look = childLook(s);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, overflow: TextOverflow.ellipsis),
        actions: [
          const LangToggle(),
          PopupMenuButton<String>(
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
              PopupMenuItem(value: 'edit', child: Text(t('edit_child'))),
              PopupMenuItem(value: 'campaign', child: Text(t('campaign_dose'))),
              PopupMenuItem(value: 'void', child: Text(t('void_child'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(c.id,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Brand.blueDark, letterSpacing: 0.5)),
                ),
                if (look != null) Pill(look.$1, look.$2),
              ]),
              const SizedBox(height: 8),
              _kv(t('age'), '${ageText(c.dob, lang)} (${fmt(c.dob)})'),
              _kv(t('sex'), c.sex == 'M' ? t('male') : t('female')),
              _kv(t('guardian'), c.guardianName),
              if (c.phone != null) _kv(t('phone'), c.phone!),
              if (_facility != null) _kv(t('facility'), '${_facility!.name} · ${_facility!.district}'),
              _kv(t('next_visit'), fmt(s.nextVisit)),
              if (s.firstMissedMilestone != null)
                _kv('', tf('first_missed', {'m': lang == 'ar' ? RuleSet.milestone(s.firstMissedMilestone!).ar : RuleSet.milestone(s.firstMissedMilestone!).en})),
            ]),
          ),
          if (!c.historyDone) ...[
            const SizedBox(height: 10),
            Panel(
              color: Brand.orangeSoft,
              child: Row(children: [
                const Icon(Icons.history, color: Brand.ink),
                const SizedBox(width: 10),
                Expanded(child: Text(t('past_intake_needed'))),
                TextButton(onPressed: _intake, child: Text(t('start_intake'))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(onPressed: _recordVisit, icon: const Icon(Icons.vaccines), label: Text(t('record_visit'))),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _card, icon: const Icon(Icons.print_outlined), label: Text(t('print_card')))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _excel, icon: const Icon(Icons.table_chart_outlined), label: Text(t('export_excel')))),
          ]),
          SectionTitle(t('schedule')),
          for (final m in RuleSet.milestones) _milestoneBlock(m, s, lang),
          if (_campaign.isNotEmpty) ...[
            SectionTitle(t('campaign_dose')),
            for (final r in _campaign)
              ListTile(
                tileColor: Colors.white,
                title: Text(r.campaignName ?? ''),
                subtitle: Text(fmt(r.givenDate)),
                onLongPress: () => _voidDose(r),
              ),
          ],
          const SizedBox(height: 12),
          Text('${t('rule_version')}: ${s.ruleVersion}', style: const TextStyle(color: Brand.muted, fontSize: 12)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (k.isNotEmpty) SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Brand.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.ink))),
        ]),
      );

  Widget _milestoneBlock(Milestone m, Schedule s, String lang) {
    final items = s.doses.where((d) => d.rule.milestone == m.index).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lang == 'ar' ? m.ar : m.en, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blueDark)),
          const Divider(height: 14),
          for (final d in items) _doseRow(d, lang),
        ]),
      ),
    );
  }

  Widget _doseRow(DoseState d, String lang) {
    final look = statusLook(d.status);
    final sub = d.status == DoseStatus.given
        ? tf('given_on', {'d': fmt(d.givenDate)})
        : d.status == DoseStatus.notEligible
            ? ''
            : tf('due_on', {'d': fmt(d.dueDate)});
    final rec = _records.where((r) => r.code == d.rule.code && r.status == 'given').toList();
    return InkWell(
      onLongPress: rec.isEmpty ? null : () => _voidDose(rec.first),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.rule.label(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            ]),
          ),
          Pill(look.$1, look.$2),
        ]),
      ),
    );
  }
}
