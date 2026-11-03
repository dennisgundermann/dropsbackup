import 'package:flutter/material.dart';

import '../theme/dazu_colors.dart';

/// First-Time-Erklärung + Bestätigung wenn der User seinen Standort mit
/// anderen Dazu-Nutzern teilen möchte. Wird IMMER gezeigt beim Aktivieren
/// des Toggles — damit der User bewusst „Ja" sagt und nicht versehentlich
/// auf sichtbar bleibt.
///
/// Portiert aus iOS `Drops/PresenceOptInSheet.swift`.
/// Verwendung:
/// ```dart
/// final ok = await showModalBottomSheet<bool>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   useSafeArea: true,
///   builder: (_) => const PresenceOptInSheet(),
/// );
/// ```
class PresenceOptInSheet extends StatelessWidget {
  const PresenceOptInSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      height: size.height * 0.92,
      decoration: const BoxDecoration(
        color: DazuColors.brandCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag indicator
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: DazuColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: DazuColors.brandLavender.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.waving_hand,
                        size: 42,
                        color: DazuColors.brandOrange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                        children: [
                          TextSpan(
                            text: 'Auf der\n',
                            style: TextStyle(color: DazuColors.brandNight),
                          ),
                          TextSpan(
                            text: 'Karte sichtbar.',
                            style: TextStyle(color: DazuColors.brandViolet),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Zeig anderen, dass du unterwegs bist. So '
                      'passieren spontane Treffen.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: DazuColors.brandNight.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: const [
                        _Bullet(
                          icon: Icons.schedule,
                          title: 'Zeitversetzt (20 Min)',
                          body: 'Andere sehen deine Position mit ~20 Min '
                              'Verzögerung. Live-Tracking ist nicht möglich.',
                        ),
                        SizedBox(height: 10),
                        _Bullet(
                          icon: Icons.gps_fixed,
                          title: 'Grob (~500 m)',
                          body: 'Deine Position wird auf ein 500 m-Grid '
                              'gerundet — nie straßengenau.',
                        ),
                        SizedBox(height: 10),
                        _Bullet(
                          icon: Icons.group,
                          title: 'Freunde sehen deinen Namen',
                          body: 'Alle sehen dein Profilbild. Nur Freunde '
                              'sehen zusätzlich den Namen.',
                        ),
                        SizedBox(height: 10),
                        _Bullet(
                          icon: Icons.bedtime,
                          title: 'Automatisch aus nach 4h',
                          body: 'Ohne neue Bewegung verschwindest du nach '
                              '4 Stunden vom Radar.',
                        ),
                        SizedBox(height: 10),
                        _Bullet(
                          icon: Icons.pan_tool_alt,
                          title: 'Jederzeit stoppbar',
                          body: 'Hier abschalten — dein Eintrag wird '
                              'sofort gelöscht.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 6,
              bottom: MediaQuery.of(context).padding.bottom + 22,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DazuColors.brandViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: const Text('Ja, sichtbar machen'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Abbrechen',
                    style: TextStyle(
                      color: DazuColors.brandNight.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DazuColors.brandLavender.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: DazuColors.brandLavender,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: DazuColors.brandViolet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: DazuColors.brandNight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DazuColors.brandNight.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
