import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/dazu_colors.dart';

/// Dreistufiger Coach-Mark fürs Erst-Rundenanlegen. Portiert aus
/// iOS `Drops/FirstDropCoachView.swift` (SwiftUI `FirstDropCoachOverlay`).
///
/// Nutzung in `CreateScreen`:
/// ```dart
/// final activityKey = GlobalKey();
/// final planKey     = GlobalKey();
/// final submitKey   = GlobalKey();
/// // … build:
/// Stack(children: [
///   buildCreateView(),
///   if (showCoach)
///     FirstDropCoachOverlay(
///       targets: {
///         CoachStep.activity: activityKey,
///         CoachStep.plan:     planKey,
///         CoachStep.start:    submitKey,
///       },
///       onDone: _completeCoach,
///       onSkip: _completeCoach,
///     ),
/// ])
/// ```
///
/// Weil Flutter keinen `.coachHighlight(active:)`-Modifier wie SwiftUI
/// hat, legen wir die anzusteuernden Sektionen über `GlobalKey`s auf,
/// die diese View dann per `RenderBox` abfragt, um Scrim-Cutout + Glow
/// zu zeichnen.
enum CoachStep {
  activity,
  plan,
  start;

  CoachStep? get next {
    final idx = CoachStep.values.indexOf(this);
    if (idx < 0 || idx + 1 >= CoachStep.values.length) return null;
    return CoachStep.values[idx + 1];
  }

  bool get isLast => next == null;
}

class FirstDropCoachOverlay extends StatefulWidget {
  const FirstDropCoachOverlay({
    super.key,
    required this.targets,
    required this.onDone,
    required this.onSkip,
    this.initialStep = CoachStep.activity,
    this.onStepChange,
  });

  /// Pro Step der GlobalKey der hervorgehobenen Sektion.
  final Map<CoachStep, GlobalKey> targets;

  /// Wird aufgerufen wenn der User den letzten Step bestätigt
  /// („Runde starten" o. ä.).
  final VoidCallback onDone;

  /// Skip-Button.
  final VoidCallback onSkip;

  final CoachStep initialStep;

  /// Hook, damit der Parent z.B. den ScrollController animieren kann.
  final void Function(CoachStep step)? onStepChange;

  @override
  State<FirstDropCoachOverlay> createState() => _FirstDropCoachOverlayState();
}

