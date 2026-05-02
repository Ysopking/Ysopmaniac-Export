import 'package:flutter/services.dart';

/// Zentrale Haptik-Helper im Apple-Stil.
/// - [tap]   = leichter Tap (Default fuer alle Buttons / Tiles)
/// - [pick]  = Auswahl-Wechsel (Picker, Chips, Toggles)
/// - [done]  = positiver Erfolg (Speichern, Import-OK)
/// - [warn]  = leichter Warnimpuls (Validation-Fehler)
///
/// Apple verwendet auf praktisch jedem getappten Element einen
/// dezenten haptischen Impuls. Das macht eine App spuerbar "echt".
/// Wir wrappen die Methoden, damit ein Austausch (z.B. plattform-
/// spezifische Feinabstimmung) zentral moeglich ist.
class Haptics {
  static Future<void> tap() => HapticFeedback.lightImpact();
  static Future<void> pick() => HapticFeedback.selectionClick();
  static Future<void> done() => HapticFeedback.mediumImpact();
  static Future<void> warn() => HapticFeedback.heavyImpact();
}
