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
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _digit(String d) {
    if (_busy || _pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 6) _go();
  }

  void _delete() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final err = await app.unlock(_pin);
    if (!mounted) return;
    setState(() {
      _error = err;
      _busy = false;
      if (err != null) _pin = '';
    });
    if (err == null) Reminders.rebuild();
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.headerGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(children: [
                    const Align(alignment: AlignmentDirectional.centerEnd, child: LangToggle(light: true)),
                    const SizedBox(height: 18),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                      child: const Icon(Icons.vaccines, color: Brand.blue, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(t('app_title'),
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(t('app_subtitle'), style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 10),
                    Container(width: 44, height: 4, decoration: BoxDecoration(color: Brand.orange, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                      decoration: BoxDecoration(
                        color: Brand.surface,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.lock_outline, color: Brand.blueDark, size: 20),
                          const SizedBox(width: 8),
                          Text(t('enter_pin'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 18),
                        PinDots(filled: _pin.length, error: _error != null),
                        SizedBox(
                          height: 40,
                          child: Center(
                            child: _busy
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Brand.bad, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        PinPad(onDigit: _digit, onDelete: _delete, enabled: !_busy),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('${app.deviceCode} · ${t('encrypted_offline')} · v0.2.0',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
