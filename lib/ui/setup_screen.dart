import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/repo.dart';
import '../services/native.dart';
import 'common.dart';

/// First-time setup by the device administrator, in three short steps
/// (FRS-SET-03): device and health worker, facility, PINs and reminders.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _forms = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  // Re-run validation after a language switch so visible errors change language too.
  final _validated = <int>{};
  String _errLang = Lang.current.value;
  final _device = TextEditingController();
  final _worker = TextEditingController();
  final _fCode = TextEditingController();
  final _fName = TextEditingController();
  final _gov = TextEditingController();
  final _dist = TextEditingController();
  final _wPin = TextEditingController();
  final _wPin2 = TextEditingController();
  final _aPin = TextEditingController();
  final _aPin2 = TextEditingController();
  final _before = TextEditingController(text: '3');
  final _after = TextEditingController(text: '3');
  int _step = 0;
  bool _busy = false;

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? t('required') : null;

  bool _validate(int i) {
    _validated.add(i);
    _errLang = Lang.current.value;
    return _forms[i].currentState!.validate();
  }

  Future<void> _next() async {
    if (!_validate(_step)) return;
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    try {
      final fid = await Repo.addFacility(_fCode.text, _fName.text, _gov.text, _dist.text);
      await app.completeSetup(
        deviceCode: _device.text.trim(),
        workerName: _worker.text.trim(),
        facilityId: fid,
        workerPin: _wPin.text,
        adminPin: _aPin.text,
        offsetBefore: (int.tryParse(_before.text) ?? 3).clamp(0, 30).toInt(),
        offsetAfter: (int.tryParse(_after.text) ?? 3).clamp(0, 30).toInt(),
      );
      await NativeBridge.requestNotificationPermission();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepBar() {
    final labels = [t('step_device'), t('step_facility'), t('step_security')];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        Expanded(
          child: Column(children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= _step ? Colors.white : Colors.white.withOpacity(0.28),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 8),
            Text(labels[i],
                style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
        if (i < 2) const SizedBox(width: 8),
      ],
    ]);
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Form(
          key: _forms[0],
          child: Column(children: [
            TextFormField(
              key: const Key('setup_device'),
              controller: _device,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: t('device_code'),
                helperText: t('device_code_hint'),
                prefixIcon: const Icon(Icons.tablet_android_outlined),
              ),
              validator: (v) => (v == null || !RegExp(r'^[A-Za-z0-9]{3,8}$').hasMatch(v.trim())) ? t('device_code_hint') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('setup_worker'),
              controller: _worker,
              decoration: InputDecoration(labelText: t('worker_name'), prefixIcon: const Icon(Icons.badge_outlined)),
              validator: _req,
            ),
          ]),
        );
      case 1:
        return Form(
          key: _forms[1],
          child: Column(children: [
            TextFormField(
              key: const Key('setup_fname'),
              controller: _fName,
              decoration: InputDecoration(labelText: t('facility_name'), prefixIcon: const Icon(Icons.local_hospital_outlined)),
              validator: _req,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('setup_fcode'),
              controller: _fCode,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t('facility_code'), prefixIcon: const Icon(Icons.qr_code_2)),
              validator: _req,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('setup_gov'),
              controller: _gov,
              decoration: InputDecoration(labelText: t('governorate'), prefixIcon: const Icon(Icons.map_outlined)),
              validator: _req,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('setup_dist'),
              controller: _dist,
              decoration: InputDecoration(labelText: t('district'), prefixIcon: const Icon(Icons.place_outlined)),
              validator: _req,
            ),
          ]),
        );
      default:
        return Form(
          key: _forms[2],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(Icons.person_outline, t('worker_pin')),
            PinField(key: const Key('setup_wpin'), controller: _wPin, label: t('worker_pin'), validator: pinRule),
            const SizedBox(height: 12),
            PinField(
              key: const Key('setup_wpin2'),
              controller: _wPin2,
              label: t('pin_repeat'),
              validator: (v) => v != _wPin.text ? t('pin_mismatch') : null,
            ),
            const SizedBox(height: 18),
            _label(Icons.admin_panel_settings_outlined, t('admin_pin')),
            PinField(
              key: const Key('setup_apin'),
              controller: _aPin,
              label: t('admin_pin'),
              validator: (v) => pinRule(v) ?? (v == _wPin.text ? t('pins_same') : null),
            ),
            const SizedBox(height: 12),
            PinField(
              key: const Key('setup_apin2'),
              controller: _aPin2,
              label: t('pin_repeat'),
              validator: (v) => v != _aPin.text ? t('pin_mismatch') : null,
            ),
            const SizedBox(height: 18),
            _label(Icons.notifications_active_outlined, t('reminders')),
            Row(children: [
              Expanded(child: _days(const Key('setup_before'), _before, t('offset_before'))),
              const SizedBox(width: 12),
              Expanded(child: _days(const Key('setup_after'), _after, t('offset_after'))),
            ]),
          ]),
        );
    }
  }

  Widget _label(IconData i, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(i, size: 20, color: Brand.blueDark),
          const SizedBox(width: 8),
          Text(s, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      );

  Widget _days(Key key, TextEditingController c, String label) => TextFormField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return (n == null || n < 0 || n > 30) ? t('days_range') : null;
        },
      );

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    if (_validated.isNotEmpty && _errLang != Lang.current.value) {
      _errLang = Lang.current.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final i in _validated) {
          _forms[i].currentState?.validate();
        }
      });
    }
    final titles = [t('step_device_title'), t('step_facility_title'), t('step_security_title')];
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.vaccines, color: Brand.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('setup_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(t('app_title'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              const LangToggle(light: true),
            ]),
            const SizedBox(height: 20),
            _stepBar(),
          ]),
        ),
        Expanded(
          child: ListView(
            key: const Key('setup_list'),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Text(titles[_step], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_step == 0 ? t('setup_intro') : tf('step_of', {'i': _step + 1, 'n': 3}),
                  style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 18),
              Panel(child: _stepBody()),
              const SizedBox(height: 22),
              Row(children: [
                if (_step > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('setup_back'),
                      onPressed: _busy ? null : () => setState(() => _step--),
                      child: Text(t('back')),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const Key('setup_next'),
                    onPressed: _busy ? null : _next,
                    child: _busy
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_step < 2 ? t('next') : t('start_using')),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
