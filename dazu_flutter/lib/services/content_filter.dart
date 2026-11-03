/// Wortbasierter Content-Filter für User-Eingaben (Runde-Name,
/// Beschreibung, Profil-Name). 1:1-Port von iOS `ContentFilter.swift`.
///
/// Strategie: einfache Wort-Blocklist, Whole-Word-Match (Wortgrenze),
/// Case-insensitive, mit basaler Leetspeak-Normalisierung
/// (`@→a`, `3→e`, `1→i`, `0→o`, `$/5→s`, `7→t`) +
/// Punkt-/Stern-/Trennzeichen-Filter (`f.u.c.k`, `f*ck`, `f_u_c_k` →
/// `fuck`).
///
/// Sprachen: DE/EN/TR/AR(translit)/ES/FR/IT/RU(translit)/PL/NL.
/// Plus universelle Slurs, Sexual-Solicitation, Drohwörter.
///
/// Performance: alle Blocklist-Wörter werden EINMAL beim ersten Scan
/// zu einem einzelnen `\b(w1|w2|…)\b`-Pattern compiliert und gecacht —
/// bei 300+ Wörtern ~50× schneller als N einzelne RegExps.
class ContentFilter {
  const ContentFilter._();

  /// Bewusst Lowercase ohne Leetspeak (normalize macht das). Compound-
  /// Wörter werden via Wortgrenze gematcht — „spazieren" matcht nicht
  /// „spast", auch wenn die Buchstaben drin sind.
  static const Set<String> blocklist = {
    // ─────────────────────────────────────────────────────────────
    // DEUTSCH — Beleidigungen
    // ─────────────────────────────────────────────────────────────
    'arschloch', 'arsch', 'arschlecker', 'arschkriecher',
    'wichser', 'wixer', 'wixxer', 'wichsen', 'wixen',
    'idiot', 'vollidiot', 'depp', 'trottel', 'drecksvieh',
    'hurensohn', 'hurenkind', 'hure', 'schlampe', 'nutte',
    'fotze', 'miststueck', 'miststück', 'missgeburt',
    'spasti', 'spast', 'behindi', 'mongo', 'kackbratze',
    'spinner', 'vollpfosten', 'drecksau', 'drecksack',
    'abschaum', 'missratener', 'schwachkopf', 'schwachmat',
    'vollhonk', 'honk', 'lappen', 'lutscher',
    'opfer', 'loser', 'versager',
    // DE — Slurs
    'kanake', 'nigger', 'neger', 'negerin',
    'schwuchtel', 'schwuchti', 'tunte',
    'schwanzlutscher', 'fag', 'faggot',
    'zigeuner', 'zigeunerin', 'jud', 'judensau', 'judenbengel',
    'polacke',
    // DE — Sexuell / vulgär
    'blowjob', 'blasen', 'blowi',
    'ficken', 'fick', 'ficker', 'anficken', 'weggeficken',
    'gangbang', 'bumsen', 'vögeln', 'voegeln',
    'schwanz', 'schwanzfick',
    'titten', 'muschi', 'möse', 'moese', 'pussy',
    'wichsvorlage',
    'anal', 'deepthroat', 'facefuck', 'creampie',
    'sexkontakt', 'sexkontakte', 'sextreffen', 'treffsex',
    'fickdate', 'fickdates', 'fickfreund', 'fickfreundin',
    'huren', 'puff', 'bordell', 'rotlicht', 'callgirl',
    'callboy', 'escort', 'escortservice',
    'milf', 'dilf', 'gilf',
    // DE — Gewalt / Drohungen
    'killen', 'umbringen', 'abstechen', 'totschlagen',
    'vergewaltigen', 'vergewaltigung', 'vergewaltiger',
    'erschießen', 'erschiessen', 'erschiess',
    'abknallen', 'köpfen', 'koepfen',

    // ─────────────────────────────────────────────────────────────
    // ENGLISCH
    // ─────────────────────────────────────────────────────────────
    'fuck', 'fucker', 'fucking', 'fuckface', 'fucktard',
    'motherfucker', 'mofo', 'mf',
    'asshole', 'asshat', 'assclown', 'asswipe', 'jackass',
    'shit', 'shithead', 'shitbag', 'bullshit', 'shitstorm',
    'bitch', 'bitchy', 'biatch',
    'cunt', 'twat', 'dickhead', 'dick', 'dickface',
    'slut', 'whore', 'thot', 'ho',
    'retard', 'retarded', 'moron',
    'bastard', 'scumbag',
    'wanker', 'tosser', 'prick',
    'douche', 'douchebag',
    // EN — Slurs
    'nigga', 'tranny', 'kike', 'chink', 'spic',
    'gook', 'wop', 'wetback', 'coon', 'redskin',
    'homo',
    'raghead', 'towelhead', 'muzzie',
    'paki',
    // EN — Sexual
    'porn', 'porno', 'xxx',
    'handjob', 'rimjob',
    'bukkake', 'facial',
    'hookup', 'fwb', 'nsa', 'sexting',
    'naked', 'nude', 'nudes', 'send nudes',
    'horny', 'kinky',
    'prostitute', 'hooker',
    'fisting',
    // EN — Threats / violence
    'kill', 'killing', 'killyou', 'kys', 'rape', 'raping',
    'stab', 'shoot', 'shooting', 'murder', 'molest',
    'bomb', 'terrorist', 'isis', 'nazi',

    // ─────────────────────────────────────────────────────────────
    // TÜRKISCH
    // ─────────────────────────────────────────────────────────────
    'amk', 'aq', 'amına', 'amına koyim', 'aminakoyim',
    'orospu', 'orospucocugu', 'orospucocuğu', 'piç',
    'siktir', 'siktir git', 'sikim', 'sikerim', 'sikiyim',
    'yarrak', 'yarak', 'döl', 'götveren', 'ibne',
    'puşt', 'pust', 'gavat', 'şerefsiz', 'serefsiz',
    'kahpe', 'fahişe', 'fahise',

    // ─────────────────────────────────────────────────────────────
    // ARABISCH (translit.)
    // ─────────────────────────────────────────────────────────────
    'kalb', 'kelb', 'ibn kalb', 'ibn al kalb',
    'sharmuta', 'charmuta', 'sharmute',
    'kahba', 'kahbeh',
    'manyak', 'manyuk',
    'khara', 'akhu sharmuta',
    'qahba', 'qahbe',
    'zib', 'zob',
    'ya hmar', 'hmar',

    // ─────────────────────────────────────────────────────────────
    // SPANISCH
    // ─────────────────────────────────────────────────────────────
    'puto', 'puta', 'putita', 'putos', 'putas',
    'cabron', 'cabrón', 'cabrona', 'cabrones',
    'pendejo', 'pendeja', 'pendejos',
    'mierda', 'joder', 'coño', 'cono',
    'chinga', 'chingar', 'chingada', 'chingate',
    'verga', 'pinche', 'pendejada',
    'maricon', 'maricón', 'marica',
    'zorra', 'perra',
    'follar', 'follador', 'culiar',
    'polla', 'concha', 'panocha',

    // ─────────────────────────────────────────────────────────────
    // FRANZÖSISCH
    // ─────────────────────────────────────────────────────────────
    'putain', 'salope', 'salaud', 'connard', 'connasse',
    'enculé', 'encule', 'enculer',
    'bordel', 'merde', 'bite', 'couilles', 'couilles molles',
    'pute', 'pétasse', 'petasse',
    'nique', 'niquer', 'niquetamere', 'niquetamère',
    'fdp', 'ntm', 'tg',
    'pédé', 'pede', 'tarlouze',

    // ─────────────────────────────────────────────────────────────
    // ITALIENISCH
    // ─────────────────────────────────────────────────────────────
    'cazzo', 'cazzata', 'stronzo', 'stronza', 'stronzata',
    'vaffanculo', 'vafanculo', 'fanculo',
    'puttana', 'troia', 'porca', 'porcoddio',
    'minchia', 'coglione', 'coglioni',
    'frocio', 'ricchione',

    // ─────────────────────────────────────────────────────────────
    // RUSSISCH (translit.)
    // ─────────────────────────────────────────────────────────────
    'blyat', 'blya', 'blyad', 'blyadi',
    'suka', 'suchka',
    'pizdec', 'pizdets', 'pizda',
    'huy', 'huya', 'huynya', 'huyovo',
    'yobaniy', 'yobannyy', 'yobanyy',
    'mudak', 'mudaki',
    'pidor', 'pidaras', 'pidoras',
    'govno', "der'mo", 'dermo',
    'shluha', 'shluxa',

    // ─────────────────────────────────────────────────────────────
    // POLNISCH
    // ─────────────────────────────────────────────────────────────
    'kurwa', 'kurwy', 'kurwo',
    'chuj', 'chuja', 'chujowy',
    'pierdol', 'pierdolic', 'spierdalaj', 'wypierdalaj',
    'jebać', 'jebac', 'jeb', 'jebaniec',
    'skurwysyn', 'skurwiel',
    'cipa', 'cipy',
    'dupa', 'dupek',
    'szmata',

    // ─────────────────────────────────────────────────────────────
    // NIEDERLÄNDISCH
    // ─────────────────────────────────────────────────────────────
    'kut', 'klootzak', 'lul', 'kutwijf',
    'hoer', 'hoertje', 'slet',
    'godverdomme', 'gvd',
    'tering', 'tyfus', 'kanker',
    'neuken', 'wijf', 'trut',

    // ─────────────────────────────────────────────────────────────
    // Universelle Slurs
    // ─────────────────────────────────────────────────────────────
    'hitler', 'heilhitler', 'sieg heil', 'siegheil',
    'kkk', 'skinhead',
  };

