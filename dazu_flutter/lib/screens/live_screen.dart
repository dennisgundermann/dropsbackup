import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/join_request.dart';
import '../models/runde.dart';
import '../models/teilnehmer.dart';
import '../services/location_service.dart';
import '../services/runden_service.dart';
import '../services/toast_center.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_icons.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/sticky_dazu_header.dart';

/// Wird gezeigt wenn der eingeloggte User eine eigene Runde aktiv hat.
/// Ersetzt im mittleren Tab den CreateScreen (iOS-Pendant:
/// ActiveDropTabView). Zeigt Live-Countdown, Teilnehmer-Row und
/// „Runde beenden"-Button.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.runde});

  final Runde runde;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with StickyDazuHeaderMixin {
  final RundenService _service = RundenService();
  final LocationService _location = LocationService();
  Timer? _tick;
  Duration _remaining = Duration.zero;
  bool _relocating = false;
  bool _extending = false;
  StreamSubscription<List<Teilnehmer>>? _teilnehmerSub;
  Set<String> _knownTeilnehmer = {};

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateRemaining();
    });
    _teilnehmerSub =
        _service.watchTeilnehmer(widget.runde.id).listen(_onTeilnehmerUpdate);
  }

  void _onTeilnehmerUpdate(List<Teilnehmer> list) {
    final currentIds = list.map((t) => t.id).toSet();
    if (_knownTeilnehmer.isNotEmpty) {
      final newcomers = currentIds.difference(_knownTeilnehmer);
      for (final id in newcomers) {
        final t = list.firstWhere((x) => x.id == id);
        ToastCenter.instance.show(DazuToast(
          title: '${t.name} ist dabei',
          subtitle: 'Neuer Teilnehmer bei "${widget.runde.activityName}"',
          kind: DazuToastKind.join,
        ));
      }
    }
    _knownTeilnehmer = currentIds;
  }

  @override
  void didUpdateWidget(covariant LiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runde.id != widget.runde.id) _updateRemaining();
  }

  void _updateRemaining() {
    final diff = widget.runde.expiresAtDate.difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _teilnehmerSub?.cancel();
    super.dispose();
  }

  String _formatRemaining() {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    if (h > 0) return '$h Std $m Min';
    return '$m Min';
  }

  @override
  Widget build(BuildContext context) {
    final runde = widget.runde;
    return Stack(
      children: [
        ListView(
          controller: dazuScrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            const DazuWordmark(height: 24),
            const SizedBox(height: 20),
            _buildHero(runde),
            const SizedBox(height: 32),
            _buildCountdown(),
            const SizedBox(height: 20),
            _buildHostActions(),
            const SizedBox(height: 20),
            _buildPendingRequests(),
            _buildTeilnehmer(),
            const SizedBox(height: 24),
            _buildCancelButton(context),
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

  Widget _buildHero(Runde runde) {
    final base = GoogleFonts.bricolageGrotesque(
      fontSize: 36,
      fontWeight: FontWeight.w800,
      height: 1.05,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: DazuColors.brandNight),
        children: [
          const TextSpan(text: 'Deine Runde:\n'),
          TextSpan(
            text: runde.activityName,
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
          TextSpan(
            text: '.',
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown() {
    final total = widget.runde.expiresAtDate
        .difference(widget.runde.startAtDate)
        .inSeconds
        .clamp(1, 24 * 3600);
    final fraction = (_remaining.inSeconds / total).clamp(0.0, 1.0);
    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                backgroundColor: DazuColors.brandLavender,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  DazuColors.brandViolet,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: DazuColors.brandViolet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatRemaining(),
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandNight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Pending-Anfragen-Card: alle Users, die beitreten wollen, mit
  /// Avatar + optionaler Message + Approve/Decline. Nur sichtbar wenn
  /// mindestens eine Pending-Anfrage da ist.
  Widget _buildPendingRequests() {
    return StreamBuilder<List<JoinRequest>>(
      stream: _service.watchIncomingJoinRequests(widget.runde.id),
      builder: (ctx, snap) {
        final list = snap.data ?? const <JoinRequest>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DazuColors.brandOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DazuColors.brandOrange.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: DazuColors.brandOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${list.length} ${list.length == 1 ? 'Anfrage' : 'Anfragen'}',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: DazuColors.brandNight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < list.length; i++) ...[
                _requestTile(list[i]),
                if (i < list.length - 1)
                  Divider(
                      color: DazuColors.brandOrange.withValues(alpha: 0.3),
                      height: 18),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _requestTile(JoinRequest r) {
    final color = DazuColors.monogramPalette[
        r.name.hashCode.abs() % DazuColors.monogramPalette.length];
    final hasPhoto =
        r.profileImageURL != null && r.profileImageURL!.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: hasPhoto ? Colors.transparent : color,
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: hasPhoto
              ? Image.network(r.profileImageURL!,
                  fit: BoxFit.cover, width: 40, height: 40)
              : Text(
                  r.name.isEmpty ? '?' : r.name.characters.first.toUpperCase(),
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                  children: [
                    TextSpan(text: r.name),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: DazuColors.brandOrange),
                    ),
                    if (r.age != null)
                      TextSpan(
                        text: '  ${r.age}',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 12,
                          color: DazuColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (r.message != null && r.message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    r.message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      color: DazuColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Ablehnen',
          icon: const Icon(Icons.close, color: DazuColors.textSecondary),
          onPressed: () =>
              _service.respondToJoinRequest(
                  rundeID: widget.runde.id, request: r, accepted: false),
        ),
        Container(
          decoration: const BoxDecoration(
            color: DazuColors.brandOrange,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Annehmen',
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: () =>
                _service.respondToJoinRequest(
                    rundeID: widget.runde.id, request: r, accepted: true),
          ),
        ),
      ],
    );
  }

  Widget _buildTeilnehmer() {
    return StreamBuilder<List<Teilnehmer>>(
      stream: _service.watchTeilnehmer(widget.runde.id),
      builder: (ctx, snap) {
        final list = snap.data ?? const <Teilnehmer>[];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DazuColors.brandViolet.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Wer kommt',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandNight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${1 + list.length} / ${widget.runde.maxParticipants}',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Text(
                  'Noch keiner dabei. Teil die Runde oder warte kurz.',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 13,
                    color: DazuColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Column(
                children: [
                  _participantRow(
                    name: widget.runde.hostName,
                    profileImageURL: widget.runde.hostProfileImageURL,
                    uid: widget.runde.hostUID,
                    reliabilityPoints: widget.runde.hostReliabilityPoints,
                    isHost: true,
                  ),
                  for (final t in list)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _participantRow(
                        name: t.name,
                        profileImageURL: t.profileImageURL,
                        uid: t.id,
                        reliabilityPoints: t.reliabilityPoints,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Zeile pro Teilnehmer: Avatar + lila Name mit orangem Punkt +
  /// Badge-Row aus `/users/<uid>/badges`. Nachgezogen via FutureBuilder,
  /// damit die Row sofort rendert und die Badges nachpoppen.
  Widget _participantRow({
    required String name,
    required String? profileImageURL,
    required String uid,
    required int? reliabilityPoints,
    bool isHost = false,
  }) {
    final color = DazuColors.monogramPalette[
        name.hashCode.abs() % DazuColors.monogramPalette.length];
    final hasPhoto = profileImageURL != null && profileImageURL.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: hasPhoto ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: isHost
                ? Border.all(color: DazuColors.brandOrange, width: 2.5)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: hasPhoto
              ? Image.network(profileImageURL,
                  fit: BoxFit.cover, width: 44, height: 44)
              : Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                  children: [
                    TextSpan(text: name),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: DazuColors.brandOrange),
                    ),
                    if (isHost)
                      TextSpan(
                        text: '  Host',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DazuColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              UserBadgesCompactRow(
                uid: uid,
                reliabilityPoints: reliabilityPoints,
                isHost: isHost,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHostActions() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: _extending ? '+30 Min …' : '+30 Min',
            icon: const Icon(Icons.add,
                size: 18, color: DazuColors.brandViolet),
            onTap: _extending ? null : _extendBy30,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: _relocating ? 'Verlege …' : 'Standort verlegen',
            icon: const DazuHostIcon(size: 18),
            onTap: _relocating ? null : _relocateHere,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required Widget icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: DazuColors.brandLavender,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: DazuColors.brandViolet.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extendBy30() async {
    setState(() => _extending = true);
    try {
      await _service.verlaengereRunde(widget.runde.id, 30);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Runde um 30 Minuten verlängert')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht verlängern: $e')),
      );
    } finally {
      if (mounted) setState(() => _extending = false);
    }
  }

  Future<void> _relocateHere() async {
    // Zwei Wege: GPS „hier" oder manuelle Adresse. Cloud Function
    // onDropLocationChangedPush reverse-geocodet die Koordinaten und
    // schickt den Push mit lesbarer Adresse — unabhängig davon, welchen
    // Pfad wir hier nehmen.
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Standort verlegen',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Alle Teilnehmer bekommen die neue Adresse per Push.',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 13,
                  color: DazuColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _relocateOption(
                ctx,
                label: 'Jetzt hier verlegen',
                sub: 'GPS: deine aktuelle Position',
                icon: Icons.my_location,
                value: 'gps',
              ),
              const SizedBox(height: 8),
              _relocateOption(
                ctx,
                label: 'Adresse eintippen',
                sub: 'z. B. „Marienplatz 1, München"',
                icon: Icons.edit_location_alt_outlined,
                value: 'address',
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'gps') return _doRelocateGPS();
    if (choice == 'address') return _doRelocateAddress();
  }

  Widget _relocateOption(
    BuildContext ctx, {
    required String label,
    required String sub,
    required IconData icon,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: DazuColors.brandViolet.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: DazuColors.brandLavender,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: DazuColors.brandViolet, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandNight,
                      )),
                  Text(sub,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 12,
                        color: DazuColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: DazuColors.brandViolet),
          ],
        ),
      ),
    );
  }

  Future<void> _doRelocateGPS() async {
    setState(() => _relocating = true);
    try {
      final pos = await _location.getCurrent();
      if (pos == null) throw 'GPS nicht verfügbar';
      await _service.verlegeStandort(
        rundeID: widget.runde.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standort verlegt — Push unterwegs')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte Standort nicht verlegen: $e')),
      );
    } finally {
      if (mounted) setState(() => _relocating = false);
    }
  }

  Future<void> _doRelocateAddress() async {
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Adresse',
          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'z. B. Marienplatz 1, München',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verlegen'),
          ),
        ],
      ),
    );
    if (address == null || address.isEmpty) return;
    setState(() => _relocating = true);
    try {
      // Flutter schickt die Adresse direkt als `locationTitle` mit —
      // Cloud Function nutzt sie unverändert im Push, falls Reverse-
      // Geocode der Koordinaten dieselbe Adresse ergibt oder keine.
      // Koordinaten bleiben die bisherigen, bis der Host mit GPS
      // relocation reinkommt; so entfällt der Geocode-Call auf Client-
      // Seite komplett.
      await _service.verlegeStandort(
        rundeID: widget.runde.id,
        lat: widget.runde.lat,
        lng: widget.runde.lng,
        addressTitle: address,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse übernommen')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht verlegen: $e')),
      );
    } finally {
      if (mounted) setState(() => _relocating = false);
    }
  }

  Widget _buildCancelButton(BuildContext context) {
    // iOS 2.0.2: Beenden ist eine dezente lila Pill, nicht knallrot.
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: () async {
          final ok = await _confirmEnd();
          if (!ok) return;
          await _service.beendeRunde(widget.runde.id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Runde beendet')),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: DazuColors.brandViolet,
          side: BorderSide(
            color: DazuColors.brandViolet.withValues(alpha: 0.4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
        ),
        child: Text(
          'Runde beenden',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmEnd() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Runde beenden?',
          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w800),
        ),
        content: const Text('Alle Teilnehmer bekommen eine Benachrichtigung.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

