import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/reminders.dart';
import 'common.dart';

/// PIN entry with lockout after repeated failures (FRS-SEC-03, 04).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    if (_pin.text.length != 6 || _busy) return;
    setState(() => _busy = true);
    final err = await app.unlock(_pin.text);
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _error = err;
      _busy = false;
    });
    if (err == null) Reminders.rebuild();
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Scaffold(
      backgroundColor: Brand.blue,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(alignment: AlignmentDirectional.centerEnd, child: const LangToggle()),
              const Icon(Icons.vaccines_outlined, color: Colors.white, size: 64),
              const SizedBox(height: 12),
              Text(t('app_title'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(t('app_subtitle'), style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 6),
              Container(width: 48, height: 3, color: Brand.orange),
              const SizedBox(height: 28),
              Panel(
                child: Column(children: [
                  Text(t('enter_pin'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  PinField(
                    controller: _pin,
                    label: '',
                    autofocus: true,
                    onSubmitted: (_) => _go(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Brand.bad)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _busy ? null : _go, child: Text(t('unlock'))),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('${app.deviceCode} · ${t('beta')} 0.1.0', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