  // ── Public API ────────────────────────────────────────────────────

  /// Prüft Runde-Name + optional Beschreibung. Gibt das erste gefundene
  /// Wort zurück, oder `null` wenn sauber.
  static ContentMatch? firstMatch({
    required String activityName,
    String? description,
  }) {
    final a = _scan(activityName);
    if (a != null) return ContentMatch(word: a, inField: activityName);
    if (description != null && description.isNotEmpty) {
      final d = _scan(description);
      if (d != null) return ContentMatch(word: d, inField: description);
    }
    return null;
  }

  /// Profilname-Check — einzelnes Feld, gleiche Engine.
  static ContentMatch? firstMatchInProfileName(String name) {
    final hit = _scan(name);
    return hit == null ? null : ContentMatch(word: hit, inField: name);
  }

  /// Allgemeine Prüfung — für beliebige Felder.
  static bool hasBlockedWord(String text) => _scan(text) != null;

  // ── Internals ────────────────────────────────────────────────────

  /// Cached kombiniertes RegExp — `\b(word1|word2|…)\b`. Beim ersten
  /// Scan einmalig gebaut, danach wiederverwendet. Mit Alternation
  /// deutlich schneller als N einzelne RegExps.
  static final RegExp _combined = _buildCombined();

  static RegExp _buildCombined() {
    // Längste Wörter zuerst, damit „arschloch" vor „arsch" gematcht wird.
    final sorted = blocklist.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final escaped = sorted.map(_escapeRegExp).join('|');
    return RegExp('\\b($escaped)\\b', caseSensitive: false, unicode: true);
  }

