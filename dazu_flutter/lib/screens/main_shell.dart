import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/aktive_runde_notifier.dart';
import '../services/auth_service.dart';
import '../services/deep_link_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_icon.dart';
import '../widgets/dazu_toast_overlay.dart';
import '../widgets/offline_banner.dart';
import '../widgets/runde_detail_sheet.dart';
import 'create_screen.dart';
import 'einstellungen_screen.dart';
import 'karte_screen.dart';
import 'live_screen.dart';
import 'placeholder_screen.dart';
import 'profil_screen.dart';
import 'umgebung_screen.dart';

/// 5-Tab-Shell wie in der iOS-App: Karte • Umgebung • dazu • Profil •
/// Einstellungen. Verwendet Material 3 NavigationBar — passt zum
/// Android-Launch, bleibt aber dazu-brand-konform (Lavender-Indicator,
/// Lila-Icon im Aktiv-Zustand, Nunito für die Labels).
///
/// Mittlerer Tab ist dynamisch: Create wenn kein eigener Drop läuft,
/// Live wenn ja — identisch zum iOS-Pattern (`store.isInActiveDrop`).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.auth});

  final AuthService? auth;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 1;
  int? _lastActiveFlip; // 0 = keine Runde, 1 = eigene Runde live

  final AktiveRundeNotifier _active = AktiveRundeNotifier();

  @override
  void initState() {
    super.initState();
    _active.addListener(_onActiveChanged);
    DeepLinkService.instance.pendingRunde.addListener(_onDeepLinkRunde);
  }

  @override
  void dispose() {
    _active.removeListener(_onActiveChanged);
    DeepLinkService.instance.pendingRunde.removeListener(_onDeepLinkRunde);
    _active.dispose();
    super.dispose();
  }

  /// Reagiert auf einen eingehenden `/d/<rundeID>` Deep-Link: öffnet
  /// das RundeDetailSheet und räumt den Pending-Zustand wieder weg.
  void _onDeepLinkRunde() {
    final runde = DeepLinkService.instance.pendingRunde.value;
    if (runde == null || !mounted) return;
    // Clear vor dem Open, damit ein zweiter identischer Link später
    // nochmal feuert.
    DeepLinkService.instance.pendingRunde.value = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RundeDetailSheet(runde: runde),
    );
  }

  /// Beim Übergang „keine Runde → eigene Runde läuft" (direkt nach
  /// starten) automatisch in den mittleren Tab springen damit der User
  /// den LiveScreen sieht. Beim Rückweg (Runde beendet) bleiben wir
  /// wo wir sind — der User soll nicht aus dem aktuellen Tab gerissen
  /// werden.
  void _onActiveChanged() {
    final flip = _active.hatAktiveRunde ? 1 : 0;
    if (_lastActiveFlip != flip && _active.hatAktiveRunde) {
      setState(() => _index = 2);
    }
    _lastActiveFlip = flip;
    // Trigger rebuild damit mittlerer Tab umgetauscht wird.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final aktiveRunde = _active.aktiveRunde;
    final middle = aktiveRunde != null
        ? LiveScreen(runde: aktiveRunde)
        : const CreateScreen();

    final screens = <Widget>[
      const KarteScreen(),
      const UmgebungScreen(),
      middle,
      widget.auth != null
          ? ProfilScreen(auth: widget.auth!)
          : const PlaceholderScreen(
              heroStart: '',
              heroViolet: 'Profil',
              subline: 'Nicht eingeloggt.',
            ),
      const EinstellungenScreen(),
    ];

    return DazuToastOverlay(
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(index: _index, children: screens),
            const Align(
              alignment: Alignment.topCenter,
              child: OfflineBanner(),
            ),
          ],
        ),
        // iOS-Pattern: floating pill-shaped Tab-Bar mit großzügigem
        // Side-Margin + weichem Schatten. Nicht edge-to-edge.
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: DazuColors.brandNight.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  surfaceTintColor: Colors.transparent,
                  labelTextStyle: WidgetStatePropertyAll(
                    GoogleFonts.bricolageGrotesque(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DazuColors.brandNight,
                    ),
                  ),
                ),
                child: NavigationBar(
                  height: 68,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  backgroundColor: Colors.white,
                  indicatorColor: DazuColors.brandLavender,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: _destinations(aktiveRunde != null),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<NavigationDestination> _destinations(bool live) {
    final labelStyle = GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w700,
      fontSize: 11,
    );
    // ignore: unused_local_variable
    final _ = labelStyle; // Labels nutzen das Theme-NavigationBarTheme
    // Tab-Icons OHNE color — Original-SVG-Farben bleiben erhalten,
    // so dass die orangenen dazu-Punkte sichtbar sind.
    return [
      const NavigationDestination(
        icon: DazuIcon('TabKarte', category: 'tab', size: 26),
        selectedIcon: DazuIcon('TabKarteAktiv', category: 'tab', size: 26),
        label: 'Karte',
      ),
      const NavigationDestination(
        icon: DazuIcon('TabUmgebung', category: 'tab', size: 26),
        selectedIcon: DazuIcon('TabUmgebungAktiv', category: 'tab', size: 26),
        label: 'Umgebung',
      ),
      NavigationDestination(
        icon: DazuIcon(
          live ? 'TabDazuAktiv' : 'TabDazu',
          category: 'tab',
          size: 26,
        ),
        selectedIcon: const DazuIcon('TabDazuAktiv', category: 'tab', size: 26),
        label: live ? 'Live' : 'dazu',
      ),
      const NavigationDestination(
        icon: DazuIcon('TabProfil', category: 'tab', size: 26),
        selectedIcon: DazuIcon('TabProfilAktiv', category: 'tab', size: 26),
        label: 'Profil',
      ),
      const NavigationDestination(
        icon: DazuIcon('TabEinstellungen', category: 'tab', size: 26),
        selectedIcon:
            DazuIcon('TabEinstellungenAktiv', category: 'tab', size: 26),
        label: 'Einstellungen',
      ),
    ];
  }
}