class _FirstDropCoachOverlayState extends State<FirstDropCoachOverlay>
    with SingleTickerProviderStateMixin {
  late CoachStep _step = widget.initialStep;
  Rect _highlight = Rect.zero;
  bool _isAnimating = false;

  late final AnimationController _cardCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureAndSlideIn();
    });
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── Spotlight-Messung ────────────────────────────────────────────────
  void _measureAndSlideIn() {
    final key = widget.targets[_step];
    final ctx = key?.currentContext;
    if (ctx == null) {
      // Target noch nicht aufgebaut — nächsten Frame versuchen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureAndSlideIn();
      });
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    setState(() {
      _highlight = offset & box.size;
    });
    _cardCtrl.forward(from: 0);
  }

  bool get _cardAtTop {
    if (_highlight == Rect.zero) return false;
    final screenH = MediaQuery.of(context).size.height;
    return _highlight.center.dy > screenH * 0.50;
  }

  // ── Step-Advance ─────────────────────────────────────────────────────
  Future<void> _advance() async {
    if (_isAnimating) return;
    _isAnimating = true;
    if (_step.isLast) {
      await _cardCtrl.reverse();
      _isAnimating = false;
      widget.onDone();
      return;
    }
    await _cardCtrl.reverse();
    final next = _step.next!;
    setState(() => _step = next);
    widget.onStepChange?.call(next);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _measureAndSlideIn();
    _isAnimating = false;
  }

  Future<void> _skip() async {
    if (_isAnimating) return;
    _isAnimating = true;
    await _cardCtrl.reverse();
    _isAnimating = false;
    widget.onSkip();
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          // Scrim mit Cutout
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _highlight == Rect.zero
                    ? const AlwaysStoppedAnimation(0.0)
                    : _glowCtrl,
                builder: (_, _) {
                  return CustomPaint(
                    painter: _ScrimPainter(
                      highlight: _highlight,
                      glow: _glowCtrl.value,
                    ),
                  );
                },
              ),
            ),
          ),

          // Karte
          _buildCard(),

          // Transparenter Catcher für Spotlight-Taps → Advance
          if (_highlight != Rect.zero)
            Positioned.fromRect(
              rect: _highlight.inflate(10),
              child: GestureDetector(
                onTap: _advance,
                behavior: HitTestBehavior.translucent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final atTop = _cardAtTop;
    final slide = Tween<double>(
      begin: atTop ? -600 : 600,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _cardCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    final fade = Tween<double>(begin: 0, end: 1).animate(_cardCtrl);
    return AnimatedBuilder(
      animation: _cardCtrl,
      builder: (_, child) {
        return Positioned(
          left: 12,
          right: 12,
          top: atTop ? MediaQuery.of(context).padding.top + 8 : null,
          bottom: atTop ? null : MediaQuery.of(context).padding.bottom + 8,
          child: Opacity(
            opacity: fade.value,
            child: Transform.translate(
              offset: Offset(0, slide.value),
              child: child,
            ),
          ),
        );
      },
      child: _coachCard(),
    );
  }

  Widget _coachCard() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: DazuColors.brandCream,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 28,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _progressRow(),
            const SizedBox(height: 18),
            _iconText(),
            const SizedBox(height: 22),
            _cta(),
          ],
        ),
      ),
    );
  }

  Widget _progressRow() {
    return Row(
      children: [
        for (int i = 0; i < CoachStep.values.length; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            width: i == _step.index ? 22 : 8,
            height: 6,
            decoration: BoxDecoration(
              color: i <= _step.index
                  ? DazuColors.brandViolet
                  : DazuColors.textTertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i < CoachStep.values.length - 1) const SizedBox(width: 5),
        ],
        const Spacer(),
        GestureDetector(
          onTap: _skip,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              L10n.of(context).tr('coach.skip'),
              style: const TextStyle(
                fontSize: 13,
                color: DazuColors.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconText() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: DazuColors.brandViolet.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _stepIcon(_step),
            color: DazuColors.brandViolet,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stepTitle(_step),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DazuColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _stepBody(_step),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: DazuColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cta() {
    return GestureDetector(
      onTap: _isAnimating ? null : _advance,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            colors: [DazuColors.brandOrange, DazuColors.brandViolet],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: DazuColors.brandViolet.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              L10n.of(context)
                  .tr(_step.isLast ? 'coach.start_drop' : 'coach.next'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _step.isLast ? Icons.bolt : Icons.arrow_forward,
              size: 16,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step-Inhalte ─────────────────────────────────────────────────────
  IconData _stepIcon(CoachStep s) {
    switch (s) {
      case CoachStep.activity:
        return Icons.auto_awesome;
      case CoachStep.plan:
        return Icons.schedule;
      case CoachStep.start:
        return Icons.bolt;
    }
  }

  String _stepTitle(CoachStep s) {
    switch (s) {
      case CoachStep.activity:
        return 'Was willst du machen?';
      case CoachStep.plan:
        return 'Wann & mit wie vielen?';
      case CoachStep.start:
        return 'Starten!';
    }
  }

  String _stepBody(CoachStep s) {
    switch (s) {
      case CoachStep.activity:
        return 'Schreib kurz was du vorhast — Kaffee, Spaziergang, '
            'Feierabendbier. Keep it simple, jemand kommt dazu.';
      case CoachStep.plan:
        return 'Wähl wann du loslegen willst, wie lang und mit wie '
            'vielen Leuten. Alles optional, Vorschläge passen fast immer.';
      case CoachStep.start:
        return 'Lila Ring halten → Runde geht online. Freunde und Leute '
            'in deiner Nähe sehen sie sofort.';
    }
  }
}

/// Zeichnet den dunklen Scrim mit einem RoundedRect-Loch über dem
/// Highlight-Target plus einen pulsierenden Glow.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.highlight, required this.glow});

  final Rect highlight;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final hole = highlight == Rect.zero
        ? null
        : RRect.fromRectAndRadius(highlight.inflate(10),
            const Radius.circular(20));

    final scrim = Paint()..color = const Color(0x8C000000); // 0.55 alpha
    if (hole == null) {
      canvas.drawRect(full, scrim);
      return;
    }

    // Scrim mit Cutout
    final path = Path()
      ..addRect(full)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, scrim);

    // Pulsierender Glow-Ring
    final glowStrength = 0.35 + 0.65 * glow; // 0.35–1.0
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = DazuColors.brandViolet.withValues(alpha: glowStrength);
    canvas.drawRRect(hole, stroke);

    // Weicher Schatten unter dem Ring
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = DazuColors.brandViolet.withValues(alpha: 0.6 * glowStrength)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10);
    canvas.drawRRect(hole, shadow);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.highlight != highlight || old.glow != glow;
}