  /// Liefert das erste Blocklist-Wort — Zwei-Pass-Scan:
  ///   1. Normalize MIT Leerzeichen → Wortgrenze funktioniert für
  ///      normale Sätze („kaffee sex party" → „sex").
  ///   2. Falls Pass 1 leer: Leerzeichen weg → obfuskierte Eingaben
  ///      („f u c k" → „fuck").
  static String? _scan(String raw) {
    final a = _match(_normalize(raw, stripSpaces: false));
    if (a != null) return a;
    return _match(_normalize(raw, stripSpaces: true));
  }

  static String? _match(String text) {
    final m = _combined.firstMatch(text);
    if (m == null) return null;
    return m.group(1);
  }

  /// Normalisiert User-Input:
  ///   1. lowercase
  ///   2. Leetspeak rückwärts (`@/4 → a`, `3 → e`, `1/!/| → i`,
  ///      `0 → o`, `$/5 → s`, `7 → t`)
  ///   3. Trennzeichen raus (`f.u.c.k` / `f*ck` / `f_u_c_k` → `fuck`)
  ///   4. Falls `stripSpaces`: zusätzlich Leerzeichen weg.
  static String _normalize(String raw, {required bool stripSpaces}) {
    final buf = StringBuffer();
    final lower = raw.toLowerCase();
    const map = <String, String>{
      '@': 'a', '4': 'a',
      '3': 'e',
      '1': 'i', '!': 'i', '|': 'i',
      '0': 'o',
      '\$': 's', '5': 's',
      '7': 't',
    };
    final separators = <String>{'.', '*', '_', '-', '·', '‧'};
    if (stripSpaces) separators.add(' ');
    for (int i = 0; i < lower.length; i++) {
      final ch = lower[i];
      if (separators.contains(ch)) continue;
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Escaped Regex-Metazeichen in einem Literal — identisch zu
  /// `NSRegularExpression.escapedPattern(for:)`.
  static String _escapeRegExp(String s) {
    return s.replaceAllMapped(
      RegExp(r'[\\^$.*+?()\[\]{}|]'),
      (m) => '\\${m[0]}',
    );
  }
}

class ContentMatch {
  const ContentMatch({required this.word, required this.inField});

  /// Gefundenes Blocklist-Wort (lowercase).
  final String word;

  /// Ursprünglicher Feld-Inhalt (für User-Feedback „in deinem
  /// Aktivitätsnamen").
  final String inField;
}
