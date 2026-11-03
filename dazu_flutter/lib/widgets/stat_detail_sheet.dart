import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/dazu_colors.dart';

/// Modales Sheet mit Runden-Historie des Users. Pendant zu iOS
/// `StatDetailSheet(.roundsCreated / .roundsJoined)` — zeigt Liste
/// vergangener Runden mit Datum, Aktivität und Location.
class StatDetailSheet extends StatelessWidget {
  const StatDetailSheet({super.key, required this.mode});

  final StatDetailMode mode;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final nodeName = mode == StatDetailMode.hosted ? 'pastDrops' : 'pastJoins';
    final title = mode == StatDetailMode.hosted ? 'Deine Runden' : 'Beigetreten';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: DazuColors.brandCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DazuColors.brandNight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandNight,
              ),
            ),
            const SizedBox(height: 14),
            if (uid == null)
              const Text('Nicht eingeloggt.')
            else
              Expanded(
                child: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('users')
                      .child(uid)
                      .child(nodeName)
                      .onValue,
                  builder: (ctx, snap) {
                    final v = snap.data?.snapshot.value;
                    final list = _parse(v);
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          mode == StatDetailMode.hosted
                              ? 'Noch keine eigenen Runden.'
                              : 'Noch keiner Runde beigetreten.',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 14,
                            color: DazuColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      itemCount: list.length,
                      separatorBuilder: (_, i) => const Divider(height: 20),
                      itemBuilder: (ctx, i) => _row(list[i]),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_PastEntry> _parse(Object? v) {
    if (v is! Map) return const [];
    final list = <_PastEntry>[];
    v.forEach((k, raw) {
      if (raw is Map) {
        final tsRaw = raw['timestamp'] ?? raw['ts'];
        final ts = tsRaw is num ? tsRaw.toInt() : 0;
        list.add(_PastEntry(
          id: k.toString(),
          activity:
              raw['activityName']?.toString() ?? raw['activity']?.toString() ?? '—',
          place: raw['place']?.toString() ?? '',
          timestampMs: ts,
        ));
      }
    });
    list.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return list;
  }

  Widget _row(_PastEntry e) {
    final d = e.timestampMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(e.timestampMs)
        : null;
    final dateStr = d == null
        ? ''
        : '${d.day}.${d.month}.${d.year}';
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DazuColors.brandLavender,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.local_activity_outlined,
              color: DazuColors.brandViolet, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                  children: [
                    TextSpan(text: e.activity),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: DazuColors.brandOrange),
                    ),
                  ],
                ),
              ),
              if (e.place.isNotEmpty)
                Text(
                  e.place,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 12,
                    color: DazuColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 11,
                    color: DazuColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum StatDetailMode { hosted, joined }

class _PastEntry {
  _PastEntry({
    required this.id,
    required this.activity,
    required this.place,
    required this.timestampMs,
  });
  final String id;
  final String activity;
  final String place;
  final int timestampMs;
}
