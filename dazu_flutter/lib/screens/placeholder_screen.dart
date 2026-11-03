import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/dazu_colors.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/sticky_dazu_header.dart';

/// Platzhalter-Screen während die anderen Tabs noch portiert werden.
/// Reproduziert bereits das Hero-Pattern (Inline-Logo + massive Hero-
/// Headline + Scroll-adaptiver Compact-Chip), damit sich die 5 Tabs
/// konsistent anfühlen.
class PlaceholderScreen extends StatefulWidget {
  const PlaceholderScreen({
    super.key,
    required this.heroStart,
    required this.heroViolet,
    this.heroEnd = '.',
    this.subline,
  });

  final String heroStart;
  final String heroViolet;
  final String heroEnd;
  final String? subline;

  @override
  State<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

class _PlaceholderScreenState extends State<PlaceholderScreen>
    with StickyDazuHeaderMixin {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          controller: dazuScrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 160),
          children: [
            const DazuWordmark(height: 24),
            const SizedBox(height: 20),
            _buildHero(),
            if (widget.subline != null) ...[
              const SizedBox(height: 20),
              Text(
                widget.subline!,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  color: DazuColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 400),
            Center(
              child: Text(
                'Noch nicht portiert — kommt bald.',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 14,
                  color: DazuColors.textTertiary,
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
          TextSpan(text: widget.heroStart),
          TextSpan(
            text: widget.heroViolet,
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
          TextSpan(
            text: widget.heroEnd,
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }
}
