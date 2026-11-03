import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/toast_center.dart';
import '../theme/dazu_colors.dart';
import 'dazu_icons.dart';

/// Dünnes Overlay über der MainShell, das den aktuellen Toast von
/// [ToastCenter] oben einfliegen lässt. Portiert aus iOS
/// `SharedComponents.DynamicToast` — Lavender-Pill mit Icon-Pastille,
/// Titel + optionale Subline, Tap zum Dismiss.
class DazuToastOverlay extends StatefulWidget {
  const DazuToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<DazuToastOverlay> createState() => _DazuToastOverlayState();
}

class _DazuToastOverlayState extends State<DazuToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  DazuToast? _displayed;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    ToastCenter.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    ToastCenter.instance.removeListener(_onChange);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChange() {
    final next = ToastCenter.instance.current;
    if (next != null) {
      setState(() => _displayed = next);
      _ctrl.forward(from: 0);
    } else {
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _displayed = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_displayed != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: SlideTransition(
              position: _slide,
              child: _buildPill(_displayed!),
            ),
          ),
      ],
    );
  }

  Widget _buildPill(DazuToast t) {
    final icon = _iconFor(t.kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: ToastCenter.instance.dismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: DazuColors.brandLavender,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: DazuColors.brandViolet.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandNight,
                      ),
                    ),
                    if (t.subtitle != null && t.subtitle!.isNotEmpty)
                      Text(
                        t.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 12,
                          color: DazuColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconFor(DazuToastKind kind) {
    switch (kind) {
      case DazuToastKind.success:
      case DazuToastKind.join:
        return const DazuVerifiedIcon(size: 20);
      case DazuToastKind.friend:
        return const DazuReliableIcon(size: 20);
      case DazuToastKind.nearby:
        return const DazuTodayIcon(size: 20);
      case DazuToastKind.info:
        return const DazuHostIcon(size: 20);
    }
  }
}
