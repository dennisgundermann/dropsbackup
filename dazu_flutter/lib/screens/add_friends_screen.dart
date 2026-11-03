import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../services/contacts_match_service.dart';
import '../services/friend_requests_service.dart';
import '../services/referral_service.dart';
import '../theme/dazu_colors.dart';

/// „Aus Kontakten hinzufügen"-Flow: fragt Kontakte-Permission, matched
/// gegen Firebase-phoneIndex und zeigt eine Liste der Freunde die schon
/// bei dazu sind. Pro Zeile ein Request-Button.
class AddFriendsScreen extends StatefulWidget {
  const AddFriendsScreen({super.key});

  @override
  State<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends State<AddFriendsScreen> {
  final ContactsMatchService _match = ContactsMatchService();
  final FriendRequestsService _requests = FriendRequestsService();
  bool _loading = true;
  List<MatchedContact> _matches = const [];
  final Set<String> _sent = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _match.loadMatches();
      if (!mounted) return;
      setState(() {
        _matches = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DazuColors.brandCream,
      appBar: AppBar(
        backgroundColor: DazuColors.brandCream,
        foregroundColor: DazuColors.brandNight,
        elevation: 0,
        title: Text(
          'Aus Kontakten',
          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _buildIncomingSection(),
          _buildInviteRow(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _matches.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        itemCount: _matches.length,
                        separatorBuilder: (_, i) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, i) => _tile(_matches[i]),
                      ),
          ),
        ],
      ),
    );
  }

  /// Zeigt reinkommende Freundesanfragen oben als Pills. Tap → accept.
  Widget _buildIncomingSection() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _requests.watchIncoming(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <FriendRequest>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          width: double.infinity,
          color: DazuColors.brandLavender,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${list.length} ${list.length == 1 ? 'Anfrage' : 'Anfragen'} an dich',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: DazuColors.brandNight,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in list)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () async {
                        await _requests.accept(r.senderUID);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '${r.senderName} angenommen.')),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: DazuColors.brandViolet
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              r.senderName,
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: DazuColors.brandViolet,
                              ),
                            ),
                            Text(
                              '.',
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: DazuColors.brandOrange,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.check,
                                size: 14,
                                color: DazuColors.brandOrange),
                          ],
                        ),
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

  /// „Freund direkt einladen"-Row: öffnet Share-Sheet mit dem Referral-
  /// Deep-Link. Spiegelt iOS AddFriends-Hero.
  Widget _buildInviteRow() {
    return FutureBuilder<String?>(
      future: ReferralService().ensureCode(),
      builder: (ctx, snap) {
        final code = snap.data;
        if (code == null || code.isEmpty) return const SizedBox.shrink();
        final link = 'https://dazuapp.com/r/$code';
        return InkWell(
          onTap: () {
            SharePlus.instance.share(ShareParams(
              text:
                  'Komm auf dazu — spontan treffen, keine Chats. $link',
            ));
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: DazuColors.brandLavender,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.ios_share,
                      color: DazuColors.brandViolet, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Freund direkt einladen',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: DazuColors.brandNight,
                        ),
                      ),
                      Text(
                        'Teilt deinen Code: $code',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 12,
                          color: DazuColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: DazuColors.brandViolet),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phonelink_ring,
                size: 56, color: DazuColors.brandViolet),
            const SizedBox(height: 16),
            Text(
              'Niemand aus deinen Kontakten ist bei dazu',
              textAlign: TextAlign.center,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandNight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sobald jemand aus deinem Telefonbuch die App installiert, siehst du sie hier.',
              textAlign: TextAlign.center,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 13,
                color: DazuColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(MatchedContact c) {
    final sent = _sent.contains(c.uid);
    final color = DazuColors.monogramPalette[
        c.name.hashCode.abs() % DazuColors.monogramPalette.length];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Text(
          c.name.characters.first.toUpperCase(),
          style: GoogleFonts.bricolageGrotesque(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        c.name,
        style: GoogleFonts.bricolageGrotesque(
          fontWeight: FontWeight.w800,
          color: DazuColors.brandNight,
        ),
      ),
      subtitle: Text(
        c.phone,
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 12,
          color: DazuColors.textSecondary,
        ),
      ),
      trailing: TextButton(
        onPressed: sent
            ? null
            : () async {
                await _requests.sendRequest(c.uid);
                if (!mounted) return;
                setState(() => _sent.add(c.uid));
              },
        style: TextButton.styleFrom(
          backgroundColor: sent
              ? DazuColors.brandLavender
              : DazuColors.brandOrange,
          foregroundColor: sent ? DazuColors.brandViolet : Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        child: Text(
          sent ? 'Angefragt' : 'Hinzufügen',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
