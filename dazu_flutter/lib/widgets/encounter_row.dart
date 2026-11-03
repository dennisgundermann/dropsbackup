import 'package:flutter/material.dart';

import '../models/encounter.dart';
import '../theme/dazu_colors.dart';

/// Zeile im Profile/Alerts-Tab für einen vergangenen Encounter
/// („Du warst mit X beim Y unterwegs — war das wirklich ein Treffen?").
/// Portiert aus iOS `ProfileAndAlertsView.swift` → `EncounterRow`.
///
/// Vier Zustände:
///   1. unbestätigt → Buttons „Ja" / „Nein" (confirm / deny)
///   2. bestätigt + bereits befreundet → grünes ✓ „Befreundet"
///   3. bestätigt + Request raus → orange ⌛ „Angefragt"
///   4. bestätigt + nicht Freund → CTA „Freund hinzufügen"
class EncounterRow extends StatelessWidget {
  const EncounterRow({
    super.key,
    required this.encounter,
    required this.isAlreadyFriend,
    this.requestSent = false,
    this.onConfirm,
    this.onDeny,
    this.onSendFriendRequest,
  });

  final Encounter encounter;
  final bool isAlreadyFriend;
  final bool requestSent;

  final VoidCallback? onConfirm;
  final VoidCallback? onDeny;
  final VoidCallback? onSendFriendRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DazuColors.brandLavender.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          _avatar(),
          const SizedBox(width: 12),
          Expanded(child: _info()),
          const SizedBox(width: 8),
          _action(),
        ],
      ),
    );
  }

  Widget _avatar() {
    final url = encounter.friendProfileImageURL;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _emojiAvatar(),
        ),
      );
    }
    return _emojiAvatar();
  }

  Widget _emojiAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: DazuColors.brandViolet.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        encounter.friendEmoji.isEmpty ? '🙂' : encounter.friendEmoji,
        style: const TextStyle(fontSize: 24),
      ),
    );
  }

  Widget _info() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${encounter.activityEmoji} ${encounter.activityName} mit ${encounter.friendName}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DazuColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          encounter.timeAgoLabel,
          style: const TextStyle(
            fontSize: 12,
            color: DazuColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _action() {
    if (encounter.denied) {
      return _StatusChip(
        label: 'Verneint',
        color: DazuColors.textTertiary,
        icon: Icons.close,
      );
    }
    if (!encounter.confirmed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniButton(
            label: 'Nein',
            onTap: onDeny,
            foreground: DazuColors.textSecondary,
            background: DazuColors.textTertiary.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 6),
          _MiniButton(
            label: 'Ja',
            onTap: onConfirm,
            foreground: Colors.white,
            background: DazuColors.brandViolet,
          ),
        ],
      );
    }
    if (isAlreadyFriend) {
      return _StatusChip(
        label: 'Befreundet',
        color: const Color(0xFF22C55E),
        icon: Icons.check_circle,
      );
    }
    if (requestSent) {
      return _StatusChip(
        label: 'Angefragt',
        color: DazuColors.brandOrange,
        icon: Icons.hourglass_bottom,
      );
    }
    if (encounter.friendUID != null) {
      return _CTA(label: 'Freund hinzufügen', onTap: onSendFriendRequest);
    }
    return _StatusChip(
      label: 'Bestätigt',
      color: const Color(0xFF22C55E),
      icon: Icons.check_circle,
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.onTap,
    required this.foreground,
    required this.background,
  });
  final String label;
  final VoidCallback? onTap;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CTA extends StatelessWidget {
  const _CTA({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [DazuColors.brandOrange, Color(0xFF22C55E)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: DazuColors.brandOrange.withValues(alpha: 0.3),
              blurRadius: 5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_add, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
