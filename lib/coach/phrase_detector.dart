/// Erkennt feste Mehrwort-Phrasen und setzt sie automatisch in
/// Anfuehrungszeichen, damit Google sie als Einheit behandelt.
///
/// Komplett offline — keine API. Liste ist hartkodiert + erweiterbar.
class PhraseDetector {
  static const List<String> _knownPhrases = [
    // Tech / IT
    'machine learning', 'deep learning', 'künstliche intelligenz',
    'kuenstliche intelligenz', 'large language model', 'natural language processing',
    'cloud computing', 'edge computing',
    // Medizin
    'multiple sklerose', 'morbus crohn', 'reizdarm syndrom',
    'chronische schmerzen', 'systematic review', 'meta analyse',
    // Recht
    'bürgerliches gesetzbuch', 'buergerliches gesetzbuch', 'grundgesetz',
    'arbeitsrecht', 'mietrecht', 'strafgesetzbuch',
    // Wirtschaft / Finanzen
    'gesetzliche rentenversicherung', 'private krankenversicherung',
    'einkommensteuererklärung', 'einkommensteuererklaerung',
    'kapitalertragsteuer',
    // Wissenschaft
    'climate change', 'klimawandel folgen', 'erneuerbare energien',
  ];

  /// Erkennt bekannte Phrasen im Text und setzt sie in Quotes.
  /// Nicht-bekannte Phrasen bleiben unveraendert.
  static String autoQuote(String text) {
    if (text.isEmpty || text.contains('"')) return text;
    final lower = text.toLowerCase();
    String result = text;
    for (final phrase in _knownPhrases) {
      final idx = lower.indexOf(phrase);
      if (idx >= 0) {
        // Original-Casing aus result extrahieren
        final original = result.substring(idx, idx + phrase.length);
        result = result.replaceFirst(original, '"$original"');
        // nur die erste Phrase quoten — verhindert Mehrfach-Quotes
        return result;
      }
    }
    // Heuristik: "Marke Modell-Nummer" -> quoten
    // z.B. "iphone 14", "galaxy s23"
    final m = RegExp(r'^([A-Za-zäöüÄÖÜß]+)\s+([A-Za-z0-9]+)$').firstMatch(text.trim());
    if (m != null && RegExp(r'\d').hasMatch(m.group(2)!)) {
      return '"${text.trim()}"';
    }
    return result;
  }
}
