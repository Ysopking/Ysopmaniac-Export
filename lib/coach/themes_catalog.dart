import 'coach_models.dart';

/// Katalog der 12 Coach-Themen mit Trigger-Woertern, Dimensionen und Chips.
///
/// Jedes Thema hat 3-4 Dimensionen, jede Dimension 4-6 Chips.
/// Chips bauen direkt sinnvolle Operatoren (site:, intitle:, after:, ...).
class ThemesCatalog {
  static List<CoachTheme> get all => [
        _technik,
        _software,
        _gesundheit,
        _recht,
        _einkauf,
        _reise,
        _ausbildung,
        _job,
        _finanzen,
        _wohnen,
        _hobby,
        _allgemein,
      ];

  static CoachTheme? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ============ Helper ============
  static CoachChip _c(String id, String label, ChipKind kind, String value,
          [String emoji = '']) =>
      CoachChip(id: id, label: label, emoji: emoji, kind: kind, value: value);

  // ============ 1. Technik ============
  static final _technik = CoachTheme(
    id: 'technik',
    label: 'Technik & Geräte',
    emoji: '📱',
    triggerWords: const [
      'laptop','handy','smartphone','tablet','drucker','akku','router',
      'monitor','tastatur','maus','kopfhoerer','kopfhörer','kamera','tv',
      'fernseher','lautsprecher','smartwatch','konsole','geraet','gerät',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was willst du erreichen?', chips: [
        _c('kaufen', 'Kaufen', ChipKind.term, 'kaufen test vergleich', '🛒'),
        _c('reparieren', 'Reparieren', ChipKind.term, 'reparieren anleitung', '🔧'),
        _c('vergleich', 'Vergleichen', ChipKind.term, 'vergleich test', '⚖️'),
        _c('anleitung', 'Anleitung', ChipKind.intitle, 'anleitung', '📖'),
        _c('beschwerde', 'Beschwerde', ChipKind.term, 'erfahrungen probleme', '😤'),
      ]),
      CoachDimension(id: 'alter', question: 'Wie alt ist das Gerät?', chips: [
        _c('neu', 'Neu / Aktuell', ChipKind.after, '180', '🆕'),
        _c('1_3', '1–3 Jahre', ChipKind.after, '1095', '⏳'),
        _c('alt', '4+ Jahre', ChipKind.term, '', '📦'),
        _c('egal', 'Egal', ChipKind.term, '', '🤷'),
      ], multiSelect: false, allowCustom: false),
      CoachDimension(id: 'quelle', question: 'Welche Quelle bevorzugst du?', chips: [
        _c('hersteller', 'Hersteller', ChipKind.term, 'official', '🏢'),
        _c('reddit', 'Reddit', ChipKind.site, 'reddit.com', '🟠'),
        _c('test', 'Test-Magazin', ChipKind.site, 'chip.de OR site:computerbild.de OR site:heise.de', '📰'),
        _c('youtube', 'YouTube-Review', ChipKind.site, 'youtube.com', '🎥'),
        _c('forum', 'Forum', ChipKind.site, 'gutefrage.net OR site:stackoverflow.com', '💬'),
      ], multiSelect: true),
    ],
  );

  // ============ 2. Software & Code ============
  static final _software = CoachTheme(
    id: 'software',
    label: 'Software & Code',
    emoji: '💻',
    triggerWords: const [
      'app','software','programm','code','python','javascript','java','flutter',
      'react','sql','linux','windows','macos','docker','git','github','fehler',
      'error','bug','install','installieren','update','treiber',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was brauchst du?', chips: [
        _c('fix', 'Fehler beheben', ChipKind.term, 'fix solution', '🔧'),
        _c('lernen', 'Tutorial', ChipKind.intitle, 'tutorial', '📚'),
        _c('beispiel', 'Code-Beispiel', ChipKind.term, 'example code', '🧩'),
        _c('install', 'Installation', ChipKind.intitle, 'install', '⚙️'),
        _c('vergleich', 'Vergleich', ChipKind.term, 'vs versus comparison', '⚖️'),
      ]),
      CoachDimension(id: 'quelle', question: 'Beste Quelle?', chips: [
        _c('so', 'StackOverflow', ChipKind.site, 'stackoverflow.com', '📚'),
        _c('github', 'GitHub', ChipKind.site, 'github.com', '🐙'),
        _c('mdn', 'MDN Docs', ChipKind.site, 'developer.mozilla.org', '🦊'),
        _c('docs', 'Offizielle Docs', ChipKind.site, 'docs.python.org OR site:docs.flutter.dev', '📖'),
        _c('reddit', 'Reddit', ChipKind.site, 'reddit.com', '🟠'),
      ], multiSelect: true),
      CoachDimension(id: 'aktualitaet', question: 'Wie aktuell?', chips: [
        _c('latest', 'Neueste Version (1 Jahr)', ChipKind.after, '365', '🆕'),
        _c('recent', '3 Jahre', ChipKind.after, '1095', '⏳'),
        _c('any', 'Alle Zeit', ChipKind.term, '', '🌐'),
      ], allowCustom: false),
      CoachDimension(id: 'tiefe', question: 'Tiefe?', chips: [
        _c('quick', 'Schnellantwort', ChipKind.mode, 'precise', '⚡'),
        _c('deep', 'Ausführlich', ChipKind.mode, 'standard', '🔍'),
        _c('explore', 'Stöbern', ChipKind.mode, 'discover', '🧭'),
      ], allowCustom: false),
    ],
  );

  // ============ 3. Gesundheit ============
  static final _gesundheit = CoachTheme(
    id: 'gesundheit',
    label: 'Gesundheit & Medizin',
    emoji: '🩺',
    triggerWords: const [
      'schmerz','schmerzen','muede','müde','symptom','symptome','arzt','aerzt',
      'krankheit','krank','therapie','medikament','medikamente','behandlung',
      'diagnose','blut','herz','kopf','ruecken','rücken','allergie',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Wonach suchst du?', chips: [
        _c('ursache', 'Ursache verstehen', ChipKind.term, 'ursache', '❓'),
        _c('therapie', 'Therapie / Behandlung', ChipKind.term, 'behandlung therapie', '💊'),
        _c('erfahrung', 'Erfahrungen anderer', ChipKind.site, 'reddit.com OR site:gutefrage.net', '👥'),
        _c('arzt', 'Arzt finden', ChipKind.term, 'arzt termin', '👨‍⚕️'),
        _c('definition', 'Definition', ChipKind.intitle, 'was ist', '📖'),
      ]),
      CoachDimension(id: 'quelle', question: 'Wem vertraust du?', chips: [
        _c('offiziell', 'RKI / WHO / Fachgesellschaft', ChipKind.site, 'rki.de OR site:who.int OR site:awmf.org', '🏛️'),
        _c('apotheke', 'Apotheken-Portal', ChipKind.site, 'apotheken-umschau.de OR site:netdoktor.de', '💊'),
        _c('klinik', 'Klinik / Uniklinikum', ChipKind.site, 'charite.de OR site:klinikum.uni-heidelberg.de', '🏥'),
        _c('paper', 'Wissenschaft', ChipKind.site, 'pubmed.ncbi.nlm.nih.gov OR site:cochrane.org', '🔬'),
        _c('forum', 'Patienten-Forum', ChipKind.site, 'med1.de OR site:reddit.com', '💬'),
      ], multiSelect: true),
      CoachDimension(id: 'aktualitaet', question: 'Wie aktuell?', chips: [
        _c('news', 'Neueste Studien (2 Jahre)', ChipKind.after, '730', '📅'),
        _c('etabliert', 'Etablierte Erkenntnisse', ChipKind.term, '', '📚'),
      ], allowCustom: false),
    ],
  );

  // ============ 4. Recht & Behoerde ============
  static final _recht = CoachTheme(
    id: 'recht',
    label: 'Recht & Behörde',
    emoji: '⚖️',
    triggerWords: const [
      'vertrag','kuendigung','kündigung','antrag','gesetz','paragraph','urteil',
      'klage','behoerde','behörde','amt','steuer','recht','rechtlich','anwalt',
      'mietrecht','arbeitsrecht','strafrecht',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Wonach suchst du?', chips: [
        _c('gesetz', 'Gesetzestext', ChipKind.site, 'gesetze-im-internet.de OR site:dejure.org', '📜'),
        _c('urteil', 'Urteil / Rechtsprechung', ChipKind.site, 'bgh.de OR site:bverfg.de OR site:openjur.de', '⚖️'),
        _c('beispiel', 'Praxis-Beispiel', ChipKind.term, 'beispiel muster', '📝'),
        _c('beratung', 'Beratung', ChipKind.term, 'anwalt beratung', '👨‍⚖️'),
        _c('formular', 'Formular / Antrag', ChipKind.term, 'formular pdf', '📄'),
      ]),
      CoachDimension(id: 'gebiet', question: 'Welches Land?', chips: [
        _c('de', 'Deutschland', ChipKind.term, 'Deutschland', '🇩🇪'),
        _c('at', 'Österreich', ChipKind.term, 'Österreich', '🇦🇹'),
        _c('ch', 'Schweiz', ChipKind.term, 'Schweiz', '🇨🇭'),
        _c('eu', 'EU-weit', ChipKind.term, 'EU Europa', '🇪🇺'),
      ], allowCustom: false),
      CoachDimension(id: 'quelle', question: 'Wem vertraust du?', chips: [
        _c('offiziell', 'Behörde', ChipKind.site, 'bund.de OR site:bmj.de', '🏛️'),
        _c('kanzlei', 'Anwaltskanzlei', ChipKind.site, 'anwalt.de OR site:rechtsanwalt.com', '👨‍⚖️'),
        _c('verbraucher', 'Verbraucherzentrale', ChipKind.site, 'verbraucherzentrale.de', '🛡️'),
      ], multiSelect: true),
    ],
  );

  // ============ 5. Einkauf ============
  static final _einkauf = CoachTheme(
    id: 'einkauf',
    label: 'Einkauf & Produkt',
    emoji: '🛒',
    triggerWords: const [
      'kaufen','preis','vergleich','test','rabatt','gutschein','angebot',
      'guenstig','günstig','shop','bestellen','versand','produkt','marke',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was suchst du?', chips: [
        _c('preisvgl', 'Preisvergleich', ChipKind.site, 'idealo.de OR site:geizhals.de OR site:check24.de', '💰'),
        _c('test', 'Testberichte', ChipKind.intitle, 'test', '⭐'),
        _c('erfahrung', 'Erfahrungsberichte', ChipKind.term, 'erfahrungen bewertung', '👥'),
        _c('gutschein', 'Gutschein / Rabatt', ChipKind.term, 'gutschein code rabatt', '🎟️'),
        _c('alternative', 'Alternative', ChipKind.term, 'alternative vergleich', '🔄'),
      ]),
      CoachDimension(id: 'zustand', question: 'Neu oder gebraucht?', chips: [
        _c('neu', 'Neu', ChipKind.term, 'neu', '🆕'),
        _c('gebraucht', 'Gebraucht', ChipKind.site, 'ebay-kleinanzeigen.de OR site:ebay.de', '♻️'),
        _c('refurbished', 'Refurbished', ChipKind.term, 'refurbished generalueberholt', '🔄'),
        _c('egal', 'Egal', ChipKind.term, '', '🤷'),
      ], allowCustom: false),
      CoachDimension(id: 'quelle', question: 'Welcher Shop?', chips: [
        _c('amazon', 'Amazon', ChipKind.site, 'amazon.de', '📦'),
        _c('otto', 'Otto', ChipKind.site, 'otto.de', '🟥'),
        _c('mediamarkt', 'MediaMarkt', ChipKind.site, 'mediamarkt.de OR site:saturn.de', '📺'),
        _c('lokal', 'Lokal', ChipKind.term, 'in der naehe', '📍'),
      ], multiSelect: true),
    ],
  );

  // ============ 6. Reise ============
  static final _reise = CoachTheme(
    id: 'reise',
    label: 'Reise & Urlaub',
    emoji: '✈️',
    triggerWords: const [
      'reise','urlaub','hotel','flug','flugticket','bahn','zug','route',
      'sehenswuerdigkeit','sehenswürdigkeit','strand','wandern','camping',
      'reisefuehrer','reiseführer',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was planst du?', chips: [
        _c('hotel', 'Hotel', ChipKind.site, 'booking.com OR site:hrs.de', '🏨'),
        _c('flug', 'Flug', ChipKind.site, 'skyscanner.de OR site:google.com/flights', '✈️'),
        _c('aktivitaet', 'Aktivitäten', ChipKind.term, 'sehenswuerdigkeiten aktivitaeten', '🎯'),
        _c('rundreise', 'Rundreise / Route', ChipKind.term, 'route rundreise', '🗺️'),
        _c('tipps', 'Insider-Tipps', ChipKind.site, 'reddit.com OR site:tripadvisor.com', '💡'),
      ]),
      CoachDimension(id: 'budget', question: 'Budget-Klasse?', chips: [
        _c('budget', 'Sparsam', ChipKind.term, 'guenstig backpacker', '💸'),
        _c('mid', 'Mittelklasse', ChipKind.term, '', '💰'),
        _c('luxus', 'Luxus', ChipKind.term, 'luxus boutique', '💎'),
      ], allowCustom: false),
      CoachDimension(id: 'aktualitaet', question: 'Wie aktuell?', chips: [
        _c('jetzt', 'Aktuelle Reisehinweise', ChipKind.after, '180', '📅'),
        _c('jahr', 'Letzte 12 Monate', ChipKind.after, '365', '⏳'),
        _c('egal', 'Egal', ChipKind.term, '', '🤷'),
      ], allowCustom: false),
    ],
  );

  // ============ 7. Ausbildung ============
  static final _ausbildung = CoachTheme(
    id: 'ausbildung',
    label: 'Ausbildung & Lernen',
    emoji: '🎓',
    triggerWords: const [
      'lernen','studium','studieren','kurs','seminar','pruefung','prüfung',
      'klausur','schule','universitaet','universität','uni','ausbildung',
      'fortbildung','weiterbildung','tutorial',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was brauchst du?', chips: [
        _c('erklaerung', 'Erklärung', ChipKind.intitle, 'erklaerung', '💡'),
        _c('uebung', 'Übungsaufgaben', ChipKind.term, 'uebungen aufgaben', '✏️'),
        _c('zusammenfassung', 'Zusammenfassung', ChipKind.intitle, 'zusammenfassung', '📋'),
        _c('video', 'Video-Tutorial', ChipKind.site, 'youtube.com', '🎥'),
        _c('paper', 'Wissenschaftliche Quelle', ChipKind.site, 'scholar.google.com OR site:arxiv.org', '🔬'),
      ]),
      CoachDimension(id: 'niveau', question: 'Welches Niveau?', chips: [
        _c('schule', 'Schule', ChipKind.term, 'schule abitur', '🏫'),
        _c('bachelor', 'Bachelor', ChipKind.term, 'bachelor studium', '📚'),
        _c('master', 'Master', ChipKind.term, 'master phd', '🎓'),
        _c('beruf', 'Berufliche Weiterbildung', ChipKind.term, 'weiterbildung berufsschule', '💼'),
      ], allowCustom: false),
      CoachDimension(id: 'sprache', question: 'Sprache?', chips: [
        _c('de', 'Deutsch', ChipKind.term, '', '🇩🇪'),
        _c('en', 'Englisch', ChipKind.term, 'english', '🇬🇧'),
        _c('beides', 'Beides', ChipKind.term, '', '🌐'),
      ], allowCustom: false),
    ],
  );

  // ============ 8. Job ============
  static final _job = CoachTheme(
    id: 'job',
    label: 'Job & Karriere',
    emoji: '💼',
    triggerWords: const [
      'job','jobs','bewerbung','lebenslauf','cv','gehalt','stelle','karriere',
      'arbeitgeber','vorstellung','vorstellungsgespraech','vorstellungsgespräch',
      'beruf','beruflich',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was brauchst du?', chips: [
        _c('stellen', 'Stellenanzeigen', ChipKind.site, 'indeed.com OR site:stepstone.de OR site:linkedin.com', '🔍'),
        _c('bewerbung', 'Bewerbung schreiben', ChipKind.term, 'anschreiben muster', '📝'),
        _c('gehalt', 'Gehalts-Info', ChipKind.site, 'kununu.com OR site:gehalt.de', '💰'),
        _c('arbeitgeber', 'Arbeitgeber-Bewertung', ChipKind.site, 'kununu.com OR site:glassdoor.de', '⭐'),
        _c('interview', 'Vorstellungsgespräch', ChipKind.term, 'vorstellungsgespraech tipps', '🤝'),
      ]),
      CoachDimension(id: 'modell', question: 'Arbeitsmodell?', chips: [
        _c('vollzeit', 'Vollzeit', ChipKind.term, 'vollzeit', '🕐'),
        _c('teilzeit', 'Teilzeit', ChipKind.term, 'teilzeit', '⏰'),
        _c('remote', 'Remote', ChipKind.term, 'remote home office', '🏠'),
        _c('werkstudent', 'Werkstudent / Praktikum', ChipKind.term, 'werkstudent praktikum', '🎓'),
      ], allowCustom: false),
      CoachDimension(id: 'aktualitaet', question: 'Aktualität?', chips: [
        _c('neu', 'Letzte 2 Wochen', ChipKind.after, '14', '🆕'),
        _c('monat', 'Letzter Monat', ChipKind.after, '30', '📅'),
        _c('egal', 'Egal', ChipKind.term, '', '🤷'),
      ], allowCustom: false),
    ],
  );

  // ============ 9. Finanzen ============
  static final _finanzen = CoachTheme(
    id: 'finanzen',
    label: 'Finanzen & Steuer',
    emoji: '💰',
    triggerWords: const [
      'steuer','kredit','rente','versicherung','konto','bank','sparen',
      'aktien','etf','depot','finanzen','geld','zins','zinsen','inflation',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was brauchst du?', chips: [
        _c('vergleich', 'Vergleich', ChipKind.site, 'check24.de OR site:verivox.de OR site:finanztip.de', '⚖️'),
        _c('erklaerung', 'Erklärung', ChipKind.intitle, 'erklaert einfach', '💡'),
        _c('formular', 'Formular / Antrag', ChipKind.term, 'formular pdf', '📄'),
        _c('rechner', 'Rechner', ChipKind.intitle, 'rechner', '🧮'),
        _c('tipp', 'Spar-Tipp', ChipKind.term, 'tipps tricks', '💡'),
      ]),
      CoachDimension(id: 'quelle', question: 'Welche Quelle?', chips: [
        _c('finanztip', 'Finanztip', ChipKind.site, 'finanztip.de', '🟢'),
        _c('stiftung', 'Stiftung Warentest', ChipKind.site, 'test.de', '🛡️'),
        _c('offiziell', 'Behörde / BMF', ChipKind.site, 'bundesfinanzministerium.de OR site:elster.de', '🏛️'),
        _c('forum', 'Forum', ChipKind.site, 'reddit.com/r/Finanzen', '💬'),
      ], multiSelect: true),
      CoachDimension(id: 'aktualitaet', question: 'Aktualität?', chips: [
        _c('aktuell', 'Aktuelles Steuerjahr', ChipKind.after, '365', '📅'),
        _c('etabliert', 'Etabliert', ChipKind.term, '', '📚'),
      ], allowCustom: false),
    ],
  );

  // ============ 10. Wohnen ============
  static final _wohnen = CoachTheme(
    id: 'wohnen',
    label: 'Wohnen & Haushalt',
    emoji: '🏠',
    triggerWords: const [
      'wohnung','miete','vermieter','mietvertrag','reparatur','renovieren',
      'streichen','umzug','moebel','möbel','garten','pflanze','schimmel',
      'heizung','strom','gas',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was suchst du?', chips: [
        _c('anleitung', 'DIY-Anleitung', ChipKind.intitle, 'anleitung diy', '🔨'),
        _c('vergleich', 'Produkt-Vergleich', ChipKind.term, 'test vergleich', '⚖️'),
        _c('recht', 'Mietrecht', ChipKind.site, 'mieterbund.de OR site:mietrecht.org', '⚖️'),
        _c('inspiration', 'Inspiration', ChipKind.site, 'pinterest.com OR site:houzz.de', '✨'),
        _c('handwerker', 'Handwerker finden', ChipKind.term, 'handwerker in der naehe', '🔧'),
      ]),
      CoachDimension(id: 'umfang', question: 'Umfang?', chips: [
        _c('klein', 'Schnell-Lösung', ChipKind.term, 'schnell einfach', '⚡'),
        _c('gross', 'Größeres Projekt', ChipKind.term, 'projekt komplett', '🏗️'),
        _c('profi', 'Profi-Hilfe', ChipKind.term, 'firma handwerker', '👷'),
      ], allowCustom: false),
    ],
  );

  // ============ 11. Hobby ============
  static final _hobby = CoachTheme(
    id: 'hobby',
    label: 'Hobby & Freizeit',
    emoji: '🎨',
    triggerWords: const [
      'rezept','kochen','backen','sport','training','fitness','spiel',
      'spiele','basteln','malen','musik','film','serie','buch','buecher','bücher',
    ],
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Was suchst du?', chips: [
        _c('anleitung', 'Anleitung', ChipKind.intitle, 'anleitung', '📖'),
        _c('inspiration', 'Inspiration', ChipKind.term, 'ideen inspiration', '✨'),
        _c('empfehlung', 'Empfehlung', ChipKind.term, 'beste top empfehlung', '⭐'),
        _c('community', 'Community', ChipKind.site, 'reddit.com', '👥'),
        _c('video', 'Video-Anleitung', ChipKind.site, 'youtube.com', '🎥'),
      ]),
      CoachDimension(id: 'level', question: 'Level?', chips: [
        _c('anfaenger', 'Anfänger', ChipKind.term, 'anfaenger einfach', '🌱'),
        _c('fortgeschritten', 'Fortgeschritten', ChipKind.term, 'fortgeschritten', '🌿'),
        _c('profi', 'Profi', ChipKind.term, 'profi advanced', '🌳'),
      ], allowCustom: false),
    ],
  );

  // ============ 12. Allgemein (Fallback) ============
  static final _allgemein = CoachTheme(
    id: 'allgemein',
    label: 'Allgemein',
    emoji: '🔍',
    triggerWords: const [], // matched only as fallback
    dimensions: [
      CoachDimension(id: 'ziel', question: 'Worum geht es genau?', chips: [
        _c('definition', 'Definition / Was ist…', ChipKind.intitle, 'was ist', '📖'),
        _c('anleitung', 'Anleitung / How-To', ChipKind.intitle, 'anleitung how to', '📋'),
        _c('vergleich', 'Vergleich', ChipKind.term, 'vergleich vs', '⚖️'),
        _c('erfahrung', 'Erfahrung anderer', ChipKind.site, 'reddit.com OR site:gutefrage.net', '👥'),
        _c('news', 'Aktuelle Nachrichten', ChipKind.after, '90', '📰'),
      ]),
      CoachDimension(id: 'tiefe', question: 'Wie tief?', chips: [
        _c('ueberblick', 'Schneller Überblick', ChipKind.mode, 'precise', '⚡'),
        _c('detail', 'Ausführlich', ChipKind.mode, 'standard', '🔍'),
        _c('stoebern', 'Stöbern', ChipKind.mode, 'discover', '🧭'),
      ], allowCustom: false),
      CoachDimension(id: 'quelle', question: 'Welche Quelle?', chips: [
        _c('wiki', 'Wikipedia', ChipKind.site, 'wikipedia.org', '📚'),
        _c('news', 'News', ChipKind.site, 'tagesschau.de OR site:spiegel.de OR site:zeit.de', '📰'),
        _c('offiziell', 'Offiziell', ChipKind.site, 'bund.de OR site:europa.eu', '🏛️'),
        _c('reddit', 'Reddit', ChipKind.site, 'reddit.com', '🟠'),
      ], multiSelect: true),
    ],
  );
}
