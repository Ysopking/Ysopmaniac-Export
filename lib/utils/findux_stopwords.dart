/// Geteilte Stoppwoerter fuer FindUX.
///
/// Wird von query_builder.dart und learning_service.dart genutzt, damit
/// beide Komponenten dieselben Begriffe ignorieren. Die Sets sind sprach-
/// getrennt (DE/EN) — die Auswahl erfolgt anhand der User-Sprache.
///
/// WICHTIG: Beide Sets MUESSEN frei von Duplikaten sein, sonst schlaegt
/// die Const-Evaluation in Dart fehl ("element conflicts with another
/// existing element in the set").
library;

const Set<String> kStopwordsDe = {
  // Artikel + Pronomen
  'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem',
  'einer', 'eines', 'sie', 'ihm', 'ihn', 'ihnen', 'wir', 'uns', 'unser',
  'unsere', 'euch', 'euer', 'eure', 'mein', 'meine', 'dein', 'deine',
  'sein', 'seine', 'ihr', 'ihre', 'man',
  // Konjunktionen + Praepositionen
  'und', 'oder', 'aber', 'doch', 'sondern', 'denn', 'weil', 'wenn', 'dann',
  'also', 'noch', 'nur', 'auch', 'als', 'ob', 'falls',
  'mit', 'von', 'zu', 'zum', 'zur', 'auf', 'fuer', 'für', 'aus', 'bei',
  'nach', 'ueber', 'über', 'unter', 'vor', 'durch', 'gegen', 'ohne',
  // Verben
  'ist', 'bin', 'bist', 'sind', 'seid', 'war', 'waren', 'wird', 'werden',
  'wurde', 'wurden', 'haben', 'hat', 'hatte', 'hatten', 'sich',
  'kann', 'koennen', 'können', 'soll', 'sollen', 'muss', 'muessen', 'müssen',
  // W-Fragen
  'wie', 'was', 'wer', 'wo', 'wann', 'warum', 'wieso', 'welche', 'welcher',
  'welches', 'wohin', 'woher',
  // Demonstrativ + Quantoren
  'dass', 'dieser', 'diese', 'dieses', 'jener', 'jene', 'jenes',
  'alle', 'alles', 'jeder', 'jede', 'jedes', 'kein', 'keine', 'einige',
  'mehr', 'sehr', 'schon', 'immer', 'nie', 'nicht', 'kein',
};

const Set<String> kStopwordsEn = {
  'the', 'a', 'an', 'and', 'or', 'but', 'so', 'because', 'if', 'when',
  'while', 'than', 'then', 'this', 'that', 'these', 'those',
  'with', 'from', 'into', 'onto', 'about', 'over', 'under', 'after',
  'before', 'against', 'between', 'through',
  'is', 'am', 'are', 'was', 'were', 'be', 'been', 'being', 'do', 'does',
  'did', 'have', 'has', 'had', 'will', 'would', 'could', 'should', 'may',
  'might', 'can',
  'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us',
  'them', 'my', 'your', 'his', 'its', 'our', 'their', 'mine', 'yours',
  'what', 'which', 'who', 'whom', 'whose', 'why', 'how', 'where', 'when',
  'all', 'any', 'every', 'each', 'no', 'not', 'only', 'just', 'also',
  'very', 'much', 'many', 'most', 'some', 'such',
};

/// Gibt das passende Stopwort-Set fuer eine Sprach-Auswahl zurueck.
/// Bei unbekannter Sprache: Vereinigung aus DE+EN (defensiv).
Set<String> stopwordsForLanguage(String lang) {
  switch (lang) {
    case 'de':
      return kStopwordsDe;
    case 'en':
      return kStopwordsEn;
    default:
      return {...kStopwordsDe, ...kStopwordsEn};
  }
}
