import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/text_match.dart';
import '../services/native.dart';
import 'child_screen.dart';
import 'common.dart';
import 'register_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, due, overdue, week }

enum _Age { any, infant, toddler, child }

/// Registry home: today's numbers, search, filters by status, facility and age
/// group, and the due/overdue lists that work even when notifications are off
/// (FRS-REG-08, 09, FRS-REM-06, 07).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<ChildSummary> _all = [];
  List<Facility> _facilities = [];
  _Filter _filter = _Filter.all;
  _Age _age = _Age.any;
  int? _facility;
  bool _loading = true;
  bool _notifOk = true;

  @override
  void initState() {
    super.initState();
    _reload().then((_) => _openFromNotification());
  }

  Future<void> _reload() async {
    final list = await Repo.summaries();
    final fac = await Repo.facilities();
    bool ok = true;
    try {
      ok = await NativeBridge.notificationsEnabled();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = list;
      _facilities = fac;
      _notifOk = ok;
      _loading = false;
    });
  }

  /// A reminder for a single child opens that child's record (FRS-REM-02).
  Future<void> _openFromNotification() async {
    String? id;
    try {
      id = await NativeBridge.takeLaunchChild();
    } catch (_) {}
    if (id == null || !mounted) return;
    if (id == '*') {
      setState(() => _filter = _Filter.due);
      return;
    }
    if (_all.any((s) => s.child.id == id)) _open(id);
  }

  bool _matches(ChildSummary s) {
    final q = _search.text.trim();
    final c = s.child;
    if (q.isNotEmpty) {
      final n = normalizeName(q);
      final hit = normalizeName(c.name).contains(n) ||
          normalizeName(c.guardianName).contains(n) ||
          c.id.toLowerCase().contains(q.toLowerCase()) ||
          ((c.nameLatin ?? '').toLowerCase().contains(q.toLowerCase())) ||
          (c.phone != null && normalizePhone(q).isNotEmpty && normalizePhone(c.phone!).contains(normalizePhone(q)));
      if (!hit) return false;
    }
    if (_facility != null && c.facilityId != _facility) return false;
    final ageDays = daysBetween(c.dob, today());
    final ageOk = switch (_age) {
      _Age.any => true,
      _Age.infant => ageDays < 365,
      _Age.toddler => ageDays >= 365 && ageDays < 730,
      _Age.child => ageDays >= 730,
    };
    if (!ageOk) return false;
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

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? t('good_morning') : t('good_evening');
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final dueN = _all.where((s) => s.schedule.hasDue && !s.schedule.hasOverdue).length;
    final overN = _all.where((s) => s.schedule.hasOverdue).length;
    final weekN = _all.where((s) {
      final n = s.schedule.nextVisit;
      return n != null && !n.isAfter(addDays(today(), 7));
    }).length;
    final upToDate = _all.isEmpty ? 0 : ((_all.length - overN) * 100 / _all.length).round();
    final shown = _all.where(_matches).toList()
      ..sort((a, b) {
        final x = a.schedule.nextVisit, y = b.schedule.nextVisit;
        if (x == null && y == null) return b.child.seq.compareTo(a.child.seq);
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
    var facName = '';
    for (final f in _facilities) {
      if (f.id == app.defaultFacilityId) facName = f.name;
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_register'),
        onPressed: _register,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t('register_child')),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GradientHeader(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_greeting()}${app.workerName.isEmpty ? '' : '${Lang.isAr ? '، ' : ', '}${app.workerName}'}',
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(t('app_title'),
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const LangToggle(light: true),
                    IconButton(
                      key: const Key('home_settings'),
                      tooltip: t('settings'),
                      onPressed: _settings,
                      color: Colors.white,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    IconButton(
                      key: const Key('home_lock'),
                      tooltip: t('lock_now'),
                      onPressed: app.lock,
                      color: Colors.white,
                      icon: const Icon(Icons.lock_outline),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.local_hospital_outlined, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('$facName · ${fmt(today())}',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: Row(children: [
                      _Stat(
                          icon: Icons.today,
                          label: t('due_today_count'),
                          value: '$dueN',
                          selected: _filter == _Filter.due,
                          onTap: () => setState(() => _filter = _Filter.due)),
                      const SizedBox(width: 10),
                      _Stat(
                          icon: Icons.warning_amber_rounded,
                          label: t('overdue_count'),
                          value: '$overN',
                          alert: overN > 0,
                          selected: _filter == _Filter.overdue,
                          onTap: () => setState(() => _filter = _Filter.overdue)),
                      const SizedBox(width: 10),
                      _Stat(
                          icon: Icons.date_range,
                          label: t('f_week'),
                          value: '$weekN',
                          selected: _filter == _Filter.week,
                          onTap: () => setState(() => _filter = _Filter.week)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: _Coverage(percent: upToDate, total: _all.length),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList.list(children: [
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
                TextField(
                  key: const Key('home_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t('search_hint'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in _Filter.values) ...[
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => t('f_all'),
                          _Filter.due => t('f_due'),
                          _Filter.overdue => t('f_overdue'),
                          _Filter.week => t('f_week'),
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _MenuChip<_Age>(
                      icon: Icons.cake_outlined,
                      label: switch (_age) {
                        _Age.any => t('age_any'),
                        _Age.infant => t('age_infant'),
                        _Age.toddler => t('age_toddler'),
                        _Age.child => t('age_child'),
                      },
                      active: _age != _Age.any,
                      items: {
                        _Age.any: t('age_any'),
                        _Age.infant: t('age_infant'),
                        _Age.toddler: t('age_toddler'),
                        _Age.child: t('age_child'),
                      },
                      onSelected: (v) => setState(() => _age = v),
                    ),
                    const SizedBox(width: 8),
                    if (_facilities.length > 1)
                      _MenuChip<int>(
                        icon: Icons.local_hospital_outlined,
                        label: _facility == null
                            ? t('all_facilities')
                            : _facilities.firstWhere((f) => f.id == _facility, orElse: () => _facilities.first).name,
                        active: _facility != null,
                        items: {-1: t('all_facilities'), for (final f in _facilities) f.id: f.name},
                        onSelected: (v) => setState(() => _facility = v == -1 ? null : v),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (shown.isEmpty)
                  _Empty(registry: _all.isEmpty)
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Text(tf('n_children', {'n': shown.length}), style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ),
                  for (final s in shown) _ChildCard(key: Key('child_${s.child.id}'), s: s, onTap: () => _open(s.child.id)),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final bool alert;
  final VoidCallback onTap;
  const _Stat({required this.icon, required this.label, required this.value, required this.onTap, this.selected = false, this.alert = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: selected ? Colors.white : Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 18, color: selected ? (alert ? Brand.bad : Brand.blueDark) : Colors.white),
                  if (alert) ...[
                    const Spacer(),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Brand.orange, shape: BoxShape.circle)),
                  ],
                ]),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: selected ? (alert ? Brand.bad : Brand.ink) : Colors.white)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: selected ? Brand.muted : Colors.white)),
              ]),
            ),
          ),
        ),
      );
}

class _Coverage extends StatelessWidget {
  final int percent;
  final int total;
  const _Coverage({required this.percent, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.verified_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tf('coverage_line', {'p': percent, 'n': total}),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          SizedBox(
            width: 84,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : percent / 100,
                minHeight: 6,
                color: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.25),
              ),
            ),
          ),
        ]),
      );
}

