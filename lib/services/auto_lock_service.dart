import 'dart:async';

import 'package:flutter/widgets.dart';

/// Beobachtet den App-Lifecycle fuer zwei Sicherheitszwecke:
///
/// 1. SOFORT-SPERRE bei resumed (Lücke 1):
///    Wenn die Session bereits als "abgelaufen" markiert ist
///    (d.h. [onLock] wurde durch den Timer ausgeloest), wird beim
///    naechsten resumed [onLock] nicht nochmal gerufen — er wurde
///    bereits gerufen. Der UnlockScreen ist dann schon aktiv.
///
///    ABER: Wenn die App in < timeout resumet, prueft [onResume]
///    ob die Session noch gueltig ist. Der Aufrufer kann optional
///    [onResume] nutzen um sofort eine Re-Auth zu erzwingen.
///
/// 2. TIMER-SPERRE nach [timeout] im Hintergrund (bisheriges Verhalten):
///    Unveraendert: nach 60 Sekunden paused -> [onLock].
///
/// Wichtig: [onResume] wird bei JEDEM resumed aufgerufen (auch ohne Timeout).
/// Der Aufrufer entscheidet selbst ob eine Re-Auth noetig ist.
class AutoLockObserver with WidgetsBindingObserver {
  AutoLockObserver({
    required this.onLock,
    this.onResume,
    this.timeout = const Duration(seconds: 60),
  });

  final VoidCallback onLock;

  /// Wird bei JEDEM Foreground-Wechsel aufgerufen (resumed).
  /// Kann genutzt werden um sofort eine Re-Auth-Pruefung auszuloesen,
  /// BEVOR der Lock-Timer abgelaufen ist.
  final VoidCallback? onResume;

  final Duration timeout;

  Timer? _pendingLock;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    _pendingLock?.cancel();
    _pendingLock = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pendingLock?.cancel();
        _pendingLock = Timer(timeout, () {
          _pendingLock = null;
          onLock();
        });
        break;
      case AppLifecycleState.resumed:
        // Timer-Countdown abbrechen (User zurueck innerhalb timeout).
        _pendingLock?.cancel();
        _pendingLock = null;
        // Immer onResume signalisieren — main.dart entscheidet ob Re-Auth noetig.
        onResume?.call();
        break;
      case AppLifecycleState.inactive:
        // Uebergangszustand (z.B. Permission-Dialog), kein Reset.
        break;
    }
  }
}
