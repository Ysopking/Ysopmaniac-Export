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
  'aber', 'alle', 'alles', 'als', 'also', 'auch', 'auf', 'aus', 'bei', 'bin',
  'bist', 'dann', 'das', 'dass', 'dein', 'deine', 'dem', 'den', 'denn',
  'der', 'des', 'die', 'diese', 'dieser', 'dieses', 'doch', 'durch', 'ein',
  'eine', 'einem', 'einen', 'einer', 'eines', 'einige', 'euch', 'euer',
  'eure', 'falls', 'fuer', 'für', 'gegen', 'haben', 'hat', 'hatte', 'hatten',
  'ihm', 'ihn', 'ihnen', 'ihr', 'ihre', 'immer', 'ist', 'jede', 'jeder',
  'jedes', 'jene', 'jener', 'jenes', 'kann', 'kein', 'keine', 'koennen',
  'können', 'man', 'mehr', 'mein', 'meine', 'mit', 'muessen', 'muss',
  'müssen', 'nach', 'nicht', 'nie', 'noch', 'nur', 'ob', 'oder', 'ohne',
  'schon', 'sehr', 'seid', 'sein', 'seine', 'sich', 'sie', 'sind', 'soll',
  'sollen', 'sondern', 'ueber', 'und', 'uns', 'unser', 'unsere', 'unter',
  'von', 'vor', 'wann', 'war', 'waren', 'warum', 'was', 'weil', 'welche',
  'welcher', 'welches', 'wenn', 'wer', 'werden', 'wie', 'wieso', 'wir',
  'wird', 'wo', 'woher', 'wohin', 'wurde', 'wurden', 'zu', 'zum', 'zur',
  'über',
};

const Set<String> kStopwordsEn = {
  'a', 'about', 'after', 'against', 'all', 'also', 'am', 'an', 'and', 'any',
  'are', 'be', 'because', 'been', 'before', 'being', 'between', 'but', 'can',
  'could', 'did', 'do', 'does', 'each', 'every', 'from', 'had', 'has',
  'have', 'he', 'her', 'him', 'his', 'how', 'i', 'if', 'into', 'is', 'it',
  'its', 'just', 'many', 'may', 'me', 'might', 'mine', 'most', 'much', 'my',
  'no', 'not', 'only', 'onto', 'or', 'our', 'over', 'she', 'should', 'so',
  'some', 'such', 'than', 'that', 'the', 'their', 'them', 'then', 'these',
  'they', 'this', 'those', 'through', 'under', 'us', 'very', 'was', 'we',
  'were', 'what', 'when', 'where', 'which', 'while', 'who', 'whom', 'whose',
  'why', 'will', 'with', 'would', 'you', 'your', 'yours',
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