class _MenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;
  const _MenuChip({super.key, required this.icon, required this.label, required this.active, required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        onSelected: onSelected,
        itemBuilder: (_) => [for (final e in items.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? Brand.blueSoft : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: active ? Brand.blue : Brand.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: active ? Brand.blueDark : Brand.muted),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: active ? Brand.blueDark : Brand.ink, fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.arrow_drop_down, color: Brand.muted),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  final bool registry;
  const _Empty({required this.registry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: Brand.blueSoft, shape: BoxShape.circle),
            child: Icon(registry ? Icons.child_care : Icons.search_off, size: 42, color: Brand.blueDark),
          ),
          const SizedBox(height: 16),
          Text(registry ? t('empty_registry_title') : t('no_children'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(registry ? t('empty_registry_body') : t('no_results_body'),
              textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.5)),
        ]),
      );
}

class _ChildCard extends StatelessWidget {
  final ChildSummary s;
  final VoidCallback onTap;
  const _ChildCard({super.key, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final c = s.child;
    final st = childStatus(s.schedule);
    final color = st == null ? Brand.good : statusLook(st).$2;
    final lang = Lang.current.value;
    final dueNow = s.schedule.doses.where((d) => d.actionable).map((d) => d.rule.label(lang)).take(3).join(lang == 'ar' ? '، ' : ', ');
    final next = s.schedule.nextVisit;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: Brand.cardShadow, color: Colors.white),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(20)).resolve(Directionality.of(context)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                    child: Row(children: [
                      Initials(c.name, color: c.sex == 'M' ? Brand.blue : Brand.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                          const SizedBox(height: 2),
                          Text('${ageText(c.dob, lang)} · ${c.guardianName}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                          Text(c.id, textDirection: TextDirection.ltr, style: const TextStyle(color: Brand.muted, fontSize: 12, letterSpacing: 0.3)),
                          if (dueNow.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              Icon(Icons.vaccines_outlined, size: 15, color: color),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(dueNow,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        ProgressRing(
                          value: s.schedule.progress,
                          size: 44,
                          stroke: 4.5,
                          center: Text('${s.schedule.givenCount}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.good)),
                        ),
                        const SizedBox(height: 6),
                        if (st != null) statusPill(st),
                        if (next != null) ...[
                          const SizedBox(height: 4),
                          Text(fmt(next), style: const TextStyle(fontSize: 12, color: Brand.muted)),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
