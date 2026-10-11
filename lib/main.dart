import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'core/i18n.dart';
import 'core/theme.dart';
import 'ui/home_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerExtraLicenses();
  runApp(const EpiApp());
  app.init();
}

class EpiApp extends StatefulWidget {
  const EpiApp({super.key});

  @override
  State<EpiApp> createState() => _EpiAppState();
}

final navKey = GlobalKey<NavigatorState>();

class _EpiAppState extends State<EpiApp> with WidgetsBindingObserver {
  DateTime? _backgroundSince;
  bool _wasUnlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.addListener(_onApp);
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the session locks, close every screen and dialog above home so
  /// nothing stays visible behind the lock screen.
  void _onApp() {
    if (_wasUnlocked && !app.unlocked) {
      navKey.currentState?.popUntil((r) => r.isFirst);
    }
    _wasUnlocked = app.unlocked;
  }

  /// Lock after the app has been in the background (FRS-SEC-05). A short
  /// grace of 30 seconds lets the print and share dialogs return without
  /// a lock; the recent-apps preview is hidden by FLAG_SECURE meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (since != null && DateTime.now().difference(since).inSeconds >= 30) app.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Lang.current,
      builder: (context, lang, _) => MaterialApp(
        title: t('app_title'),
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        theme: buildTheme(),
        locale: Locale(lang),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.ready) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (app.startupError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Startup error:\n${app.startupError}', textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (!app.setupDone) return const SetupScreen();
        if (!app.unlocked) return const LockScreen();
        // Any touch resets the inactivity timer.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => app.touch(),
          child: const HomeScreen(),
        );
      },
    );
  }
}

/// Notices for components that Flutter does not register automatically
/// (native SQLCipher library and the bundled Amiri font). Dart/Flutter package
/// licenses (sqflite_sqlcipher, pdf, printing, path, Flutter) appear on the
/// license page by default.
void _registerExtraLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['SQLCipher Community Edition'], """
Copyright (c) Zetetic LLC. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
  * Neither the name of the ZETETIC LLC nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY ZETETIC LLC ''AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL ZETETIC LLC BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.""");
    // TODO before release: replace with the full OFL-1.1 text shipped with the font (OFL.txt).
    yield const LicenseEntryWithLineBreaks(['Amiri font'], """
Copyright The Amiri Project Authors (https://github.com/aliftype/amiri).
This Font Software is licensed under the SIL Open Font License, Version 1.1.
License text: https://openfontlicense.org""");
  });
}
