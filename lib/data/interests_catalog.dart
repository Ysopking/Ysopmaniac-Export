/// Stage G: Hierarchischer Interessen-Katalog (3 Ebenen).
///
/// Struktur:  Top-Kategorie -> Unterkategorie -> Item (Multi-Select).
/// Speicher-Format als flache Pfade `top/sub/item` (z.B. `musik/rap/sido`).
///
/// IDs sind ASCII-lowercase (kein Umlaut) — sie landen 1:1 als
/// `weight_kw_<token>` im Lern-Modell, also ohne Sonderzeichen.
/// Labels sind das, was der User sieht (DE).

class InterestSubcategory {
  final String id;
  final String label;
  final List<InterestItem> items;
  const InterestSubcategory(this.id, this.label, this.items);
}

class InterestItem {
  final String id;
  final String label;
  const InterestItem(this.id, this.label);
}

class InterestCategory {
  final String id;
  final String label;
  final String emoji;
  final List<InterestSubcategory> subs;
  const InterestCategory(this.id, this.label, this.emoji, this.subs);
}

const List<InterestCategory> kInterestsCatalog = <InterestCategory>[
  InterestCategory('musik', 'Musik', '🎵', [
    InterestSubcategory('rap', 'Rap & Hip-Hop', [
      InterestItem('sido', 'Sido'),
      InterestItem('bushido', 'Bushido'),
      InterestItem('kollegah', 'Kollegah'),
      InterestItem('capitalbra', 'Capital Bra'),
      InterestItem('apache207', 'Apache 207'),
      InterestItem('haftbefehl', 'Haftbefehl'),
      InterestItem('rafcamora', 'RAF Camora'),
      InterestItem('oldschool', 'Old-School (Tupac, Biggie, NWA)'),
      InterestItem('eminem', 'Eminem'),
      InterestItem('drake', 'Drake'),
    ]),
    InterestSubcategory('rock', 'Rock & Metal', [
      InterestItem('rammstein', 'Rammstein'),
      InterestItem('metallica', 'Metallica'),
      InterestItem('linkinpark', 'Linkin Park'),
      InterestItem('acdc', 'AC/DC'),
      InterestItem('foofighters', 'Foo Fighters'),
      InterestItem('queen', 'Queen'),
      InterestItem('nirvana', 'Nirvana'),
      InterestItem('iron', 'Iron Maiden'),
    ]),
    InterestSubcategory('pop', 'Pop & Charts', [
      InterestItem('helene', 'Helene Fischer'),
      InterestItem('taylorswift', 'Taylor Swift'),
      InterestItem('edsheeran', 'Ed Sheeran'),
      InterestItem('adele', 'Adele'),
      InterestItem('weeknd', 'The Weeknd'),
      InterestItem('billie', 'Billie Eilish'),
      InterestItem('dualipa', 'Dua Lipa'),
    ]),
    InterestSubcategory('elektro', 'Elektronik & EDM', [
      InterestItem('guetta', 'David Guetta'),
      InterestItem('daftpunk', 'Daft Punk'),
      InterestItem('calvin', 'Calvin Harris'),
      InterestItem('techno', 'Techno'),
      InterestItem('house', 'House'),
      InterestItem('trance', 'Trance'),
      InterestItem('dnb', 'Drum and Bass'),
    ]),
    InterestSubcategory('klassik', 'Klassik', [
      InterestItem('beethoven', 'Beethoven'),
      InterestItem('mozart', 'Mozart'),
      InterestItem('bach', 'Bach'),
      InterestItem('klavier', 'Klaviermusik'),
      InterestItem('orchester', 'Orchester'),
      InterestItem('filmmusik', 'Filmmusik (Hans Zimmer)'),
    ]),
    InterestSubcategory('jazz', 'Jazz & Soul', [
      InterestItem('milesdavis', 'Miles Davis'),
      InterestItem('amywinehouse', 'Amy Winehouse'),
      InterestItem('coltrane', 'John Coltrane'),
      InterestItem('norahjones', 'Norah Jones'),
      InterestItem('blues', 'Blues'),
    ]),
  ]),

  InterestCategory('sport', 'Sport', '⚽', [
    InterestSubcategory('fussball', 'Fussball', [
      InterestItem('bundesliga', 'Bundesliga'),
      InterestItem('bayern', 'Bayern Muenchen'),
      InterestItem('bvb', 'Borussia Dortmund'),
      InterestItem('realmadrid', 'Real Madrid'),
      InterestItem('barcelona', 'FC Barcelona'),
      InterestItem('cl', 'Champions League'),
      InterestItem('emwm', 'EM und WM'),
    ]),
    InterestSubcategory('formel1', 'Formel 1', [
      InterestItem('mercedes', 'Mercedes'),
      InterestItem('ferrari', 'Ferrari'),
      InterestItem('redbull', 'Red Bull'),
      InterestItem('hamilton', 'Lewis Hamilton'),
      InterestItem('verstappen', 'Max Verstappen'),
      InterestItem('vettel', 'Sebastian Vettel'),
    ]),
    InterestSubcategory('kampfsport', 'Kampfsport', [
      InterestItem('boxen', 'Boxen'),
      InterestItem('mma', 'MMA'),
      InterestItem('ufc', 'UFC'),
      InterestItem('mcgregor', 'Conor McGregor'),
      InterestItem('khabib', 'Khabib Nurmagomedov'),
      InterestItem('bjj', 'Brazilian Jiu-Jitsu'),
    ]),
    InterestSubcategory('tennis', 'Tennis', [
      InterestItem('wimbledon', 'Wimbledon'),
      InterestItem('zverev', 'Alexander Zverev'),
      InterestItem('djokovic', 'Novak Djokovic'),
      InterestItem('nadal', 'Rafael Nadal'),
      InterestItem('atp', 'ATP Tour'),
    ]),
    InterestSubcategory('fitness', 'Fitness', [
      InterestItem('krafttraining', 'Krafttraining'),
      InterestItem('yoga', 'Yoga'),
      InterestItem('laufen', 'Laufen und Marathon'),
      InterestItem('crossfit', 'Crossfit'),
      InterestItem('hiit', 'HIIT'),
      InterestItem('bodyweight', 'Bodyweight Training'),
    ]),
    InterestSubcategory('winter', 'Wintersport', [
      InterestItem('skialpin', 'Ski Alpin'),
      InterestItem('biathlon', 'Biathlon'),
      InterestItem('eishockey', 'Eishockey'),
      InterestItem('skispringen', 'Skispringen'),
      InterestItem('langlauf', 'Langlauf'),
    ]),
  ]),

  InterestCategory('mathe', 'Mathematik', '🧮', [
    InterestSubcategory('schule', 'Schul-Mathe', [
      InterestItem('algebra', 'Algebra'),
      InterestItem('geometrie', 'Geometrie'),
      InterestItem('analysis', 'Analysis'),
      InterestItem('stochastik', 'Stochastik'),
      InterestItem('trigonometrie', 'Trigonometrie'),
    ]),
    InterestSubcategory('hoehere', 'Hoehere Mathematik', [
      InterestItem('linalg', 'Lineare Algebra'),
      InterestItem('dgl', 'Differentialgleichungen'),
      InterestItem('topologie', 'Topologie'),
      InterestItem('komplex', 'Komplexe Zahlen'),
      InterestItem('funktionalanalysis', 'Funktionalanalysis'),
    ]),
    InterestSubcategory('logik', 'Logik & Beweise', [
      InterestItem('aussagenlogik', 'Aussagenlogik'),
      InterestItem('mengenlehre', 'Mengenlehre'),
      InterestItem('beweistechnik', 'Beweistechniken'),
      InterestItem('graphentheorie', 'Graphentheorie'),
    ]),
    InterestSubcategory('statistik', 'Statistik & Stochastik', [
      InterestItem('wahrscheinlichkeit', 'Wahrscheinlichkeit'),
      InterestItem('regression', 'Regression'),
      InterestItem('hypothesen', 'Hypothesentests'),
      InterestItem('bayes', 'Bayes-Statistik'),
    ]),
    InterestSubcategory('kopfrechnen', 'Kopfrechnen-Tricks', [
      InterestItem('schnellrechnen', 'Schnellrechnen'),
      InterestItem('vedisch', 'Vedische Mathematik'),
      InterestItem('mentalarithmetik', 'Mentalarithmetik'),
    ]),
    InterestSubcategory('anwendung', 'Anwendungen', [
      InterestItem('finanzmathe', 'Finanzmathematik'),
      InterestItem('spieltheorie', 'Spieltheorie'),
      InterestItem('optimierung', 'Optimierung'),
      InterestItem('kryptographie', 'Kryptographie'),
    ]),
  ]),

  InterestCategory('sprachen', 'Sprachen lernen', '🌍', [
    InterestSubcategory('englisch', 'Englisch', [
      InterestItem('grammar', 'Grammar'),
      InterestItem('vocab', 'Vokabeln'),
      InterestItem('konversation', 'Konversation'),
      InterestItem('business', 'Business English'),
      InterestItem('ielts', 'IELTS / TOEFL'),
    ]),
    InterestSubcategory('spanisch', 'Spanisch', [
      InterestItem('grammatik', 'Grammatik'),
      InterestItem('vokabeln', 'Vokabeln'),
      InterestItem('lateinamerika', 'Lateinamerikanisches Spanisch'),
      InterestItem('dele', 'DELE'),
    ]),
    InterestSubcategory('franzoesisch', 'Franzoesisch', [
      InterestItem('grammaire', 'Grammaire'),
      InterestItem('vocabulaire', 'Vokabular'),
      InterestItem('delf', 'DELF / DALF'),
    ]),
    InterestSubcategory('italienisch', 'Italienisch', [
      InterestItem('italgrammatik', 'Grammatik'),
      InterestItem('italvokabeln', 'Vokabeln'),
      InterestItem('konversazione', 'Konversation'),
    ]),
    InterestSubcategory('tuerkisch', 'Tuerkisch', [
      InterestItem('turgrammatik', 'Grammatik'),
      InterestItem('turvokabeln', 'Vokabeln'),
      InterestItem('turkonversation', 'Konversation'),
    ]),
    InterestSubcategory('asiatisch', 'Asiatische Sprachen', [
      InterestItem('japanisch', 'Japanisch'),
      InterestItem('chinesisch', 'Chinesisch (Mandarin)'),
      InterestItem('koreanisch', 'Koreanisch'),
      InterestItem('thai', 'Thai'),
    ]),
  ]),

  InterestCategory('wissenschaft', 'Wissenschaft', '🔬', [
    InterestSubcategory('physik', 'Physik', [
      InterestItem('quantenphysik', 'Quantenphysik'),
      InterestItem('astrophysik', 'Astrophysik'),
      InterestItem('kosmologie', 'Kosmologie'),
      InterestItem('relativitaet', 'Relativitaetstheorie'),
      InterestItem('teilchen', 'Teilchenphysik'),
    ]),
    InterestSubcategory('chemie', 'Chemie', [
      InterestItem('organisch', 'Organische Chemie'),
      InterestItem('anorganisch', 'Anorganische Chemie'),
      InterestItem('biochemie', 'Biochemie'),
      InterestItem('analytik', 'Analytische Chemie'),
    ]),
    InterestSubcategory('biologie', 'Biologie & Medizin', [
      InterestItem('genetik', 'Genetik'),
      InterestItem('evolution', 'Evolution'),
      InterestItem('mikrobiologie', 'Mikrobiologie'),
      InterestItem('medizin', 'Medizin'),
      InterestItem('neuro', 'Neurowissenschaft'),
    ]),
    InterestSubcategory('klima', 'Klima & Umwelt', [
      InterestItem('erderwaermung', 'Erderwaermung'),
      InterestItem('erneuerbare', 'Erneuerbare Energien'),
      InterestItem('naturschutz', 'Naturschutz'),
      InterestItem('co2', 'CO2-Reduktion'),
    ]),
    InterestSubcategory('ki', 'KI & Technik', [
      InterestItem('ml', 'Maschinelles Lernen'),
      InterestItem('robotik', 'Robotik'),
      InterestItem('quantum', 'Quantum Computing'),
      InterestItem('llm', 'LLM und ChatGPT'),
    ]),
    InterestSubcategory('geschichte', 'Geschichte', [
      InterestItem('antike', 'Antike'),
      InterestItem('mittelalter', 'Mittelalter'),
      InterestItem('weltkriege', 'Weltkriege'),
      InterestItem('archaeologie', 'Archaeologie'),
    ]),
  ]),

  InterestCategory('film', 'Filme & Serien', '🎬', [
    InterestSubcategory('scifi', 'Sci-Fi & Fantasy', [
      InterestItem('starwars', 'Star Wars'),
      InterestItem('startrek', 'Star Trek'),
      InterestItem('marvel', 'Marvel MCU'),
      InterestItem('dc', 'DC Universe'),
      InterestItem('dune', 'Dune'),
      InterestItem('hdr', 'Herr der Ringe'),
    ]),
    InterestSubcategory('drama', 'Drama-Serien', [
      InterestItem('breakingbad', 'Breaking Bad'),
      InterestItem('thewire', 'The Wire'),
      InterestItem('sopranos', 'The Sopranos'),
      InterestItem('saul', 'Better Call Saul'),
      InterestItem('succession', 'Succession'),
    ]),
    InterestSubcategory('krimi', 'Krimi & Thriller', [
      InterestItem('tatort', 'Tatort'),
      InterestItem('sherlock', 'Sherlock'),
      InterestItem('truedetective', 'True Detective'),
      InterestItem('mindhunter', 'Mindhunter'),
    ]),
    InterestSubcategory('comedy', 'Komoedie', [
      InterestItem('sitcom', 'Sitcoms'),
      InterestItem('standup', 'Stand-Up Comedy'),
      InterestItem('officeus', 'The Office'),
      InterestItem('friends', 'Friends'),
    ]),
    InterestSubcategory('anime', 'Anime & Manga', [
      InterestItem('ghibli', 'Studio Ghibli'),
      InterestItem('naruto', 'Naruto'),
      InterestItem('onepiece', 'One Piece'),
      InterestItem('aot', 'Attack on Titan'),
      InterestItem('demonslayer', 'Demon Slayer'),
    ]),
    InterestSubcategory('streaming', 'Streaming-Plattformen', [
      InterestItem('netflix', 'Netflix'),
      InterestItem('disney', 'Disney Plus'),
      InterestItem('prime', 'Amazon Prime'),
      InterestItem('appletv', 'Apple TV Plus'),
    ]),
  ]),

  InterestCategory('gaming', 'Gaming', '🎮', [
    InterestSubcategory('shooter', 'Shooter', [
      InterestItem('csgo', 'Counter-Strike'),
      InterestItem('cod', 'Call of Duty'),
      InterestItem('valorant', 'Valorant'),
      InterestItem('battlefield', 'Battlefield'),
      InterestItem('fortnite', 'Fortnite'),
    ]),
    InterestSubcategory('rpg', 'Rollenspiele', [
      InterestItem('witcher', 'The Witcher'),
      InterestItem('skyrim', 'Skyrim'),
      InterestItem('eldenring', 'Elden Ring'),
      InterestItem('baldursgate', 'Baldurs Gate'),
      InterestItem('cyberpunk', 'Cyberpunk 2077'),
    ]),
    InterestSubcategory('strategie', 'Strategie', [
      InterestItem('civ', 'Civilization'),
      InterestItem('aoe', 'Age of Empires'),
      InterestItem('starcraft', 'StarCraft'),
      InterestItem('anno', 'Anno-Reihe'),
    ]),
    InterestSubcategory('sportgames', 'Sport-Games', [
      InterestItem('fifa', 'FIFA / FC'),
      InterestItem('nba2k', 'NBA 2K'),
      InterestItem('f1game', 'F1-Game'),
      InterestItem('efootball', 'eFootball'),
    ]),
    InterestSubcategory('indie', 'Indie & Retro', [
      InterestItem('hollow', 'Hollow Knight'),
      InterestItem('stardew', 'Stardew Valley'),
      InterestItem('hades', 'Hades'),
      InterestItem('terraria', 'Terraria'),
    ]),
    InterestSubcategory('mobile', 'Mobile Gaming', [
      InterestItem('clash', 'Clash of Clans'),
      InterestItem('genshin', 'Genshin Impact'),
      InterestItem('pubgmobile', 'PUBG Mobile'),
      InterestItem('brawl', 'Brawl Stars'),
    ]),
  ]),

  InterestCategory('kochen', 'Kochen & Rezepte', '🍳', [
    InterestSubcategory('italienisch', 'Italienisch', [
      InterestItem('pasta', 'Pasta'),
      InterestItem('pizza', 'Pizza'),
      InterestItem('risotto', 'Risotto'),
      InterestItem('tiramisu', 'Tiramisu'),
    ]),
    InterestSubcategory('asiatisch', 'Asiatisch', [
      InterestItem('sushi', 'Sushi'),
      InterestItem('wok', 'Wok-Gerichte'),
      InterestItem('curry', 'Curry'),
      InterestItem('ramen', 'Ramen'),
      InterestItem('pho', 'Pho'),
    ]),
    InterestSubcategory('backen', 'Backen', [
      InterestItem('brot', 'Brot backen'),
      InterestItem('kuchen', 'Kuchen'),
      InterestItem('torten', 'Torten'),
      InterestItem('sourdough', 'Sourdough'),
    ]),
    InterestSubcategory('veggie', 'Vegetarisch & Vegan', [
      InterestItem('bowls', 'Bowls'),
      InterestItem('tofu', 'Tofu-Rezepte'),
      InterestItem('seitan', 'Seitan'),
      InterestItem('vegancake', 'Vegan backen'),
    ]),
    InterestSubcategory('grillen', 'Grillen & BBQ', [
      InterestItem('steak', 'Steak'),
      InterestItem('smoker', 'Smoker'),
      InterestItem('marinaden', 'Marinaden'),
      InterestItem('lowsmoke', 'Low and Slow'),
    ]),
    InterestSubcategory('gesund', 'Gesund & Fitness', [
      InterestItem('mealprep', 'Meal-Prep'),
      InterestItem('lowcarb', 'Low-Carb'),
      InterestItem('protein', 'Protein-Rezepte'),
      InterestItem('keto', 'Keto'),
    ]),
  ]),

  InterestCategory('reisen', 'Reisen', '✈️', [
    InterestSubcategory('europa', 'Europa', [
      InterestItem('italien', 'Italien'),
      InterestItem('spanien', 'Spanien'),
      InterestItem('skandinavien', 'Skandinavien'),
      InterestItem('griechenland', 'Griechenland'),
      InterestItem('portugal', 'Portugal'),
    ]),
    InterestSubcategory('amerika', 'USA & Kanada', [
      InterestItem('newyork', 'New York'),
      InterestItem('losangeles', 'Los Angeles'),
      InterestItem('nationalparks', 'Nationalparks'),
      InterestItem('roadtripus', 'US-Roadtrip'),
    ]),
    InterestSubcategory('asien', 'Asien', [
      InterestItem('japan', 'Japan'),
      InterestItem('thailand', 'Thailand'),
      InterestItem('bali', 'Bali'),
      InterestItem('vietnam', 'Vietnam'),
      InterestItem('indien', 'Indien'),
    ]),
    InterestSubcategory('roadtrip', 'Roadtrips & Camping', [
      InterestItem('vanlife', 'Vanlife'),
      InterestItem('wohnmobil', 'Wohnmobil'),
      InterestItem('wildcamping', 'Wildcamping'),
    ]),
    InterestSubcategory('staedte', 'Staedtereisen', [
      InterestItem('berlin', 'Berlin'),
      InterestItem('paris', 'Paris'),
      InterestItem('london', 'London'),
      InterestItem('rom', 'Rom'),
      InterestItem('tokio', 'Tokio'),
    ]),
    InterestSubcategory('berge', 'Wandern & Berge', [
      InterestItem('alpen', 'Alpen'),
      InterestItem('gr20', 'GR20 Korsika'),
      InterestItem('pct', 'Pacific Crest Trail'),
      InterestItem('hiking', 'Trekking generell'),
    ]),
  ]),

  InterestCategory('tech', 'Tech & Coding', '💻', [
    InterestSubcategory('webdev', 'Web-Dev', [
      InterestItem('react', 'React'),
      InterestItem('vue', 'Vue.js'),
      InterestItem('tailwind', 'Tailwind CSS'),
      InterestItem('nextjs', 'Next.js'),
      InterestItem('typescript', 'TypeScript'),
    ]),
    InterestSubcategory('mobiledev', 'Mobile Dev', [
      InterestItem('flutter', 'Flutter'),
      InterestItem('swift', 'Swift / iOS'),
      InterestItem('kotlin', 'Kotlin / Android'),
      InterestItem('reactnative', 'React Native'),
    ]),
    InterestSubcategory('backend', 'Backend', [
      InterestItem('nodejs', 'Node.js'),
      InterestItem('python', 'Python'),
      InterestItem('golang', 'Go'),
      InterestItem('rust', 'Rust'),
      InterestItem('java', 'Java'),
    ]),
    InterestSubcategory('devops', 'DevOps & Cloud', [
      InterestItem('docker', 'Docker'),
      InterestItem('kubernetes', 'Kubernetes'),
      InterestItem('aws', 'AWS'),
      InterestItem('terraform', 'Terraform'),
    ]),
    InterestSubcategory('aidev', 'KI & Daten', [
      InterestItem('pytorch', 'PyTorch'),
      InterestItem('tensorflow', 'TensorFlow'),
      InterestItem('llmdev', 'LLM-Entwicklung'),
      InterestItem('chatgptapi', 'ChatGPT API'),
    ]),
    InterestSubcategory('hardware', 'Hardware & Linux', [
      InterestItem('raspberry', 'Raspberry Pi'),
      InterestItem('arduino', 'Arduino'),
      InterestItem('linux', 'Linux'),
      InterestItem('homeserver', 'Home Server'),
    ]),
  ]),

  InterestCategory('garten', 'Garten & Heimwerken', '🌱', [
    InterestSubcategory('gemuese', 'Gemuesegarten', [
      InterestItem('tomaten', 'Tomaten'),
      InterestItem('gurken', 'Gurken'),
      InterestItem('kartoffeln', 'Kartoffeln'),
      InterestItem('hochbeet', 'Hochbeet'),
    ]),
    InterestSubcategory('zierpflanzen', 'Zierpflanzen', [
      InterestItem('rosen', 'Rosen'),
      InterestItem('stauden', 'Stauden'),
      InterestItem('zimmerpflanzen', 'Zimmerpflanzen'),
    ]),
    InterestSubcategory('obst', 'Obst & Baeume', [
      InterestItem('apfelbaum', 'Apfelbaum'),
      InterestItem('beeren', 'Beerenstraeucher'),
      InterestItem('schnitt', 'Baumschnitt'),
    ]),
    InterestSubcategory('renovierung', 'Renovierung', [
      InterestItem('streichen', 'Streichen'),
      InterestItem('tapezieren', 'Tapezieren'),
      InterestItem('boden', 'Bodenverlegen'),
    ]),
    InterestSubcategory('werkstatt', 'Werkstatt', [
      InterestItem('werkzeug', 'Werkzeuge'),
      InterestItem('holz', 'Holzarbeit'),
      InterestItem('bohren', 'Bohren & Duebeln'),
    ]),
    InterestSubcategory('smarthome', 'Smart Home', [
      InterestItem('hue', 'Philips Hue'),
      InterestItem('sonoff', 'Sonoff / Tasmota'),
      InterestItem('homeassistant', 'Home Assistant'),
    ]),
  ]),

  InterestCategory('auto', 'Auto & Mobilitaet', '🚗', [
    InterestSubcategory('elektro', 'Elektroautos', [
      InterestItem('tesla', 'Tesla'),
      InterestItem('id4', 'VW ID-Reihe'),
      InterestItem('etron', 'Audi e-tron'),
      InterestItem('polestar', 'Polestar'),
      InterestItem('byd', 'BYD'),
    ]),
    InterestSubcategory('tuning', 'Tuning & Sport', [
      InterestItem('bmwm', 'BMW M'),
      InterestItem('amg', 'Mercedes AMG'),
      InterestItem('audirs', 'Audi RS'),
      InterestItem('porsche', 'Porsche'),
    ]),
    InterestSubcategory('klassiker', 'Klassiker & Oldtimer', [
      InterestItem('oldtimer', 'Oldtimer'),
      InterestItem('youngtimer', 'Youngtimer'),
      InterestItem('restauration', 'Restauration'),
    ]),
    InterestSubcategory('motorrad', 'Motorrad', [
      InterestItem('bmwgs', 'BMW GS'),
      InterestItem('harley', 'Harley-Davidson'),
      InterestItem('yamaha', 'Yamaha'),
      InterestItem('motogp', 'MotoGP'),
    ]),
    InterestSubcategory('fahrrad', 'Fahrrad', [
      InterestItem('ebike', 'E-Bike'),
      InterestItem('mtb', 'Mountain Bike'),
      InterestItem('rennrad', 'Rennrad'),
      InterestItem('bikepacking', 'Bikepacking'),
    ]),
    InterestSubcategory('news', 'News & Tests', [
      InterestItem('automag', 'Auto-Magazine'),
      InterestItem('reviews', 'Reviews'),
      InterestItem('vergleiche', 'Vergleichstests'),
    ]),
  ]),
];

