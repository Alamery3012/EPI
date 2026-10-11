import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'core/i18n.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'services/native.dart';

enum Role { worker, admin }

/// Session, security and device settings (FRS-SEC-03..05, FRS-SET-03).
class AppState extends ChangeNotifier {
  bool ready = false;
  bool setupDone = false;
  bool unlocked = false;
  Role role = Role.worker;
  String deviceCode = '';
  String workerName = '';
  int? defaultFacilityId;
  int offsetBefore = 3;
  int offsetAfter = 3;
  bool calendarSync = false;
  String? startupError;

  static const inactivity = Duration(minutes: 5);
  Timer? _idle;

  Future<void> init() async {
    try {
      final key = await NativeBridge.dbKey();
      await AppDb.open(key);
      await _load();
    } catch (e) {
      startupError = '$e';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _load() async {
    setupDone = (await Repo.getSetting('setup_done')) == '1';
    deviceCode = await Repo.getSetting('device_code') ?? '';
    workerName = await Repo.getSetting('worker_name') ?? '';
    defaultFacilityId = int.tryParse(await Repo.getSetting('default_facility') ?? '');
    offsetBefore = int.tryParse(await Repo.getSetting('offset_before') ?? '') ?? 3;
    offsetAfter = int.tryParse(await Repo.getSetting('offset_after') ?? '') ?? 3;
    calendarSync = (await Repo.getSetting('calendar_sync')) == '1';
    final lang = await Repo.getSetting('language');
    if (lang == 'ar' || lang == 'en') Lang.current.value = lang!;
    Repo.currentUser = workerName.isEmpty ? 'worker' : workerName;
  }

  static String _salt() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> setPin(Role who, String pin) async {
    final salt = _salt();
    final hash = await NativeBridge.hashPin(pin, salt);
    final k = who == Role.admin ? 'admin' : 'worker';
    await Repo.setSetting('pin_${k}_salt', salt, audit: false);
    await Repo.setSetting('pin_${k}_hash', hash, audit: false);
  }

  Future<bool> _check(Role who, String pin) async {
    final k = who == Role.admin ? 'admin' : 'worker';
    final salt = await Repo.getSetting('pin_${k}_salt');
    final hash = await Repo.getSetting('pin_${k}_hash');
    if (salt == null || hash == null) return false;
    return await NativeBridge.hashPin(pin, salt) == hash;
  }

  /// Minutes still locked after repeated failures (FRS-SEC-04), or 0.
  Future<int> lockedMinutes() async {
    final until = DateTime.tryParse(await Repo.getSetting('lock_until') ?? '');
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left <= 0 ? 0 : (left / 60).ceil();
  }

  /// Returns null on success, otherwise an error message.
  Future<String?> unlock(String pin) async {
    final mins = await lockedMinutes();
    if (mins > 0) return tf('locked_for', {'m': mins});
    Role? who;
    if (await _check(Role.worker, pin)) who = Role.worker;
    if (who == null && await _check(Role.admin, pin)) who = Role.admin;
    if (who == null) {
      final fails = (int.tryParse(await Repo.getSetting('fail_count') ?? '') ?? 0) + 1;
      await Repo.setSetting('fail_count', '$fails', audit: false);
      await Repo.logAudit('login_failed', 'session', null, 'attempt $fails');
      if (fails % 5 == 0) {
        final rounds = fails ~/ 5;
        final int shift = min(max(rounds - 1, 0), 6);
        final minutes = 5 * (1 << shift);
        await Repo.setSetting('lock_until', DateTime.now().add(Duration(minutes: minutes)).toIso8601String(), audit: false);
        return tf('locked_for', {'m': minutes});
      }
      return t('wrong_pin');
    }
    await Repo.setSetting('fail_count', '0', audit: false);
    role = who;
    unlocked = true;
    Repo.currentUser = who == Role.admin ? 'admin' : (workerName.isEmpty ? 'worker' : workerName);
    await Repo.logAudit('login', 'session', null, who.name);
    touch();
    notifyListeners();
    return null;
  }

  Future<bool> verifyAdmin(String pin) => _check(Role.admin, pin);

  void lock() {
    if (!unlocked) return;
    unlocked = false;
    _idle?.cancel();
    notifyListeners();
  }

  /// Resets the inactivity timer (FRS-SEC-05).
  void touch() {
    _idle?.cancel();
    if (unlocked) _idle = Timer(inactivity, lock);
  }

  Future<void> completeSetup({
    required String deviceCode,
    required String workerName,
    required int facilityId,
    required String workerPin,
    required String adminPin,
    int offsetBefore = 3,
    int offsetAfter = 3,
  }) async {
    await Repo.setSetting('device_code', deviceCode.toUpperCase());
    await Repo.setSetting('worker_name', workerName);
    await Repo.setSetting('default_facility', '$facilityId');
    await Repo.setSetting('offset_before', '$offsetBefore');
    await Repo.setSetting('offset_after', '$offsetAfter');
    await Repo.setSetting('language', Lang.current.value);
    await setPin(Role.worker, workerPin);
    await setPin(Role.admin, adminPin);
    await Repo.setSetting('setup_done', '1');
    await _load();
    unlocked = true;
    role = Role.admin;
    touch();
    notifyListeners();
  }

  Future<void> updateSettings({int? before, int? after, bool? calendar, String? worker, String? lang}) async {
    if (before != null) await Repo.setSetting('offset_before', '$before');
    if (after != null) await Repo.setSetting('offset_after', '$after');
    if (calendar != null) await Repo.setSetting('calendar_sync', calendar ? '1' : '0');
    if (worker != null) await Repo.setSetting('worker_name', worker);
    if (lang != null) {
      await Repo.setSetting('language', lang);
      Lang.current.value = lang;
    }
    await _load();
    notifyListeners();
  }

  Future<void> wipe() async {
    await AppDb.wipe();
    await NativeBridge.wipe();
    setupDone = false;
    unlocked = false;
    final key = await NativeBridge.dbKey();
    await AppDb.open(key);
    await _load();
    notifyListeners();
  }
}

final app = AppState();
