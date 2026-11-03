import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/content_filter.dart';
import '../services/location_service.dart';
import '../services/reliability_service.dart';
import '../services/runden_service.dart';
import '../theme/dazu_colors.dart';
import '../models/first_drop_celebration.dart';
import '../widgets/dazu_ring_puck.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/first_drop_celebration_sheet.dart';
import '../widgets/first_drop_coach_overlay.dart';
import '../widgets/sticky_dazu_header.dart';

/// Create-Flow: Satz-Baukasten „Ich geh … jetzt für 2h mit 10 Leuten · hier".
/// Jede unterstrichene Pille öffnet ein kleines BottomSheet mit den
/// erlaubten Werten. Finaler Button legt die Runde in Firebase RTDB ab —
/// sie erscheint sofort auf der iOS-App und auf der Flutter-Karte als Pin.
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen>
    with StickyDazuHeaderMixin, TickerProviderStateMixin {
  final RundenService _service = RundenService();
  final LocationService _location = LocationService();
  final TextEditingController _activity = TextEditingController();
  final FocusNode _activityFocus = FocusNode();

  String _when = 'Jetzt';

  /// iOS-Parität zu `CreateDropView.durationMinutes`. 0 = kein Limit
  /// (12 h-Fallback in `Runde.expiresAt`), sonst 30/60/120/240 min.
  int _durationMinutes = 120;
  int _people = 10;
  bool _publishing = false;

  /// Verfügbare Dauer-Optionen in iOS-2.0.2 (CreateDropView:533).
  static const List<MapEntry<String, int>> _durationOptions = [
    MapEntry('30 Min', 30),
    MapEntry('1 h', 60),
    MapEntry('2 h', 120),
    MapEntry('4 h', 240),
    MapEntry('Ohne Limit', 0),
  ];

  String get _durationLabel {
    for (final e in _durationOptions) {
      if (e.value == _durationMinutes) return e.key;
    }
    return '${_durationMinutes}m';
  }

  late AnimationController _shakeCtrl;

  // ── First-Drop Coach ────────────────────────────────────────────────
  /// iOS: `@AppStorage("hasCompletedFirstDropWalkthrough")`.
  static const _walkthroughDoneKey = 'hasCompletedFirstDropWalkthrough';
  bool _showCoach = false;
  final GlobalKey _coachActivityKey = GlobalKey(debugLabel: 'coach_activity');
  final GlobalKey _coachPlanKey = GlobalKey(debugLabel: 'coach_plan');
  final GlobalKey _coachStartKey = GlobalKey(debugLabel: 'coach_start');

  bool get _activityReady => _activity.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _activity.addListener(() => setState(() {}));
    _maybeShowCoach();
  }

  Future<void> _maybeShowCoach() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_walkthroughDoneKey) ?? false;
      if (!done && mounted) {
        setState(() => _showCoach = true);
      }
    } catch (_) {
      // Keine SharedPrefs → Coach lieber nicht anzeigen als zu loopen.
    }
  }

  Future<void> _completeCoach() async {
    setState(() => _showCoach = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_walkthroughDoneKey, true);
    } catch (_) {}
  }

  void _scrollCoachInto(CoachStep step) {
    final key = switch (step) {
      CoachStep.activity => _coachActivityKey,
      CoachStep.plan => _coachPlanKey,
      CoachStep.start => _coachStartKey,
    };
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  @override
  void dispose() {
    _activity.dispose();
    _activityFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _shakeActivity() {
    _shakeCtrl.forward(from: 0);
    _activityFocus.requestFocus();
  }

  Future<void> _publish() async {
    final activity = _activity.text.trim();
    if (activity.isEmpty) {
      _snack('Was willst du machen?');
      return;
    }
    // iOS-Parität: Content-Filter vor Firebase-Write, blockt Slurs /
    // Beleidigungen / sexuelle Anbahnung in 10 Sprachen. Match-Wort
    // bewusst nicht in der UI zeigen — iOS-Verhalten damit kein
    // Rate-Limit-Umgehen durch gezieltes Ausprobieren.
    final hit = ContentFilter.firstMatch(activityName: activity);
    if (hit != null) {
      _snack('Das geht so nicht. Nimm bitte eine andere Formulierung.');
      _shakeActivity();
      return;
    }
    setState(() => _publishing = true);
    try {
      // „hier" = aktuelle GPS-Position. Falls Permission abgelehnt oder
      // Services aus → München-Marienplatz als Fallback (identisch zum
      // iOS-Verhalten), damit die Runde trotzdem veröffentlicht wird.
      final pos = await _location.getCurrent();
      final lat = pos?.latitude ?? LocationService.fallbackLat;
      final lng = pos?.longitude ?? LocationService.fallbackLng;

      await _service.starteRunde(
        activityName: activity,
        lat: lat,
        lng: lng,
        radius: 500,
        maxParticipants: _people,
        durationMinutes: _durationMinutes,
        scheduledTime: _when,
      );
      // iOS-Parität (Models.swift:3349): +10 Pkt Create-Bonus.
      unawaited(ReliabilityService.instance.recordDropCreated());
      // Boost-Bonus wenn Umgebung „leer" ist (<5 aktive Runden im 2 km-
      // Umkreis) — iOS gibt dann +5 extra, damit User in dünn
      // besiedelten Städten belohnt werden.
      unawaited(_service
          .countNearbyRunden(lat: lat, lng: lng, radiusKm: 2)
          .then((n) {
        if (n < 5) ReliabilityService.instance.recordBoostBonus(5);
      }));
      // Erst-Host-Celebration (einmal pro Account) — gibt zusätzlich
      // +10 Pkt via claimFirstHostBonus und zeigt dann das Sheet.
      final isFirstHost =
          await ReliabilityService.instance.claimFirstHostBonus();
      if (!mounted) return;
      if (isFirstHost) {
        // Pop in post-frame damit das Sheet nach dem _snack kommt.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useSafeArea: true,
            builder: (_) => const FirstDropCelebrationSheet(
              variant: FirstDropCelebration.created,
            ),
          );
        });
      }
      _snack(pos == null
          ? 'Runde läuft (ohne GPS — München-Fallback)'
          : 'Runde läuft 🎉');
      _activity.clear();
    } catch (e) {
      _snack('Konnte Runde nicht starten: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
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
            const SizedBox(height: 36),
            KeyedSubtree(
              key: _coachActivityKey,
              child: _buildActivityField(),
            ),
            const SizedBox(height: 24),
            KeyedSubtree(
              key: _coachPlanKey,
              child: Column(
                children: [
                  _buildSentenceRow([
                    _PillChip(label: _when, onTap: _pickWhen),
                    const _TextChip('für'),
                    _PillChip(label: _durationLabel, onTap: _pickDuration),
                  ]),
                  const SizedBox(height: 14),
                  _buildSentenceRow([
                    const _TextChip('mit'),
                    _PillChip(label: '$_people Leuten', onTap: _pickPeople),
                    const _TextChip('·'),
                    const _PillChip(label: 'hier', onTap: null),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Center(child: _buildPuckHintPill()),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: _coachStartKey,
              child: DazuRingPuck(
                enabled: _activityReady,
                onTryWhileDisabled: _shakeActivity,
                onLockedIn: _publish,
              ),
            ),
            if (_publishing)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: StickyDazuHeader(isScrolled: dazuIsScrolled),
        ),
        if (_showCoach)
          Positioned.fill(
            child: FirstDropCoachOverlay(
              targets: {
                CoachStep.activity: _coachActivityKey,
                CoachStep.plan: _coachPlanKey,
                CoachStep.start: _coachStartKey,
              },
              onStepChange: _scrollCoachInto,
              onDone: _completeCoach,
              onSkip: _completeCoach,
            ),
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
        style: base.copyWith(color: DazuColors.brandNight),
        children: [
          const TextSpan(text: 'Lust auf eine\n'),
          TextSpan(
            text: 'Runde',
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
          TextSpan(
            text: '?',
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityField() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) {
        // 3 kurze Zyklen, abklingend — identisch zum iOS activityShake.
        final v = _shakeCtrl.value;
        final dx = v == 0 ? 0.0 : math.sin(v * math.pi * 6) * 10 * (1 - v);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ich geh',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DazuColors.brandNight,
            ),
          ),
          TextField(
            controller: _activity,
            focusNode: _activityFocus,
            autofocus: false,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandViolet,
            ),
            decoration: InputDecoration(
              hintText: 'Padel',
              hintStyle: GoogleFonts.bricolageGrotesque(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandViolet.withValues(alpha: 0.35),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: DazuColors.brandViolet.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: DazuColors.brandViolet,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pending-Pill-Hint oberhalb des Pucks — gleicher visueller Code wie
  /// die Beitrittsanfrage-Pill: lila Lavender-Pill, oranger Dot links,
  /// Text wechselt je nach Zustand. Dient als Pfeil nach oben auf den
  /// Satz-Baukasten, solange die activity leer ist.
  Widget _buildPuckHintPill() {
    final ready = _activityReady;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ready
            ? DazuColors.brandLavender
            : DazuColors.brandOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ready
              ? DazuColors.brandViolet.withValues(alpha: 0.2)
              : DazuColors.brandOrange.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: DazuColors.brandOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ready
                ? 'Zieh den Punkt in den Ring'
                : 'Was willst du machen? Trag das kurz ein',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DazuColors.brandNight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceRow(List<Widget> children) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Future<void> _pickWhen() async {
    final value = await _showPicker(
      title: 'Wann?',
      // iOS-Parität zu `scheduledTime` in `CreateDropView.swift` +
      // `Runde.scheduledStartOffset`. „Heute Abend" lässt den Drop bis
      // 23:59:59 des aktuellen Tages laufen (Server-Side via
      // Runde.scheduledStartOffset = 0 + Fallback-Window).
      options: const ['Jetzt', 'In 30 Min', 'In 1 Std', 'In 2 Std', 'Heute Abend'],
      current: _when,
    );
    if (value != null) setState(() => _when = value);
  }

  Future<void> _pickDuration() async {
    final value = await _showPicker(
      title: 'Wie lange?',
      options: _durationOptions.map((e) => e.key).toList(),
      current: _durationLabel,
    );
    if (value == null) return;
    final match = _durationOptions.firstWhere(
      (e) => e.key == value,
      orElse: () => const MapEntry('2 h', 120),
    );
    setState(() => _durationMinutes = match.value);
  }

  Future<void> _pickPeople() async {
    final value = await _showPicker(
      title: 'Wie viele?',
      options: const ['2', '4', '6', '8', '10', '12', '15'],
      current: '$_people',
    );
    if (value != null) setState(() => _people = int.parse(value));
  }

  Future<String?> _showPicker({
    required String title,
    required List<String> options,
    required String current,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final o in options)
                    ChoiceChip(
                      label: Text(o),
                      selected: o == current,
                      onSelected: (_) => Navigator.pop(ctx, o),
                      labelStyle: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w700,
                        color: o == current
                            ? DazuColors.brandCream
                            : DazuColors.brandNight,
                      ),
                      selectedColor: DazuColors.brandViolet,
                      backgroundColor: DazuColors.brandLavender,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: DazuColors.brandViolet.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unterstrichene Pille für wählbare Satzbestandteile.
class _PillChip extends StatelessWidget {
  const _PillChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: DazuColors.brandViolet,
            decoration: TextDecoration.underline,
            decorationColor: DazuColors.brandViolet.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _TextChip extends StatelessWidget {
  const _TextChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.bricolageGrotesque(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: DazuColors.brandNight,
      ),
    );
  }
}
