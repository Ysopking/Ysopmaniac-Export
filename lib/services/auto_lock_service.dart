import 'dart:async';

import 'package:flutter/widgets.dart';

/// Beobachtet den App-Lifecycle und ruft [onLock] auf, wenn die App
/// laenger als [timeout] im Hintergrund war (Stage F: 60 Sekunden).
///
/// Wir setzen NICHT direkt sofort beim ersten `paused` zurueck — der User
/// koennte nur kurz das Notification-Center pruefen. Erst nach Ablauf
/// des Timers ist die Sitzung verfallen.
class AutoLockObserver with WidgetsBindingObserver {
  AutoLockObserver({
    required this.onLock,
    this.timeout = const Duration(seconds: 60),
  });

  final VoidCallback onLock;
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
        // User ist zurueck — laufenden Lock-Countdown abbrechen.
        _pendingLock?.cancel();
        _pendingLock = null;
        break;
      case AppLifecycleState.inactive:
        // Uebergangszustand (z.B. Permission-Dialog), kein Reset.
        break;
    }
  }
}
