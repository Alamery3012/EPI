import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/repo.dart';
import '../services/native.dart';
import 'common.dart';

/// First-time setup by the device administrator (FRS-SET-03).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  // Re-run validation after a language switch so visible errors change language too.
  bool _validated = false;
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
  bool _busy = false;

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? t('required') : null;

  Future<void> _save() async {
    _validated = true;
    _errLang = Lang.current.value;
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final fid = await Repo.addFacility(_fCode.text, _fName.text, _gov.text, _dist.text);
      await app.completeSetup(
        deviceCode: _device.text.trim(),
        workerName: _worker.text.trim(),
        facilityId: fid,
        workerPin: _wPin.text,
        adminPin: _aPin.text,
      );
      await NativeBridge.requestNotificationPermission();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    if (_validated && _errLang != Lang.current.value) {
      _errLang = Lang.current.value;
      WidgetsBinding.instance.addPostFrameCallback((_) => _form.currentState?.validate());
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('setup_title')), actions: const [LangToggle()]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              color: Brand.blueSoft,
              child: Row(children: [
                const Icon(Icons.vaccines_outlined, color: Brand.blue, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('app_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.ink)),
                    Text(t('setup_intro'), style: const TextStyle(color: Brand.muted)),
                  ]),
                ),
              ]),
            ),
            SectionTitle(t('device_code')),
            TextFormField(
              controller: _device,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t('device_code'), helperText: t('device_code_hint')),
              validator: (v) => (v == null || !RegExp(r'^[A-Za-z0-9]{3,8}$').hasMatch(v.trim())) ? t('device_code_hint') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _worker, decoration: InputDecoration(labelText: t('worker_name')), validator: _req),
            SectionTitle(t('first_facility')),
            TextFormField(controller: _fName, decoration: InputDecoration(labelText: t('facility_name')), validator: _req),
            const SizedBox(height: 12),
            TextFormField(controller: _fCode, decoration: InputDecoration(labelText: t('facility_code')), validator: _req),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _gov, decoration: InputDecoration(labelText: t('governorate')), validator: _req)),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _dist, decoration: InputDecoration(labelText: t('district')), validator: _req)),
            ]),
            SectionTitle(t('worker_pin')),
            PinField(controller: _wPin, label: t('worker_pin'), validator: pinRule),
            const SizedBox(height: 12),
            PinField(
              controller: _wPin2,
              label: t('pin_repeat'),
              validator: (v) => v != _wPin.text ? t('pin_mismatch') : null,
            ),
            SectionTitle(t('admin_pin')),
            PinField(
              controller: _aPin,
              label: t('admin_pin'),
              validator: (v) => pinRule(v) ?? (v == _wPin.text ? t('pins_same') : null),
            ),
            const SizedBox(height: 12),
            PinField(
              controller: _aPin2,
              label: t('pin_repeat'),
              validator: (v) => v != _aPin.text ? t('pin_mismatch') : null,
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
