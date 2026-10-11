import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/text_match.dart';
import '../services/native.dart';
import 'child_screen.dart';
import 'common.dart';
import 'register_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, due, overdue, week }

/// Registry list with search, filters and the due/overdue lists that work even
/// when notifications are off (FRS-REG-08, 09, FRS-REM-06, 07).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<ChildSummary> _all = [];
  _Filter _filter = _Filter.all;
  bool _loading = true;
  bool _notifOk = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await Repo.summaries();
    bool ok = true;
    try {
      ok = await NativeBridge.notificationsEnabled();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = list;
      _notifOk = ok;
      _loading = false;
    });
  }

  bool _matches(ChildSummary s) {
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      final n = normalizeName(q);
      final c = s.child;
      final hit = normalizeName(c.name).contains(n) ||
          normalizeName(c.guardianName).contains(n) ||
          c.id.toLowerCase().contains(q.toLowerCase()) ||
          ((c.nameLatin ?? '').toLowerCase().contains(q.toLowerCase())) ||
          (c.phone != null && normalizePhone(q).isNotEmpty && normalizePhone(c.phone!).contains(normalizePhone(q)));
      if (!hit) return false;
    }
    final sch = s.schedule;
    final next = sch.nextVisit;
    return switch (_filter) {
      _Filter.all => true,
      _Filter.due => sch.hasDue && !sch.hasOverdue,
      _Filter.overdue => sch.hasOverdue,
      _Filter.week => next != null && !next.isAfter(addDays(today(), 7)),
    };
  }

  Future<void> _open(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChildScreen(childId: id)));
    _reload();
  }

  Future<void> _register() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
    await _reload();
    if (id != null && mounted) _open(id);
  }

  Future<void> _settings() async {
    if (!await requireAdmin(context)) return;
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final dueN = _all.where((s) => s.schedule.hasDue && !s.schedule.hasOverdue).length;
    final overN = _all.where((s) => s.schedule.hasOverdue).length;
    final shown = _all.where(_matches).toList()
      ..sort((a, b) {
        final x = a.schedule.nextVisit, y = b.schedule.nextVisit;
        if (x == null && y == null) return b.child.seq.compareTo(a.child.seq);
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('app_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${app.workerName} · ${app.deviceCode} · ${t('beta')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
        ]),
        actions: [
          const LangToggle(),
          IconButton(tooltip: t('settings'), onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
          IconButton(tooltip: t('lock_now'), onPressed: app.lock, icon: const Icon(Icons.lock_outline)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _register,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t('register_child')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (!_notifOk)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Panel(
                        color: Brand.orangeSoft,
                        child: Row(children: [
                          const Icon(Icons.notifications_off_outlined, color: Brand.ink),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t('notif_off'))),
                          TextButton(
                            onPressed: () async {
                              await NativeBridge.requestNotificationPermission();
                              _reload();
                            },
                            child: Text(t('enable')),
                          ),
                        ]),
                      ),
                    ),
                  Row(children: [
                    _Stat(label: t('due_today_count'), value: dueN, color: Brand.blueDark, onTap: () => setState(() => _filter = _Filter.due)),
                    const SizedBox(width: 10),
                    _Stat(label: t('overdue_count'), value: overN, color: Brand.bad, onTap: () => setState(() => _filter = _Filter.overdue)),
                    const SizedBox(width: 10),
                    _Stat(label: t('registered_count'), value: _all.length, color: Brand.ink, onTap: () => setState(() => _filter = _Filter.all)),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: t('search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final f in _Filter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => t('f_all'),
                          _Filter.due => t('f_due'),
                          _Filter.overdue => t('f_overdue'),
                          _Filter.week => t('f_week'),
                        }),
                        selected: _filter == f,
                        selectedColor: Brand.blueSoft,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(t('no_children'), style: const TextStyle(color: Brand.muted))),
                    ),
                  for (final s in shown) _ChildTile(s: s, onTap: () => _open(s.child.id)),
                ],
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;
  const _Stat({required this.label, required this.value, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Panel(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            ]),
          ),
        ),
      );
}

class _ChildTile extends StatelessWidget {
  final ChildSummary s;
  final VoidCallback onTap;
  const _ChildTile({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final c = s.child;
    final look = childLook(s.schedule);
    final lang = Lang.current.value;
    final dueNow = s.schedule.doses.where((d) => d.actionable).map((d) => d.rule.label(lang)).take(3).join('، ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Panel(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: c.sex == 'M' ? Brand.blueSoft : Brand.orangeSoft,
              child: Icon(Icons.child_care, color: c.sex == 'M' ? Brand.blueDark : Brand.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Brand.ink)),
                const SizedBox(height: 2),
                Text('${c.id} · ${ageText(c.dob, lang)} · ${c.guardianName}',
                    style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                if (dueNow.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(dueNow, style: const TextStyle(fontSize: 12.5, color: Brand.ink)),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (look != null) Pill(look.$1, look.$2),
              const SizedBox(height: 6),
              if (s.schedule.nextVisit != null)
                Text(fmt(s.schedule.nextVisit), style: const TextStyle(fontSize: 12, color: Brand.muted)),
              if (s.schedule.nextVisit == null && s.schedule.doses.every((d) => d.status != DoseStatus.upcoming))
                const SizedBox.shrink(),
            ]),
          ]),
        ),
      ),
    );
  }
}
