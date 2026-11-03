import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_de.dart';
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_fr.dart';
import 'strings_it.dart';

/// 5 unterstützte Sprachen — iOS-Parität mit `enum AppLanguage` in
/// `Drops/Localization.swift`. Reihenfolge gleich (DE/EN/IT/FR/ES).
enum AppLanguage {
  german,
  english,
  italian,
  french,
  spanish;

  String get code {
    switch (this) {
      case AppLanguage.german:
        return 'de';
      case AppLanguage.english:
        return 'en';
      case AppLanguage.italian:
        return 'it';
      case AppLanguage.french:
        return 'fr';
      case AppLanguage.spanish:
        return 'es';
    }
  }

  String get label {
    switch (this) {
      case AppLanguage.german:
        return 'Deutsch';
      case AppLanguage.english:
        return 'English';
      case AppLanguage.italian:
        return 'Italiano';
      case AppLanguage.french:
        return 'Français';
      case AppLanguage.spanish:
        return 'Español';
    }
  }

  String get shortCode => code.toUpperCase();

  String get flag {
    switch (this) {
      case AppLanguage.german:
        return '🇩🇪';
      case AppLanguage.english:
        return '🇬🇧';
      case AppLanguage.italian:
        return '🇮🇹';
      case AppLanguage.french:
        return '🇫🇷';
      case AppLanguage.spanish:
        return '🇪🇸';
    }
  }

  static AppLanguage? fromCode(String? code) {
    if (code == null) return null;
    for (final l in AppLanguage.values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// String-Lookup-Service für die ganze App. Mirrort das iOS `tr(key)`-
/// Pattern aus `Drops/Localization.swift`: zuerst die aktive Sprache
/// nachschlagen, dann Fallback auf Deutsch (ist komplett übersetzt),
/// zuletzt den Key als Platzhalter zurückgeben.
///
/// Sprachauswahl überlebt App-Restarts via SharedPreferences
/// (`ud_appLanguage`, iOS-identisch).
///
/// Verwendung in Widgets:
/// ```dart
/// final l10n = L10n.of(context);
/// Text(l10n.tr('tab.map'));
/// ```
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n _instance = L10n._();
  static L10n get instance => _instance;

  /// Convenience für `L10n.instance` ohne Context — nützlich in
  /// Services wo kein BuildContext greifbar ist. Views sollten
  /// `L10n.of(context)` nutzen, damit sie bei Sprachwechsel neu
  /// bauen.
  static L10n of(BuildContext context) {
    final notifier =
        context.dependOnInheritedWidgetOfExactType<_L10nScope>()?.notifier;
    return notifier ?? _instance;
  }

  static const String _prefsKey = 'ud_appLanguage';
  static const AppLanguage _fallbackLang = AppLanguage.german;

  AppLanguage _language = _fallbackLang;
  AppLanguage get language => _language;

  bool _loaded = false;
  Future<void> loadFromPrefs() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = AppLanguage.fromCode(prefs.getString(_prefsKey));
      if (saved != null && saved != _language) {
        _language = saved;
        notifyListeners();
      }
    } catch (_) {
      // Prefs nicht verfügbar — Fallback-Sprache bleibt.
    }
  }

  Future<void> setLanguage(AppLanguage next) async {
    if (_language == next) return;
    _language = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.code);
    } catch (_) {}
  }

  /// Lookup. Erst aktive Sprache, dann Deutsch (ist komplett), zuletzt
  /// Key als sichtbarer Platzhalter.
  String tr(String key) => _lookup(key, _language);

  String _lookup(String key, AppLanguage lang) {
    final map = _mapFor(lang);
    final v = map[key];
    if (v != null) return v;
    if (lang != _fallbackLang) {
      final fallback = _mapFor(_fallbackLang)[key];
      if (fallback != null) return fallback;
    }
    return key; // sichtbare Lücke
  }

  Map<String, String> _mapFor(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.german:
        return stringsDe;
      case AppLanguage.english:
        return stringsEn;
      case AppLanguage.italian:
        return stringsIt;
      case AppLanguage.french:
        return stringsFr;
      case AppLanguage.spanish:
        return stringsEs;
    }
  }
}

/// Top-Level-Convenience — spiegelt iOS `tr("key")`. Nutzt die aktive
/// Sprache aus `L10n.instance`. Für reaktive Widgets lieber
/// `L10n.of(context).tr(…)` verwenden.
String tr(String key) => L10n.instance.tr(key);

/// Macht die aktuelle Sprache an die Widget-Tree weiter, damit
/// `L10n.of(context)` ein Rebuild bei Sprachwechsel triggert.
class L10nProvider extends StatefulWidget {
  const L10nProvider({super.key, required this.child});
  final Widget child;

  @override
  State<L10nProvider> createState() => _L10nProviderState();
}

class _L10nProviderState extends State<L10nProvider> {
  final L10n _notifier = L10n.instance;

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
    _notifier.loadFromPrefs();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _L10nScope(notifier: _notifier, child: widget.child);
  }
}

class _L10nScope extends InheritedWidget {
  const _L10nScope({required this.notifier, required super.child});
  final L10n notifier;

  @override
  bool updateShouldNotify(_L10nScope old) =>
      old.notifier.language != notifier.language;
}
