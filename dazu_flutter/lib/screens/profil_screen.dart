import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/encounter.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../services/encounter_service.dart';
import '../services/friend_requests_service.dart';
import '../services/friends_service.dart';
import '../services/past_rounds_service.dart';
import '../services/reliability_service.dart';
import '../services/stats_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_icons.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/encounter_row.dart';
import '../widgets/mini_map_snapshot.dart';
import '../widgets/reliability_info_sheet.dart';
import '../widgets/stat_detail_sheet.dart';
import '../widgets/sticky_dazu_header.dart';
import 'add_friends_screen.dart';

/// Profil-Tab — pendant zu iOS `FreundeView` (Hero + Badges + Statistik
/// + Dein Mix + Hotspots + Freund-hinzufügen-Buttons). Stats sind v1
/// noch nicht aus RTDB angebunden — fallen auf 0 zurück.
class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen>
    with StickyDazuHeaderMixin {
  final StatsNotifier _stats = StatsNotifier();
  final FriendsService _friendsService = FriendsService();
  final FriendRequestsService _requestsService = FriendRequestsService();
  final PastRoundsService _past = PastRoundsService();
  final AvatarService _avatar = AvatarService();
  bool _uploading = false;

  final ReliabilityService _reliability = ReliabilityService.instance;
  final EncounterService _encounters = EncounterService();
  final Set<String> _encounterRequestsSent = <String>{};

  @override
  void initState() {
    super.initState();
    _reliability.addListener(_onReliabilityChanged);
  }

  void _onReliabilityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _reliability.removeListener(_onReliabilityChanged);
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'dazu';
    final photoUrl = user?.photoURL;

    return Stack(
      children: [
        ListView(
          controller: dazuScrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            const DazuWordmark(height: 24),
            const SizedBox(height: 24),
            _buildHero(displayName, photoUrl),
            const SizedBox(height: 16),
            _buildBadgesRow(),
            const SizedBox(height: 32),
            Row(
              children: [
                _buildSectionLabel('STATISTIKEN'),
                const SizedBox(width: 10),
                _buildStreakChip(),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatsRow(),
            const SizedBox(height: 32),
            _buildSectionLabel('ZUVERLÄSSIGKEIT'),
            const SizedBox(height: 12),
            _buildReliabilityCard(),
            const SizedBox(height: 32),
            _buildSectionLabel('DEIN MIX'),
            const SizedBox(height: 12),
            _buildMixPills(),
            const SizedBox(height: 32),
            _buildSectionLabel('HOTSPOTS'),
            const SizedBox(height: 12),
            _buildHotspotPlaceholder(),
            const SizedBox(height: 32),
            _buildEncountersSection(),
            _buildIncomingRequests(),
            _buildSectionLabel('FREUNDE'),
            const SizedBox(height: 12),
            _buildFriendsList(),
            const SizedBox(height: 12),
            _buildAddFromContactsButton(),
            const SizedBox(height: 10),
            _buildInviteButton(),
            const SizedBox(height: 32),
            _buildLogoutButton(context),
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

  Future<void> _pickAvatar() async {
    setState(() => _uploading = true);
    try {
      final url = await _avatar.pickAndUpload();
      if (!mounted) return;
      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilbild aktualisiert')),
        );
        setState(() {}); // triggered rebuild damit neues photoURL greift
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildHero(String name, String? photoUrl) {
    final color = DazuColors.monogramPalette[
        name.hashCode.abs() % DazuColors.monogramPalette.length];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _uploading ? null : _pickAvatar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: DazuColors.brandOrange, width: 3.5),
                ),
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(photoUrl, fit: BoxFit.cover)
                      : Container(
                          color: color,
                          alignment: Alignment.center,
                          child: Text(
                            name.isEmpty
                                ? '?'
                                : name.characters.first.toUpperCase(),
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: DazuColors.brandViolet,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: _uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_camera,
                        size: 16, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                  children: [
                    TextSpan(text: name),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: DazuColors.brandOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '— Jahre',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DazuColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadgesRow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DatabaseEvent>(
      stream: uid == null
          ? const Stream.empty()
          : FirebaseDatabase.instance
              .ref('users')
              .child(uid)
              .onValue,
      builder: (ctx, snap) {
        final userData = snap.data?.snapshot.value;
        bool verified = false, trusted = false, host = false, circle = false;
        DateTime? createdAt;
        if (userData is Map) {
          final badges = userData['badges'];
          if (badges is Map) {
            verified = badges['verified'] == true;
            trusted = badges['trusted'] == true;
            host = badges['host'] == true;
            circle = badges['circle'] == true;
          }
          final ts = userData['createdAt'] ?? userData['onboardedAt'];
          if (ts is num) {
            final ms = ts > 1e10 ? ts.toInt() : (ts * 1000).toInt();
            createdAt = DateTime.fromMillisecondsSinceEpoch(ms);
          }
        }
        // Cutoff identisch zu iOS: Account vor 01.12.2026 → Original-Badge.
        final cutoff = DateTime(2026, 12, 1);
        final original = createdAt != null && createdAt.isBefore(cutoff);

        // Reihenfolge wie bei iOS: achieved zuerst, locked rechts.
        final slots = [
          _BadgeSlot(kind: _BadgeKind.verified, achieved: verified),
          _BadgeSlot(kind: _BadgeKind.trusted,  achieved: trusted),
          _BadgeSlot(kind: _BadgeKind.beta,     achieved: original),
          _BadgeSlot(kind: _BadgeKind.circle,   achieved: circle),
          _BadgeSlot(kind: _BadgeKind.host,     achieved: host),
        ];
        final sorted = [
          ...slots.where((s) => s.achieved),
          ...slots.where((s) => !s.achieved),
        ];
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (final s in sorted) ...[
              _dazuBadgePill(s),
              const SizedBox(width: 6),
            ],
          ],
        );
      },
    );
  }

  Widget _dazuBadgePill(_BadgeSlot slot) {
    Widget icon;
    Color bg;
    switch (slot.kind) {
      case _BadgeKind.verified:
        icon = const DazuVerifiedIcon(size: 14);
        bg = DazuColors.brandViolet.withOpacity(0.14);
        break;
      case _BadgeKind.trusted:
        icon = const DazuReliableIcon(size: 14);
        bg = DazuColors.brandViolet.withOpacity(0.14);
        break;
      case _BadgeKind.beta:
        return Opacity(
          opacity: slot.achieved ? 1.0 : 0.32,
          child: ColorFiltered(
            colorFilter: slot.achieved
                ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                : const ColorFilter.matrix([
                    0.33, 0.33, 0.33, 0, 0,
                    0.33, 0.33, 0.33, 0, 0,
                    0.33, 0.33, 0.33, 0, 0,
                    0, 0, 0, 1, 0,
                  ]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: DazuColors.brandCream,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: DazuColors.brandNight.withOpacity(0.45), width: 0.8),
              ),
              child: const MiniPolaroid(size: 14),
            ),
          ),
        );
      case _BadgeKind.circle:
        icon = Icon(Icons.people,
            size: 12, color: DazuColors.brandOrange);
        bg = DazuColors.brandViolet;
        break;
      case _BadgeKind.host:
        icon = const DazuHostIcon(size: 14);
        bg = DazuColors.brandOrange.withOpacity(0.14);
        break;
    }
    return Opacity(
      opacity: slot.achieved ? 1.0 : 0.32,
      child: ColorFiltered(
        colorFilter: slot.achieved
            ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
            : const ColorFilter.matrix([
                0.33, 0.33, 0.33, 0, 0,
                0.33, 0.33, 0.33, 0, 0,
                0.33, 0.33, 0.33, 0, 0,
                0, 0, 0, 1, 0,
              ]),
        child: Container(
          width: 28, height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.bricolageGrotesque(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: DazuColors.textTertiary,
      ),
    );
  }

  Widget _buildReliabilityCard() {
    final s = _reliability.score;
    final remaining = s.pointsToNextTier;
    final nextLabel = s.tier.next?.label;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useSafeArea: true,
          builder: (_) => ReliabilityInfoSheet(score: s),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: DazuColors.brandLavender.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: s.tier.color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(s.tier.icon, color: s.tier.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.displayLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: DazuColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.points} Pkt',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: s.tier.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: DazuColors.textTertiary,
                ),
              ],
            ),
            if (remaining != null && nextLabel != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: s.tierProgress,
                        minHeight: 6,
                        backgroundColor:
                            DazuColors.textTertiary.withValues(alpha: 0.15),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(s.tier.color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$remaining bis $nextLabel',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DazuColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return ListenableBuilder(
      listenable: _stats,
      builder: (ctx, _) {
        final s = _stats.stats;
        return Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${s.roundsHosted}',
                label: 'RUNDEN',
                onTap: () => _openStatDetail(StatDetailMode.hosted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: '${s.roundsJoined}',
                label: 'BEIGETRETEN',
                onTap: () => _openStatDetail(StatDetailMode.joined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(value: '${s.friends}', label: 'FREUNDE')),
          ],
        );
      },
    );
  }

  void _openStatDetail(StatDetailMode mode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatDetailSheet(mode: mode),
    );
  }

  Widget _buildMixPills() {
    return StreamBuilder<PastRoundsStats>(
      stream: _past.watchStats(),
      builder: (ctx, snap) {
        final mix = snap.data?.mix ?? const <MixActivity>[];
        if (mix.isEmpty) {
          return const Wrap(
            children: [_MixPill(label: 'Noch leer', count: 0)],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in mix) _MixPill(label: m.name, count: m.count),
          ],
        );
      },
    );
  }

  Widget _buildHotspotPlaceholder() {
    return StreamBuilder<PastRoundsStats>(
      stream: _past.watchStats(),
      builder: (ctx, snap) {
        final pins = snap.data?.hotspots ?? const <HotspotPin>[];
        final markers = pins.map((p) => (p.lat, p.lng)).toList();
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 160,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MiniMapSnapshot(
                    lat: pins.isEmpty ? 48.1371 : pins.first.lat,
                    lng: pins.isEmpty ? 11.5754 : pins.first.lng,
                    zoom: pins.isEmpty ? 12 : 13,
                    width: 600,
                    height: 240,
                    markers: markers,
                  ),
                ),
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: _HotspotLabel(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreakChip() {
    // iOS zeigt die aktuelle Streak-Zahl (anzahl Drops in Folge ohne
    // No-Show). Bei 0 zeigen wir nichts, damit die Row nicht leer wirkt.
    final streak = _reliability.score.currentStreak;
    final label = streak <= 0
        ? 'Diese Woche aktiv'
        : (streak == 1 ? '1 in Folge' : '$streak in Folge');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DazuColors.brandOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              size: 12, color: DazuColors.brandOrange),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncountersSection() {
    return StreamBuilder<List<Encounter>>(
      stream: _encounters.watchMine(),
      builder: (ctx, snap) {
        final list = (snap.data ?? const <Encounter>[])
            .where((e) => !e.denied)
            .take(5)
            .toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel('BEGEGNUNGEN'),
            const SizedBox(height: 12),
            for (final e in list) ...[
              EncounterRow(
                encounter: e,
                isAlreadyFriend: false, // TODO: friends-service abfragen
                requestSent: _encounterRequestsSent.contains(e.id),
                onConfirm: () => _encounters.confirm(e.id),
                onDeny: () => _encounters.deny(e.id),
                onSendFriendRequest: () {
                  final uid = e.friendUID;
                  if (uid == null) return;
                  _requestsService.sendRequest(uid);
                  setState(() => _encounterRequestsSent.add(e.id));
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 22),
          ],
        );
      },
    );
  }

  Widget _buildFriendsList() {
    return StreamBuilder<List<Freund>>(
      stream: _friendsService.watchFriends(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <Freund>[];
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DazuColors.brandLavender.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Noch keine Freunde',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandNight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lad jemanden ein — dann siehst du hier wer heute auf dazu live ist.',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DazuColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final f in list) _friendRow(f),
          ],
        );
      },
    );
  }

  Widget _friendRow(Freund f) {
    final color = DazuColors.monogramPalette[
        f.name.hashCode.abs() % DazuColors.monogramPalette.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: f.profileImageURL != null && f.profileImageURL!.isNotEmpty
                ? ClipOval(child: Image.network(f.profileImageURL!, fit: BoxFit.cover, width: 44, height: 44))
                : Text(
                    f.name.isEmpty
                        ? '?'
                        : f.name.characters.first.toUpperCase(),
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandViolet,
                ),
                children: [
                  TextSpan(text: f.name),
                  const TextSpan(
                    text: '.',
                    style: TextStyle(color: DazuColors.brandOrange),
                  ),
                  if (f.age != null)
                    TextSpan(
                      text: '  ${f.age}',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 13,
                        color: DazuColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequests() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _requestsService.watchIncoming(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <FriendRequest>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel('ANFRAGEN · ${list.length}'),
              const SizedBox(height: 12),
              for (final r in list) _requestRow(r),
            ],
          ),
        );
      },
    );
  }

  Widget _requestRow(FriendRequest r) {
    final color = DazuColors.monogramPalette[
        r.senderName.hashCode.abs() % DazuColors.monogramPalette.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DazuColors.brandLavender.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Text(
                r.senderName.characters.first.toUpperCase(),
                style: GoogleFonts.bricolageGrotesque(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${r.senderName} will dazu.',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _requestsService.decline(r.senderUID),
              child: Text('Ablehnen',
                  style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w700,
                      color: DazuColors.textSecondary)),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: DazuColors.brandOrange,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: () => _requestsService.accept(r.senderUID),
              child: Text('Dazu',
                  style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFromContactsButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddFriendsScreen()),
        ),
        icon: const Icon(Icons.contacts_outlined,
            color: DazuColors.brandViolet, size: 18),
        label: Text(
          'Aus Kontakten hinzufügen',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: DazuColors.brandViolet,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: DazuColors.brandViolet.withValues(alpha: 0.4),
            width: 1.5,
          ),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _buildInviteButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () async {
          final user = FirebaseAuth.instance.currentUser;
          final name = user?.displayName ?? 'jemand';
          // Pragma für v1 — dazuapp.com-Website ist der zentrale Share-
          // Anker. In v2: individueller Deep-Link per User-ID.
          await SharePlus.instance.share(
            ShareParams(
              text:
                  '$name hat dich zu dazu eingeladen. Spontan treffen ohne Chat: https://dazuapp.com',
            ),
          );
        },
        icon: const Icon(Icons.ios_share, color: DazuColors.brandCream, size: 18),
        label: Text(
          'Einladungslink teilen',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: DazuColors.brandCream,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: DazuColors.brandViolet,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () async {
          await widget.auth.signOut();
        },
        style: TextButton.styleFrom(
          foregroundColor: DazuColors.textTertiary,
        ),
        child: Text(
          'Abmelden',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: DazuColors.brandLavender.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandNight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: DazuColors.textTertiary,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _MixPill extends StatelessWidget {
  const _MixPill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DazuColors.brandLavender.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: DazuColors.brandViolet.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DazuColors.brandNight,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '×$count',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandViolet,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kleine „München"-Pille unten links auf der Hotspot-Mini-Map,
/// damit die Fläche nicht nackt wirkt bis echte Pins drin sind.
class _HotspotLabel extends StatelessWidget {
  const _HotspotLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on,
              size: 12, color: DazuColors.brandViolet),
          const SizedBox(width: 4),
          Text(
            'Deine Spots',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandNight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge-Kinds für die kompakte Row im Profil-Hero. Reihenfolge spiegelt
/// iOS `BadgeSlot`: Vertrauen → Zugehörigkeit → Status.
enum _BadgeKind { verified, trusted, beta, circle, host }

class _BadgeSlot {
  final _BadgeKind kind;
  final bool achieved;
  const _BadgeSlot({required this.kind, required this.achieved});
}
