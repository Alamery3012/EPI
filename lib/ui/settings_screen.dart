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
    // Always re-ask the administrator PIN, even inside settings (FRS-SEC-10).
    final pin = await promptText(context, t('secure_wipe'), t('admin_pin'), obscure: true, digits: true);
    if (pin == null || !mounted) return;
    if (!await app.verifyAdmin(pin)) {
      if (mounted) toast(context, t('wrong_pin'));
      return;
    }
    if (!mounted) return;
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
    Widget tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing, Color color = Brand.blueDark, Key? key}) =>
        ListTile(
          key: key,
          leading: IconBadge(icon, color, size: 40),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color == Brand.bad ? Brand.bad : Brand.ink)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right, color: Brand.muted)),
          onTap: onTap,
        );
    return Scaffold(
      appBar: AppBar(title: Text(t('settings')), actions: const [LangToggle()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Panel(
            color: Brand.blueSoft,
            child: Row(children: [
              const Icon(Icons.admin_panel_settings_outlined, color: Brand.blueDark),
              const SizedBox(width: 10),
              Expanded(child: Text(t('admin_mode'), style: const TextStyle(fontWeight: FontWeight.w500))),
            ]),
          ),
          SectionTitle(t('general')),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('language'), style: const TextStyle(color: Brand.muted, fontSize: 13)),
              const SizedBox(height: 6),
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
              const SizedBox(height: 14),
              TextField(controller: _worker, decoration: InputDecoration(labelText: t('worker_name'), prefixIcon: const Icon(Icons.badge_outlined))),
            ]),
          ),
          SectionTitle(t('reminders')),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              const SizedBox(height: 12),
              FilledButton(key: const Key('settings_save'), onPressed: _saveReminders, child: Text(t('save'))),
              const SizedBox(height: 4),
              SwitchListTile(
                value: app.calendarSync,
                onChanged: _toggleCalendar,
                title: Text(t('calendar_sync'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(t('calendar_hint')),
                contentPadding: EdgeInsets.zero,
              ),
            ]),
          ),
          SectionTitle(t('facilities')),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (final f in _facilities)
                tile(Icons.local_hospital_outlined, f.name,
                    subtitle: '${f.code} · ${f.district} · ${f.governorate}',
                    trailing: f.id == app.defaultFacilityId ? const Icon(Icons.star_rounded, color: Brand.orange) : null),
              tile(Icons.add, t('add_facility'), onTap: _addFacility, key: const Key('settings_add_facility')),
            ]),
          ),
          SectionTitle(t('security')),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              tile(Icons.fact_check_outlined, t('audit_log'),
                  key: const Key('settings_audit'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen()))),
              tile(Icons.password, t('change_worker_pin'), onTap: _changeWorkerPin),
              tile(Icons.delete_forever_outlined, t('secure_wipe'), onTap: _wipe, color: Brand.bad),
            ]),
          ),
          SectionTitle(t('about')),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow(Icons.info_outline, t('app_version'), '$_version (${t('beta')})'),
              InfoRow(Icons.tablet_android_outlined, t('device_code'), app.deviceCode),
              InfoRow(Icons.rule_folder_outlined, t('rule_version'), RuleSet.version),
              InfoRow(Icons.verified_outlined, t('approval_ref'), RuleSet.approvalRef),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Brand.warnSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(t('provisional_note'), style: const TextStyle(color: Brand.warn)),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => showLicensePage(context: context, applicationVersion: _version),
                icon: const Icon(Icons.gavel_outlined),
                label: Text(t('licenses')),
              ),
            ]),
          ),
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
                leading: const Icon(Icons.history_toggle_off, color: Brand.muted),
                title: Text('${e.action} · ${e.entity}${e.entityId == null ? '' : ' · ${e.entityId}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('$ts UTC · ${e.user}${e.detail == null ? '' : '\n${e.detail}'}'),
              );
            },
          );
        },
      ),
    );
  }
}
