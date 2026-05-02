import '../utils/findux_stopwords.dart';

/// Heuristische Vagheits-Erkennung.
///
/// Eine Suche gilt als vage, wenn sie ohne Coach voraussichtlich
/// schlechte Resultate liefert:
///   - WAS hat <= 2 Inhaltswoerter UND
///   - WARUM ist leer ODER sehr kurz UND
///   - WAS enthaelt keine spezifischen Marker (Zahlen, Eigennamen,
///     Bindestrich-Begriffe, Anfuehrungszeichen-Phrasen)
class VaguenessDetector {
  static bool isVague({required String what, required String why, String language = 'de'}) {
    final whatTrim = what.trim();
    if (whatTrim.isEmpty) return false; // leerer Input -> nicht "vage", nur leer

    // Schon manuell gequotet? -> User weiss was er will
    if (whatTrim.contains('"')) return false;

    // Enthaelt eine Zahl (Modell-Nr, Jahr, Versionsnummer)? -> spezifisch
    if (RegExp(r'\d').hasMatch(whatTrim)) return false;

    // Enthaelt einen Bindestrich-Begriff (z.B. "lithium-ionen")? -> spezifisch
    if (RegExp(r'\w-\w').hasMatch(whatTrim)) return false;

    // Inhaltswoerter im WAS zaehlen
    final stop = stopwordsForLanguage(language);
    final whatTokens = whatTrim
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !stop.contains(t))
        .toList();
    if (whatTokens.length >= 4) return false;

    // WARUM-Inhaltsworte zaehlen
    final whyTokens = why
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !stop.contains(t))
        .toList();

    // Vage = wenig WAS UND wenig/kein WARUM
    return whatTokens.length <= 2 && whyTokens.length <= 1;
  }
}
