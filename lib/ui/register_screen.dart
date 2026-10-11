import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import '../domain/text_match.dart';
import '../services/reminders.dart';
import 'common.dart';
import 'intake_screen.dart';

/// Registration and edit form (FRS-REG-01..05, 07, 10, 13).
/// Pops with the child ID when a child was created or opened.
class RegisterScreen extends StatefulWidget {
  final Child? editing;
  const RegisterScreen({super.key, this.editing});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _latin = TextEditingController();
  final _weight = TextEditingController();
  final _area = TextEditingController();
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  String _sex = '';
  String _relation = 'mother';
  DateTime? _dob;
  String? _dobError;
  int? _facilityId;
  List<Facility> _facilities = [];
  bool _busy = false;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.editing;
    if (c != null) {
      _name.text = c.name;
      _latin.text = c.nameLatin ?? '';
      _weight.text = c.birthWeight?.toString() ?? '';
      _area.text = c.area ?? '';
      _guardian.text = c.guardianName;
      _phone.text = c.phone ?? '';
      _sex = c.sex;
      _relation = c.guardianRelation ?? 'mother';
      _dob = c.dob;
      _facilityId = c.facilityId;
    } else {
      _facilityId = app.defaultFacilityId;
    }
    Repo.facilities().then((f) {
      if (!mounted) return;
      setState(() {
        _facilities = f;
        if (_facilityId != null && !f.any((x) => x.id == _facilityId)) _facilityId = null;
      });
    });
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? t('required') : null;

  bool _checkDob() {
    String? e;
    if (_dob == null) {
      e = t('required');
    } else if (_dob!.isAfter(today())) {
      e = t('dob_future');
    } else if (daysBetween(_dob!, today()) > RuleSet.maxChildAgeDays) {
      e = t('dob_too_old');
    }
    setState(() => _dobError = e);
    return e == null;
  }

  Map<String, Object?> _fields() => {
        'name': _name.text.trim(),
        'name_latin': _latin.text.trim().isEmpty ? null : _latin.text.trim(),
        'sex': _sex,
        'dob': iso(_dob!),
        'birth_weight': int.tryParse(_weight.text.trim()),
        'facility_id': _facilityId,
        'area': _area.text.trim().isEmpty ? null : _area.text.trim(),
        'guardian_name': _guardian.text.trim(),
        'guardian_relation': _relation,
        'phone': _phone.text.trim().isEmpty ? null : normalizePhone(_phone.text),
      };

  Future<void> _save() async {
    final okForm = _form.currentState!.validate();
    final okDob = _checkDob();
    if (!okForm || !okDob || _sex.isEmpty || _facilityId == null) {
      if (_sex.isEmpty || _facilityId == null) toast(context, t('required'));
      return;
    }
    setState(() => _busy = true);
    try {
      final dups = await Repo.possibleDuplicates(
        name: _name.text,
        dob: _dob!,
        guardianName: _guardian.text,
        phone: _phone.text,
        excludeId: widget.editing?.id,
      );
      if (dups.isNotEmpty && mounted) {
        final choice = await _duplicateDialog(dups);
        if (choice == null) return;
        if (choice != '__new__') {
          if (mounted) Navigator.pop(context, choice);
          return;
        }
      }
      if (_editing) {
        await Repo.updateChild(widget.editing!, _fields());
        await Reminders.rebuild();
        if (mounted) {
          toast(context, t('saved'));
          Navigator.pop(context, widget.editing!.id);
        }
        return;
      }
      final id = await Repo.createChild(_fields(), app.deviceCode);
      final needsIntake = Engine.passedMilestones(_dob!).isNotEmpty;
      if (!mounted) return;
      if (needsIntake) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => IntakeScreen(childId: id)));
      } else {
        await Repo.markHistoryDone(id);
      }
      await Reminders.rebuild();
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns the existing child ID to open, '__new__' to continue, or null.
  Future<String?> _duplicateDialog(List<Child> dups) => showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t('dup_title')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('dup_body')),
              const SizedBox(height: 12),
              for (final d in dups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.child_care, color: Brand.ink),
                  title: Text(d.name),
                  subtitle: Text('${d.id} · ${fmt(d.dob)} · ${d.guardianName}'),
                  trailing: TextButton(onPressed: () => Navigator.pop(c, d.id), child: Text(t('open'))),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, '__new__'), child: Text(t('dup_new'))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? t('edit_child') : t('register_child')), actions: const [LangToggle()]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionTitle(t('child_details')),
            TextFormField(controller: _name, decoration: InputDecoration(labelText: t('child_name')), validator: _req),
            const SizedBox(height: 12),
            TextFormField(
              controller: _latin,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t('child_name_latin')),
            ),
            const SizedBox(height: 12),
            Text(t('sex'), style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'M', label: Text(t('male')), icon: const Icon(Icons.male)),
                ButtonSegment(value: 'F', label: Text(t('female')), icon: const Icon(Icons.female)),
              ],
              selected: _sex.isEmpty ? <String>{} : {_sex},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) => setState(() => _sex = s.isEmpty ? '' : s.first),
            ),
            const SizedBox(height: 12),
            DateField(
              label: t('dob'),
              value: _dob,
              error: _dobError,
              onTap: () async {
                final d = await pickDate(context, initial: _dob, first: addDays(today(), -RuleSet.maxChildAgeDays));
                if (d != null) {
                  setState(() => _dob = d);
                  _checkDob();
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weight,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: t('birth_weight')),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                return (n == null || n < 300 || n > 7000) ? t('weight_invalid') : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _facilityId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t('facility')),
              items: [
                for (final f in _facilities)
                  DropdownMenuItem(value: f.id, child: Text('${f.name} · ${f.district} · ${f.governorate}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _facilityId = v),
              validator: (v) => v == null ? t('required') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _area, decoration: InputDecoration(labelText: t('area'))),
            SectionTitle(t('guardian')),
            TextFormField(controller: _guardian, decoration: InputDecoration(labelText: t('guardian_name')), validator: _req),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _relation,
              decoration: InputDecoration(labelText: t('relation')),
              items: [
                DropdownMenuItem(value: 'mother', child: Text(t('rel_mother'))),
                DropdownMenuItem(value: 'father', child: Text(t('rel_father'))),
                DropdownMenuItem(value: 'other', child: Text(t('rel_other'))),
              ],
              onChanged: (v) => setState(() => _relation = v ?? 'mother'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t('phone'), hintText: '7XXXXXXXX'),
              validator: (v) => (v == null || v.trim().isEmpty || isValidYemenMobile(v)) ? null : t('phone_invalid'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t('save')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
