import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/rules.dart';
import '../services/native.dart';
import '../services/reminders.dart';
import 'common.dart';

/// Administrator settings (FRS-SET-03, 04, FRS-REM-01, 08, FRS-SEC-09, 10).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _before = TextEditingController(text: '${app.offsetBefore}');
  late final _after = TextEditingController(text: '${app.offsetAfter}');
  late final _worker = TextEditingController(text: app.workerName);
  List<Facility> _facilities = [];
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await Repo.facilities();
    String v = '';
    try {
      v = await NativeBridge.appVersion();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _facilities = f;
      _version = v;
    });
  }

  Future<void> _saveReminders() async {
    final b = int.tryParse(_before.text) ?? 3;
    final a = int.tryParse(_after.text) ?? 3;
    await app.updateSettings(before: b.clamp(0, 30).toInt(), after: a.clamp(0, 30).toInt(), worker: _worker.text.trim());
    await Reminders.rebuild();
    if (mounted) toast(context, t('saved'));
  }

  Future<void> _toggleCalendar(bool on) async {
    if (on) {
      final ok = await NativeBridge.requestCalendarPermission();
      if (!ok) {
        if (mounted) toast(context, t('calendar_denied'));
        return;
      }
    }
    await app.updateSettings(calendar: on);
    await Reminders.rebuild();
    setState(() {});
  }

  Future<void> _addFacility() async {
    final code = TextEditingController(), name = TextEditingController(), gov = TextEditingController(), dist = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('add_facility')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: t('facility_name'))),
            const SizedBox(height: 8),
            TextField(controller: code, decoration: InputDecoration(labelText: t('facility_code'))),
            const SizedBox(height: 8),
            TextField(controller: gov, decoration: InputDecoration(labelText: t('governorate'))),
            const SizedBox(height: 8),
            TextField(controller: dist, decoration: InputDecoration(labelText: t('district'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('add'))),
        ],
      ),
    );
    if (ok != true) return;
    if ([code, name, gov, dist].any((x) => x.text.trim().isEmpty)) {
      if (mounted) toast(context, t('required'));
      return;
    }
    try {
      await Repo.addFacility(code.text, name.text, gov.text, dist.text);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    _load();
  }

  Future<void> _changeWorkerPin() async {
    final pin = await promptText(context, t('change_worker_pin'), t('worker_pin'), obscure: true, digits: true);
    if (pin == null) return;
    if (pinRule(pin) != null) {
      if (mounted) toast(context, t('pin_rule'));
      return;
    }
    await app.setPin(Role.worker, pin);
    await Repo.logAudit('pin_change', 'settings', 'worker', null);
    if (mounted) toast(context, t('saved'));
  }

  Future<void> _wipe() async {
    final typed = await promptText(context, t('secure_wipe'), t('wipe_warning'));
    if (typed == null || typed.toUpperCase() != app.deviceCode) return;
    if (!mounted) return;
    if (!await confirmDialog(context, t('secure_wipe'), t('wipe_warning'))) return;
    await NativeBridge.setReminders([]);
    await app.wipe();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('settings')), actions: const [LangToggle()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(t('language')),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'ar', label: Text(t('arabic'))),
              ButtonSegment(value: 'en', label: Text(t('english'))),
            ],
            selected: {Lang.current.value},
            onSelectionChanged: (s) async {
              await app.updateSettings(lang: s.first);
              setState(() {});
            },
          ),
          SectionTitle(t('worker_name')),
          TextField(controller: _worker, decoration: InputDecoration(labelText: t('worker_name'))),
          SectionTitle(t('reminders')),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _before,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: t('offset_before')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _after,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: t('offset_after')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          FilledButton(onPressed: _saveReminders, child: Text(t('save'))),
          const SizedBox(height: 6),
          SwitchListTile(
            value: app.calendarSync,
            onChanged: _toggleCalendar,
            title: Text(t('calendar_sync')),
            contentPadding: EdgeInsets.zero,
          ),
          SectionTitle(t('facilities')),
          for (final f in _facilities)
            Card(
              child: ListTile(
                title: Text(f.name),
                subtitle: Text('${f.code} · ${f.district} · ${f.governorate}'),
                trailing: f.id == app.defaultFacilityId ? const Icon(Icons.star, color: Brand.orange) : null,
              ),
            ),
          OutlinedButton.icon(onPressed: _addFacility, icon: const Icon(Icons.add), label: Text(t('add_facility'))),
          SectionTitle(t('audit_log')),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(t('audit_log')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _changeWorkerPin, icon: const Icon(Icons.password), label: Text(t('change_worker_pin'))),
          SectionTitle(t('about')),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('app_version')}: $_version (${t('beta')})'),
              Text('${t('device_code')}: ${app.deviceCode}'),
              Text('${t('rule_version')}: ${RuleSet.version}'),
              Text('${t('approval_ref')}: ${RuleSet.approvalRef}'),
              const SizedBox(height: 8),
              Text(t('provisional_note'), style: const TextStyle(color: Brand.warn)),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => showLicensePage(context: context, applicationVersion: _version),
                icon: const Icon(Icons.gavel_outlined),
                label: Text(t('licenses')),
              ),
            ]),
          ),
          SectionTitle(t('secure_wipe')),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Brand.bad, side: const BorderSide(color: Brand.bad)),
            onPressed: _wipe,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(t('secure_wipe')),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Read-only audit log, newest first (FRS-SEC-09).
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('audit_log'))),
      body: FutureBuilder<List<AuditEntry>>(
        future: Repo.auditLog(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = list[i];
              final ts = e.ts.length >= 16 ? e.ts.substring(0, 16).replaceFirst('T', ' ') : e.ts;
              return ListTile(
                dense: true,
                title: Text('${e.action} · ${e.entity}${e.entityId == null ? '' : ' · ${e.entityId}'}'),
                subtitle: Text('$ts UTC · ${e.user}${e.detail == null ? '' : '\n${e.detail}'}'),
              );
            },
          );
        },
      ),
    );
  }
}