// ---------- Helfer ----------

InterestCategory? findCategory(String id) {
  for (final c in kInterestsCatalog) {
    if (c.id == id) return c;
  }
  return null;
}

InterestSubcategory? findSubcategory(InterestCategory cat, String subId) {
  for (final s in cat.subs) {
    if (s.id == subId) return s;
  }
  return null;
}

/// Wieviele Items aus dieser Top-Kategorie wurden gewaehlt?
int countSelectedInTop(String topId, List<String> selected) {
  var n = 0;
  final prefix = '$topId/';
  for (final s in selected) {
    if (s.startsWith(prefix)) n++;
  }
  return n;
}

/// Wieviele Items aus dieser Unterkategorie wurden gewaehlt?
int countSelectedInSub(
    String topId, String subId, List<String> selected) {
  var n = 0;
  final prefix = '$topId/$subId/';
  for (final s in selected) {
    if (s.startsWith(prefix)) n++;
  }
  return n;
}

/// Menschen-lesbares Label fuer einen gespeicherten Pfad.
String labelForPath(String path) {
  final parts = path.split('/');
  if (parts.length != 3) return path;
  final cat = findCategory(parts[0]);
  if (cat == null) return path;
  final sub = findSubcategory(cat, parts[1]);
  if (sub == null) return path;
  for (final i in sub.items) {
    if (i.id == parts[2]) {
      return '${cat.label} > ${sub.label} > ${i.label}';
    }
  }
  return path;
}
