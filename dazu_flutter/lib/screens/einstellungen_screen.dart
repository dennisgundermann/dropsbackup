import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../l10n/l10n.dart';
import '../services/admin_seed_service.dart';
import '../services/block_report_service.dart';
import '../services/location_service.dart';
import '../services/referral_service.dart';
import '../services/reliability_service.dart';
import '../services/settings_sync_service.dart';
import '../services/og_code_service.dart';
import '../widgets/dazu_icon.dart';

import '../theme/dazu_colors.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/sticky_dazu_header.dart';

/// Einstellungen-Tab — pendant zu iOS `ProfileView`. V1 persistiert
/// alles lokal in SharedPreferences. Firebase-Sync (so dass dieselben
/// Prefs auf iOS/Android gelten) kommt in einem späteren Baustein.
class EinstellungenScreen extends StatefulWidget {
  const EinstellungenScreen({super.key});

  @override
  State<EinstellungenScreen> createState() => _EinstellungenScreenState();
}

class _EinstellungenScreenState extends State<EinstellungenScreen>
    with StickyDazuHeaderMixin {
  SharedPreferences? _prefs;
  final SettingsSyncService _sync = SettingsSyncService();

  bool _visible = false;
  bool _push = true;
  int _notifyRadiusM = 2000;
  double _runRadiusKm = 25; // „Unbegrenzt" repräsentiert durch 25km-Slider-Ende
  int _minAge = 18;
  int _maxAge = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Erst Firebase → SharedPreferences damit frisch-installierte
    // Android-Clients die iOS-Settings ihres Users übernehmen.
    await _sync.hydrateFromFirebase();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _visible = p.getBool('ud_visible') ?? false;
      _push = p.getBool('ud_push') ?? true;
      _notifyRadiusM = p.getInt('ud_notifyRadiusM') ?? 2000;
      _runRadiusKm = p.getDouble('ud_runRadiusKm') ?? 25;
      _minAge = p.getInt('ud_minAge') ?? 18;
      _maxAge = p.getInt('ud_maxAge') ?? 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          controller: dazuScrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            const DazuWordmark(height: 24),
            const SizedBox(height: 20),
            _buildHero(),
            const SizedBox(height: 32),
            _buildSichtbarkeitCard(),
            const SizedBox(height: 20),
            _buildSectionLabel('ENTDECKEN'),
            const SizedBox(height: 10),
            _buildRadiusCard(),
            const SizedBox(height: 20),
            _buildSectionLabel('SPRACHE'),
            const SizedBox(height: 10),
            _buildLanguageCard(),
            const SizedBox(height: 20),
            _buildSectionLabel('ALTERSGRUPPEN'),
            const SizedBox(height: 10),
            _buildAgeCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('SICHERHEIT'),
            const SizedBox(height: 10),
            _buildBlockedCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('RECHTLICHES'),
            const SizedBox(height: 10),
            _buildLegalCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('KONTO'),
            const SizedBox(height: 10),
            _buildAccountCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('FREUNDE EINLADEN'),
            const SizedBox(height: 10),
            _buildReferralCard(),
            const SizedBox(height: 24),
            _buildAdminCard(),
            _buildVersion(),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: StickyDazuHeader(isScrolled: dazuIsScrolled),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final base = GoogleFonts.bricolageGrotesque(
      fontSize: 42,
      fontWeight: FontWeight.w800,
      height: 1.02,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: DazuColors.brandViolet),
        children: [
          const TextSpan(text: 'Einstellungen'),
          TextSpan(
            text: '.',
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String s) {
    return Row(
      children: [
        const DazuIcon('SetSichtbarkeit',
            size: 14, color: DazuColors.brandViolet),
        const SizedBox(width: 6),
        Text(
          s,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: DazuColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildSichtbarkeitCard() {
    return _card(
      child: Column(
        children: [
          _switchRow(
            iconName: 'SetAuge',
            title: 'Auf der Karte sichtbar',
            subtitle:
                'Andere dazu-Nutzer sehen dein Profilbild — mit 20 Min Verzögerung und auf ~500m gerundet.',
            value: _visible,
            onChanged: (v) {
              setState(() => _visible = v);
              _prefs?.setBool('ud_visible', v);
              _sync.push('visible', v);
            },
          ),
          const _Divider(),
          _switchRow(
            iconName: 'SetGlocke',
            title: 'Push-Mitteilungen',
            subtitle: 'Runden & Einladungen in der Nähe',
            value: _push,
            onChanged: (v) {
              setState(() => _push = v);
              _prefs?.setBool('ud_push', v);
              _sync.push('push', v);
            },
          ),
          const _Divider(),
          _radiusPicker(
            title: 'Benachrichtigungsradius',
            subtitle:
                'Runden in dieser Entfernung lösen eine Benachrichtigung aus',
          ),
        ],
      ),
    );
  }

  Widget _radiusPicker({required String title, required String subtitle}) {
    const options = [500, 1000, 2000, 5000, 10000];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DazuIcon('SetGlocke',
                  color: DazuColors.brandViolet, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.bricolageGrotesque(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.bricolageGrotesque(
                            fontSize: 12,
                            color: DazuColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in options)
                ChoiceChip(
                  label: Text(m < 1000 ? '${m}m' : '${m ~/ 1000} km'),
                  selected: m == _notifyRadiusM,
                  onSelected: (_) {
                    setState(() => _notifyRadiusM = m);
                    _prefs?.setInt('ud_notifyRadiusM', m);
                    _sync.push('notifyRadiusM', m);
                  },
                  labelStyle: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700,
                    color: m == _notifyRadiusM
                        ? Colors.white
                        : DazuColors.brandNight,
                  ),
                  selectedColor: DazuColors.brandOrange,
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: DazuColors.brandViolet.withValues(alpha: 0.2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard() {
    // Live auf Sprachwechsel reagieren (Flagge + Haken wandern).
    final l10n = L10n.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DazuColors.brandLavender.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < AppLanguage.values.length; i++) ...[
            _buildLanguageRow(AppLanguage.values[i], l10n),
            if (i < AppLanguage.values.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 1,
                  color: DazuColors.textTertiary.withValues(alpha: 0.15),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageRow(AppLanguage lang, L10n l10n) {
    final isActive = l10n.language == lang;
    return InkWell(
      onTap: () => l10n.setLanguage(lang),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: DazuColors.textPrimary,
                    ),
                  ),
                  Text(
                    lang.shortCode,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DazuColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: DazuColors.brandViolet,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadiusCard() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DazuIcon('SetRadius',
                    color: DazuColors.brandViolet, size: 22),
                const SizedBox(width: 10),
                Text('RUNDEN-RADIUS',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: DazuColors.textTertiary,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _runRadiusKm >= 25 ? '∞' : '${_runRadiusKm.toInt()}',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandNight,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _runRadiusKm >= 25 ? 'Unbegrenzt' : 'km',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DazuColors.textSecondary,
                  ),
                ),
              ],
            ),
            Slider(
              value: _runRadiusKm,
              min: 0.5,
              max: 25,
              activeColor: DazuColors.brandViolet,
              inactiveColor: DazuColors.brandLavender,
              onChanged: (v) {
                setState(() => _runRadiusKm = v);
                _prefs?.setDouble('ud_runRadiusKm', v);
                _sync.push('runRadiusKm', v);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in const ['500m', '1km', '2km', '5km', '10km', '25km', '∞'])
                  Text(s,
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 10,
                          color: DazuColors.textTertiary,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeCard() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_minAge – ${_maxAge >= 60 ? "60+" : _maxAge} Jahre',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandNight,
              ),
            ),
            const SizedBox(height: 10),
            RangeSlider(
              values: RangeValues(_minAge.toDouble(), _maxAge.toDouble()),
              min: 18,
              max: 60,
              divisions: 42,
              activeColor: DazuColors.brandViolet,
              inactiveColor: DazuColors.brandLavender,
              onChanged: (r) {
                setState(() {
                  _minAge = r.start.round();
                  _maxAge = r.end.round();
                });
                _prefs?.setInt('ud_minAge', _minAge);
                _prefs?.setInt('ud_maxAge', _maxAge);
                _sync.push('minAge', _minAge);
                _sync.push('maxAge', _maxAge);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedCard() {
    return _card(
      child: InkWell(
        onTap: () => _openBlockedList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const DazuIcon('SetBlockiert',
                  color: DazuColors.brandViolet, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Blockierte Nutzer',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Blockierte Hosts sehen deine Runden nicht und tauchen bei dir nicht auf.',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 12,
                        color: DazuColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: DazuColors.brandNight.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  void _openBlockedList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _BlockedListSheet(service: BlockReportService()),
    );
  }

  Widget _buildLegalCard() {
    return _card(
      child: Column(
        children: [
          _legalRow(
            iconName: 'SetSchloss',
            title: 'Datenschutz',
            url: 'https://dazuapp.com/datenschutz',
          ),
          const _Divider(),
          _legalRow(
            iconName: 'SetDokument',
            title: 'Nutzungsbedingungen',
            url: 'https://dazuapp.com/nutzungsbedingungen',
          ),
          const _Divider(),
          _legalRow(
            iconName: 'SetInfo',
            title: 'Impressum',
            url: 'https://dazuapp.com/impressum',
          ),
        ],
      ),
    );
  }

  Widget _legalRow({
    required String iconName,
    required String title,
    required String url,
  }) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            DazuIcon(iconName, color: DazuColors.brandViolet, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: DazuColors.brandNight.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return _card(
      child: Column(
        children: [
          _actionRow(
            iconName: 'SetAbmelden',
            title: 'Abmelden',
            color: DazuColors.brandViolet,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
          const _Divider(),
          _actionRow(
            iconName: 'SetKontoLoeschen',
            title: 'Konto löschen',
            color: Colors.red,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required String iconName,
    required String title,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            DazuIcon(iconName, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              title,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DazuColors.brandCream,
        title: Text(
          'Konto wirklich löschen?',
          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Deine Daten werden sofort entfernt. Diese Aktion lässt sich nicht rückgängig machen.',
          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseDatabase.instance.ref('users').child(user.uid).remove();
      await user.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht löschen: $e')),
      );
    }
  }

  /// Referral-Card: zeigt den Code des Users (lila Pill), hat „Kopieren"
  /// und „Teilen" nebeneinander. Spiegelt die iOS-Settings-Row.
  Widget _buildReferralCard() {
    return FutureBuilder<String?>(
      future: ReferralService().ensureCode(),
      builder: (ctx, snap) {
        final code = snap.data;
        if (code == null || code.isEmpty) {
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Code wird geladen …'),
                ],
              ),
            ),
          );
        }
        final link = 'https://dazuapp.com/r/$code';
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dein Code',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: DazuColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: DazuColors.brandLavender,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    code,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Jeder Freund, der sich mit deinem Code anmeldet, zählt',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 12,
                    color: DazuColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Link kopiert')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Kopieren'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DazuColors.brandViolet,
                          side: BorderSide(
                            color: DazuColors.brandViolet
                                .withValues(alpha: 0.3),
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          SharePlus.instance.share(ShareParams(
                            text:
                                'Komm auf dazu — spontan treffen, keine Chats. $link',
                          ));
                        },
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: const Text('Teilen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DazuColors.brandViolet,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminCard() {
    // Nur sichtbar wenn `/users/<me>/isAdmin == true`. Rules sorgen
    // dafür, dass fremde User die Admin-Aktion nicht ausführen können.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return FutureBuilder<DatabaseEvent>(
      future: FirebaseDatabase.instance
          .ref('users')
          .child(uid)
          .child('isAdmin')
          .once(),
      builder: (ctx, snap) {
        if (snap.data?.snapshot.value != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel('ADMIN'),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    _actionRow(
                      iconName: 'SetAdminPanel',
                      title: 'Demo-Runden seeden',
                      color: DazuColors.brandOrange,
                      onTap: _seedDemo,
                    ),
                    const _Divider(),
                    _actionRow(
                      iconName: 'SetKreuz',
                      title: 'Demo-Runden löschen',
                      color: Colors.red,
                      onTap: _purgeDemo,
                    ),
                    const _Divider(),
                    _actionRow(
                      iconName: 'SetBlockiert',
                      title: 'Mock-Freunde löschen',
                      color: Colors.red,
                      onTap: _purgeMockFriends,
                    ),
                    const _Divider(),
                    _actionRow(
                      iconName: 'SetBlockiert',
                      title: 'Reliability-Score zurücksetzen',
                      color: Colors.red,
                      onTap: _resetReliability,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _purgeDemo() async {
    final removed = await AdminSeedService().purgeDemoRunden();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$removed Demo-Runden gelöscht.')),
    );
  }

  Future<void> _purgeMockFriends() async {
    final removed = await AdminSeedService().purgeMockFriends();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$removed Mock-Freunde gelöscht.')),
    );
  }

  Future<void> _resetReliability() async {
    final prefs = await SharedPreferences.getInstance();
    // Alle ReliabilityScore-Keys + die beiden Erst-Bonus-Flags.
    const keys = [
      'ud_reliabilityShows',
      'ud_reliabilityNoShows',
      'ud_reliabilityHostOK',
      'ud_reliabilityStreakB',
      'ud_reliabilityFirstB',
      'ud_reliabilityInviteB',
      'ud_reliabilityNewcB',
      'ud_reliabilityAppInvB',
      'ud_reliabilityCreateB',
      'ud_reliabilityBoostB',
      'ud_reliabilityStreak',
      'ud_firstHostBonusReceived',
      'ud_firstJoinBonusReceived',
    ];
    for (final k in keys) {
      await prefs.remove(k);
    }
    await ReliabilityService.instance.resetAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reliability-Score zurückgesetzt.')),
    );
  }

  Future<void> _seedDemo() async {
    final loc = LocationService();
    final pos = await loc.getCurrent();
    final count = await AdminSeedService().seedDemoRunden(
      centerLat: pos?.latitude ?? LocationService.fallbackLat,
      centerLng: pos?.longitude ?? LocationService.fallbackLng,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count Demo-Runden angelegt.')),
    );
  }

  Widget _buildVersion() {
    return Center(
      child: Column(
        children: [
          Text(
            'dazu',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandViolet.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Version 1.0 (Android Preview)',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DazuColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: DazuColors.brandLavender.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _switchRow({
    required String iconName,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DazuIcon(iconName, color: DazuColors.brandViolet, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 12,
                        color: DazuColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DazuColors.brandOrange,
            activeTrackColor: DazuColors.brandOrange.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.6,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: DazuColors.brandViolet.withValues(alpha: 0.1),
    );
  }
}

/// Liste der blockierten Nutzer mit Unblock-Button pro Zeile.
class _BlockedListSheet extends StatelessWidget {
  const _BlockedListSheet({required this.service});

  final BlockReportService service;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return StreamBuilder<List<BlockedUser>>(
          stream: service.watchBlocked(),
          builder: (ctx, snap) {
            final list = snap.data ?? const <BlockedUser>[];
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              children: [
                Text(
                  'Blockierte Nutzer',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandNight,
                  ),
                ),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Keiner blockiert.',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DazuColors.textSecondary,
                      ),
                    ),
                  ),
                for (final b in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.name,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: DazuColors.brandNight,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => service.unblock(b.uid),
                          child: Text(
                            'Entsperren',
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w800,
                              color: DazuColors.brandViolet,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

}

/// Modal-Sheet für die Code-Eingabe + Success-Anzeige. Identisches UX
/// wie iOS' RedeemOGCodeSheet.
class _RedeemOGSheet extends StatefulWidget {
  const _RedeemOGSheet();

  @override
  State<_RedeemOGSheet> createState() => _RedeemOGSheetState();
}

class _RedeemOGSheetState extends State<_RedeemOGSheet> {
  final _codeController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;
  int? _successNumber;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag indicator
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Wortmarke + Label
              RichText(
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: DazuColors.brandNight,
                      letterSpacing: -0.5),
                  children: const [
                    TextSpan(text: 'dazu'),
                    TextSpan(
                        text: '.',
                        style: TextStyle(color: DazuColors.brandOrange)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text('01/50 bis 50/50',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: const Color(0x991C1230))),
              const SizedBox(height: 24),

              if (_successNumber != null)
                _buildSuccess(_successNumber!)
              else
                _buildInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Column(
      children: [
        Text('Code eintippen',
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: DazuColors.brandNight)),
        const SizedBox(height: 10),
        TextField(
          controller: _codeController,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          autofocus: true,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'DAZU-XXXX',
            hintStyle: TextStyle(
                color: Colors.black.withValues(alpha: 0.25),
                fontWeight: FontWeight.w900),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: DazuColors.brandViolet.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: DazuColors.brandViolet.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: DazuColors.brandViolet, width: 1.5),
            ),
          ),
          onChanged: (v) {
            final filtered = v.toUpperCase().replaceAll(
                RegExp(r'[^A-Z0-9-]'), '');
            if (filtered != v) {
              _codeController.value = TextEditingValue(
                text: filtered,
                selection: TextSelection.collapsed(offset: filtered.length),
              );
            }
            setState(() {});
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(_errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _codeController.text.length >= 4
                  ? DazuColors.brandViolet
                  : DazuColors.brandViolet.withValues(alpha: 0.4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            onPressed: (_submitting || _codeController.text.length < 4)
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Einlösen',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Codes vergibt Dennis per Instagram-DM. Nur die ersten 50 bekommen eine Nummer.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11, color: Colors.black.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildSuccess(int n) {
    final num = n.toString().padLeft(2, '0');
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFF7664FF), DazuColors.brandViolet, Color(0xFF3826C4)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(r),
          child: Text('$num/50',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        ),
        const SizedBox(height: 10),
        Text('Du bist Nr. $n von 50.',
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DazuColors.brandNight)),
        const SizedBox(height: 6),
        Text('Deine Insider-Nummer ist jetzt in deinem Profil sichtbar.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.65))),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DazuColors.brandViolet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Alles klar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final number = await OGCodeService.redeem(_codeController.text);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _successNumber = number;
      });
    } on OGCodeError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString();
      });
    }
  }
}
