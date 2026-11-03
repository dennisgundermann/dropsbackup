import 'dart:ui';

import 'package:flutter/material.dart';

import 'dazu_wordmark.dart';

/// Compact-dazu-Chip, der oben erscheint sobald der dahinter liegende
/// Scroll weit genug gelaufen ist — iOS-Large→Compact-Pattern aus der
/// nativen App, hier in Flutter nachgebaut: Material-Blur + Cream-
/// Lasur + weicher Alpha-Fade nach unten.
class StickyDazuHeader extends StatelessWidget {
  const StickyDazuHeader({super.key, required this.isScrolled});

  /// Steuert sichtbar/unsichtbar via Fade+Slide-Transition. Normalerweise
  /// von einem `NotificationListener<ScrollNotification>` gefüttert.
  final bool isScrolled;

  @override
  Widget build(BuildContext context) {
    final mediaTop = MediaQuery.of(context).padding.top;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: isScrolled ? Offset.zero : const Offset(0, -0.6),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: isScrolled ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Colors.black,
                Color(0x8C000000),
                Color(0x00000000),
              ],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: EdgeInsets.only(
                    top: mediaTop + 6,
                    bottom: 10,
                    left: 24,
                    right: 24,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xD9FCF4EA),
                        Color(0x8CFCF4EA),
                        Color(0x00FCF4EA),
                      ],
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: DazuWordmark(height: 18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mixin für Tab-Screens: hält den `isScrolled`-State über einen
/// ScrollController und blendet den Compact-Header ein. Threshold ist
/// konservativ auf 50px gesetzt (passt zur iOS-App-Haltung).
mixin StickyDazuHeaderMixin<T extends StatefulWidget> on State<T> {
  final ScrollController dazuScrollController = ScrollController();
  bool _dazuIsScrolled = false;

  bool get dazuIsScrolled => _dazuIsScrolled;

  double get dazuScrollThreshold => 50;

  @override
  void initState() {
    super.initState();
    dazuScrollController.addListener(_onDazuScroll);
  }

  @override
  void dispose() {
    dazuScrollController.removeListener(_onDazuScroll);
    dazuScrollController.dispose();
    super.dispose();
  }

  void _onDazuScroll() {
    final scrolled = dazuScrollController.offset > dazuScrollThreshold;
    if (scrolled != _dazuIsScrolled) {
      setState(() => _dazuIsScrolled = scrolled);
    }
  }
}
