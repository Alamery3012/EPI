# EPI Immunization App — Beta 0.1.0

Offline Android app for YFCA / MoPHP-EPI (RFQ P24-12/RFQ/26/265), built by Nomow Soft in Flutter.
Arabic is the default language; English is available on every screen.

> **Clinical rules are provisional.** Milestones and vaccines follow TOR Section 7. Minimum ages,
> intervals, age limits and spacing are placeholders in `lib/domain/rules.dart` until YFCA supplies
> the approved rule document. Do not use this build clinically.

## Get the APK (GitHub, no local setup)

1. Create a **private** GitHub repository and push this folder to its `main` branch.
2. GitHub runs **Actions → Build APK** automatically (about 10–15 minutes). It:
   generates the Android project, downloads the Arabic font, applies `tool/patch_android.py`,
   runs `flutter analyze` and the unit tests, and builds the release APKs.
3. Open the finished run and download the artifact **EPI-beta-0.1.0-apk**. It contains:
   - `EPI-beta-0.1.0-universal.apk`: installs on any phone (use this one if unsure)
   - `EPI-beta-0.1.0-armeabi-v7a.apk`: smaller, for older 32-bit phones
   - `EPI-beta-0.1.0-arm64-v8a.apk`: smaller, for most current phones
   - `EPI-beta-0.1.0-x86_64.apk`: emulators
4. Copy the APK to the phone and install it (allow "install unknown apps" for the file manager).

The beta is signed with the debug key. The production signing key is created at handover (Day 18)
and given to MoPHP/EPI.

## Build locally

Requires Flutter (stable), Android SDK and Java 17.

```bash
flutter create --org org.yfca --project-name epi_app --platforms android .
bash tool/get_fonts.sh
python3 tool/patch_android.py
flutter pub get
flutter test
flutter build apk --release
```

## First run

1. **Setup (administrator):** device code (e.g. `ADN07`), health-worker name, default facility,
   worker PIN and administrator PIN (6 digits each, different).
2. **Lock screen:** either PIN unlocks; the administrator PIN also opens Settings.
3. **Register a child.** If the child is older than a milestone, the past-visit intake starts.
4. **Child screen:** record a visit, print the A4 card, export Excel, add a campaign dose.

## What the beta covers (FRS v0.1)

| Area | Requirements | Status |
|---|---|---|
| Registry | FRS-REG-01..13: fields, validation, child ID with check digit, duplicate warning, search, filters, edit with audit, void | Done |
| Clinical engine | FRS-SCH-01..13: routine schedule, statuses, minimum age and interval, Rota cut-off, MR and live-vaccine spacing, forward rescheduling, versioned rule tables | Done (provisional values) |
| Past visits | FRS-HIS-01..07: guided milestone-by-milestone intake, validation, first missed milestone, catch-up | Done |
| Visits | FRS-VIS-01..05: date, site, only valid doses selectable, reasons not given, void dose (long-press) | Done |
| Reminders | FRS-REM-01..10: before/on/after, grouped per day, rebuilt after restart, time change and update, due/overdue lists, calendar sync by stored event ID | Done |
| Documents | FRS-DOC-01..09: OpenXML .xlsx (RTL, saved to Downloads/EPI), single-page A4 card (print or save as PDF), export warning, audit | Done (headings and notice provisional) |
| Security | FRS-SEC-01..10: SQLCipher, Keystore-wrapped key, PBKDF2 PINs, lockout, auto-lock after 5 min idle or 30 s in background, no backup or device transfer, FLAG_SECURE, no network permission, append-only audit log, secure wipe | Done |
| Settings | FRS-SET-01..05: Arabic/English switch on any screen without losing typed data, setup, About with rule version, offline | Done |

## Known gaps before UAT

- Rule values, MoPHP/EPI headings, clinical notice text, Excel template and facility lists from YFCA (FRS open questions Q1–Q10).
- Launcher icon is Flutter's default; the YFCA/EPI icon is added once approved.
- Screenshots are blocked by design (FLAG_SECURE). For UAT evidence, use photos of the screen or a debug build.

## Project layout

```
lib/domain/      rules.dart (rule tables), engine.dart (scheduling), child_id.dart, text_match.dart
lib/data/        db.dart (SQLCipher schema), models.dart, repo.dart (all writes audited)
lib/services/    native.dart (platform channel), reminders.dart, xlsx.dart, zip_writer.dart, card_pdf.dart
lib/ui/          setup, lock, home, register, intake, child, visit, settings screens
native/          MainActivity.kt (Keystore, PIN hash, permissions, calendar, downloads), ReminderStore.kt, ReminderReceiver.kt
tool/            patch_android.py, get_fonts.sh
test/            unit tests for the TOR acceptance scenarios
```
