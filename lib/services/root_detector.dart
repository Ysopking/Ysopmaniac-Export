import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Root- und Emulator-Detection (S-04 + S-15).
///
/// Schutzziel: Wenn die App auf einem gerooteten Geraet oder Emulator laeuft,
/// hat der Angreifer potentiell:
///   • Zugriff auf /data/user/0/io.findux.app/ (Hive-Box, SharedPrefs)
///   • Moeglichkeit einen Debugger anzuhaengen (ptrace)
///   • Keinen echten Hardware-Keystore (Emulator)
///
/// Reaktion: KEIN sofortiger App-Abbruch (wuerde legitime Power-User ausschliessen).
/// Stattdessen: Warnung anzeigen + sensitiven Features einschraenken.
///
/// Erkennungsmethoden:
///   1. su-Binary-Suche in bekannten Pfaden
///   2. Bekannte Root-Management-Apps (Magisk, SuperSU, KingRoot)
///   3. Build-Properties die auf Emulator hinweisen
///   4. /proc/self/status TracerPid-Check (Debugger aktiv?)
class RootDetector {
  RootDetector._();

  static const _suPaths = [
    '/system/app/Superuser.apk',
    '/sbin/su',
    '/system/bin/su',
    '/system/xbin/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/data/local/su',
    '/su/bin/su',
  ];

  static const _rootPackages = [
    'com.topjohnwu.magisk',       // Magisk
    'com.koushikdutta.superuser', // SuperSU
    'com.noshufou.android.su',    // SuperUser
    'com.kingroot.kinguser',      // KingRoot
    'com.kingo.root',             // KingoRoot
    'eu.chainfire.supersu',       // Chainfire SuperSU
  ];

  /// Prueft ob das Geraet gerootet ist.
  /// Gibt [RootStatus] zurueck mit Details.
  static Future<RootStatus> check() async {
    if (!Platform.isAndroid) return RootStatus.clean;

    // 1. su-Binary-Suche
    for (final path in _suPaths) {
      try {
        if (await File(path).exists()) {
          if (kDebugMode) debugPrint('RootDetector: su-Binary gefunden: $path');
          return RootStatus.rooted;
        }
      } catch (_) {}
    }

    // 2. Root-App-Pakete via Package Manager
    // (Pruefung nur via ProcessResult, kein Plugin benoetigt)
    for (final pkg in _rootPackages) {
      try {
        final result = await Process.run('pm', ['list', 'packages', pkg]);
        if (result.stdout.toString().contains(pkg)) {
          if (kDebugMode) debugPrint('RootDetector: Root-App gefunden: $pkg');
          return RootStatus.rooted;
        }
      } catch (_) {}
    }

    // 3. Emulator-Detection via Build-Properties
    final isEmulator = await _isEmulator();
    if (isEmulator) return RootStatus.emulator;

    // 4. Debugger-Check via /proc/self/status
    final isTraced = await _isTraced();
    if (isTraced) {
      if (kDebugMode) debugPrint('RootDetector: Debugger angehaengt (TracerPid != 0)');
      return RootStatus.debuggerAttached;
    }

    return RootStatus.clean;
  }

  static Future<bool> _isEmulator() async {
    try {
      // Android-Build-Properties die auf Emulator hinweisen
      final result = await Process.run('getprop', ['ro.product.model']);
      final model = result.stdout.toString().toLowerCase();
      final emulatorHints = ['sdk', 'emulator', 'android sdk', 'generic'];
      if (emulatorHints.any((h) => model.contains(h))) return true;

      final brandResult = await Process.run('getprop', ['ro.product.brand']);
      final brand = brandResult.stdout.toString().toLowerCase().trim();
      if (brand == 'generic' || brand == 'android') return true;
    } catch (_) {}
    return false;
  }

  static Future<bool> _isTraced() async {
    try {
      final status = await File('/proc/self/status').readAsString();
      final match = RegExp(r'TracerPid:\s*(\d+)').firstMatch(status);
      final pid = int.tryParse(match?.group(1) ?? '0') ?? 0;
      return pid != 0;
    } catch (_) {}
    return false;
  }
}

enum RootStatus {
  clean,
  rooted,
  emulator,
  debuggerAttached;

  bool get isClean => this == RootStatus.clean;
  bool get requiresWarning => !isClean;

  String get userMessage {
    switch (this) {
      case RootStatus.rooted:
        return 'Sicherheitshinweis: Dieses Geraet scheint gerootet zu sein. '
            'Deine Suchdaten koennen von anderen Apps gelesen werden. '
            'Fuer maximalen Schutz empfehlen wir ein nicht gerootetes Geraet.';
      case RootStatus.emulator:
        return 'Hinweis: FindUX laeuft auf einem Emulator. '
            'Der Hardware-Schluessel-Schutz ist auf Emulatoren eingeschraenkt.';
      case RootStatus.debuggerAttached:
        return 'Sicherheitshinweis: Ein Debugger ist aktiv. '
            'FindUX ist im eingeschraenkten Modus.';
      case RootStatus.clean:
        return '';
    }
  }
}
