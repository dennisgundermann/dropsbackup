import 'package:flutter/material.dart';

import '../models/first_drop_celebration.dart';
import '../theme/dazu_colors.dart';

/// Celebration-Sheet nach dem ERSTEN Drop. Portiert aus iOS
/// `FirstDropCelebration` + Sheet-Content in `AppStore` /
/// `CreateDropView`. Zwei Varianten:
///   • `FirstDropCelebration.created` — User hat seinen allerersten
///     eigenen Drop erstellt (+10 Pkt Host-Bonus-Flag).
///   • `FirstDropCelebration.joined` — User ist seinem allerersten
///     fremden Drop beigetreten.
///
/// Verwendung:
/// ```dart
/// await showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   useSafeArea: true,
///   builder: (_) => FirstDropCelebrationSheet(
///     variant: FirstDropCelebration.created,
///   ),
/// );
/// ```
class FirstDropCelebrationSheet extends StatefulWidget {
  const FirstDropCelebrationSheet({super.key, required this.variant});
  final FirstDropCelebration variant;

  @override
  State<FirstDropCelebrationSheet> createState() =>
      _FirstDropCelebrationSheetState();
}

class _FirstDropCelebrationSheetState extends State<FirstDropCelebrationSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _emojiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    _emojiCtrl.forward();
  }

  @override
  void dispose() {
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final v = widget.variant;
    return Container(
      height: size.height * 0.70,
      decoration: const BoxDecoration(
        color: DazuColors.brandCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 20),
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _emojiCtrl,
                        curve: Curves.elasticOut,
                      ),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              DazuColors.brandOrange,
                              DazuColors.brandViolet,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: DazuColors.brandViolet
                                  .withValues(alpha: 0.3),
                              blurRadius: 32,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          v == FirstDropCelebration.created
                              ? Icons.celebration_rounded
                              : Icons.waving_hand_rounded,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      v.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      v.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: DazuColors.brandNight.withValues(alpha: 0.7),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: DazuColors.brandViolet.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 14, color: DazuColors.brandViolet),
                          SizedBox(width: 6),
                          Text(
                            '+10 Pkt Erst-Bonus',
                            style: TextStyle(
                              color: DazuColors.brandViolet,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
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
                child: const Text('Los!'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
