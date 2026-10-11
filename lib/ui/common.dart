import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../domain/engine.dart';

/// App-bar button that switches Arabic/English without leaving the screen.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key});

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return TextButton(
        onPressed: () => app.updateSettings(lang: Lang.isAr ? 'en' : 'ar'),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        child: Text(t('lang_toggle')),
      );
  }
}

/// Makes the calling widget rebuild when the language changes, so every
/// open screen switches text and direction immediately (FRS-SET-01, 02).
void watchLang(BuildContext context) => Localizations.localeOf(context);

Future<DateTime?> pickDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) async {
  final now = today();
  final lastD = last ?? now;
  var init = initial ?? lastD;
  if (init.isAfter(lastD)) init = lastD;
  final firstD = first ?? DateTime.utc(now.year - 6);
  if (init.isBefore(firstD)) init = firstD;
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(init.year, init.month, init.day),
    firstDate: DateTime(firstD.year, firstD.month, firstD.day),
    lastDate: DateTime(lastD.year, lastD.month, lastD.day),
  );
  return picked == null ? null : dateOnly(picked);
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? error;
  const DateField({super.key, required this.label, required this.value, required this.onTap, this.error});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            suffixIcon: const Icon(Icons.calendar_month_outlined, color: Brand.blue),
          ),
          child: Text(value == null ? t('pick_date') : fmt(value),
              style: TextStyle(color: value == null ? Brand.muted : Brand.ink, fontSize: 16)),
        ),
      );
}

class PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  const PinField({super.key, required this.controller, required this.label, this.validator, this.onSubmitted, this.autofocus = false});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textDirection: TextDirection.ltr,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
        validator: validator,
        onFieldSubmitted: onSubmitted,
      );
}

String? pinRule(String? v) => (v == null || !RegExp(r'^\d{6}$').hasMatch(v)) ? t('pin_rule') : null;

Future<bool> confirmDialog(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('confirm'))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, String label, {bool obscure = false, bool digits = false}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: obscure,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(t('confirm'))),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}

/// Asks for the administrator PIN before an admin-only action.
Future<bool> requireAdmin(BuildContext context) async {
  if (app.role == Role.admin) return true;
  final pin = await promptText(context, t('admin_required'), t('admin_pin'), obscure: true, digits: true);
  if (pin == null) return false;
  final ok = await app.verifyAdmin(pin);
  if (!ok && context.mounted) toast(context, t('wrong_pin'));
  return ok;
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

(String, Color) statusLook(DoseStatus s) => switch (s) {
      DoseStatus.given => (t('st_given'), Brand.good),
      DoseStatus.due => (t('st_due'), Brand.blueDark),
      DoseStatus.overdue => (t('st_overdue'), Brand.bad),
      DoseStatus.upcoming => (t('st_upcoming'), Brand.muted),
      DoseStatus.notEligible => (t('st_noelig'), Brand.warn),
    };

/// Overall child status for lists.
(String, Color)? childLook(Schedule s) {
  if (s.hasOverdue) return statusLook(DoseStatus.overdue);
  if (s.hasDue) return statusLook(DoseStatus.due);
  if (s.nextVisit != null) return statusLook(DoseStatus.upcoming);
  return null;
}
