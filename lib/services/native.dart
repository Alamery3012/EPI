import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Bridge to the native Android code in android/.../MainActivity.kt.
/// Keystore, PIN hashing, alarms, calendar and downloads use the Android API
/// directly (offer Section 5: native system services via platform channels).
class NativeBridge {
  static const _ch = MethodChannel('org.yfca.epi/native');

  /// 32-byte database key, generated once and protected by the Android
  /// Keystore (FRS-SEC-02). Returned as hex.
  static Future<String> dbKey() async => (await _ch.invokeMethod<String>('getDbKey'))!;

  /// PBKDF2-HMAC-SHA256 of the PIN with [saltHex] (FRS-SEC-03).
  static Future<String> hashPin(String pin, String saltHex) async =>
      (await _ch.invokeMethod<String>('hashPin', {'pin': pin, 'salt': saltHex}))!;

  static Future<bool> requestNotificationPermission() async =>
      (await _ch.invokeMethod<bool>('requestNotificationPermission')) ?? false;

  static Future<bool> notificationsEnabled() async =>
      (await _ch.invokeMethod<bool>('notificationsEnabled')) ?? false;

  /// Replaces every scheduled reminder with [alarms] (FRS-REM-04). The list is
  /// also stored natively so it can be rebuilt after a restart (FRS-REM-05).
  static Future<void> setReminders(List<Map<String, Object?>> alarms) =>
      _ch.invokeMethod('setReminders', {'alarms': alarms});

  static Future<bool> requestCalendarPermission() async =>
      (await _ch.invokeMethod<bool>('requestCalendarPermission')) ?? false;

  /// Creates or updates one calendar event; returns its ID (FRS-REM-09).
  static Future<int?> calendarUpsert({int? eventId, required String title, required String description, required int startMillis}) =>
      _ch.invokeMethod<int>('calendarUpsert', {
        'eventId': eventId,
        'title': title,
        'description': description,
        'start': startMillis,
      });

  static Future<void> calendarDelete(int eventId) => _ch.invokeMethod('calendarDelete', {'eventId': eventId});

  /// Saves a file to Downloads/EPI and returns where it went.
  static Future<String> saveToDownloads(Uint8List bytes, String fileName, String mime) async =>
      (await _ch.invokeMethod<String>('saveToDownloads', {'bytes': bytes, 'name': fileName, 'mime': mime}))!;

  /// Clears native preferences, keys and alarms (FRS-SEC-10).
  static Future<void> wipe() => _ch.invokeMethod('wipe');

  static Future<String> appVersion() async => (await _ch.invokeMethod<String>('appVersion')) ?? '';
}
