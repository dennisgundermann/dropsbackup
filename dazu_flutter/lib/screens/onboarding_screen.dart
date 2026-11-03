import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_wordmark.dart';

/// Onboarding: Name (falls Google-DisplayName fehlt) → Geburtstag →
/// Done. Spiegelt den iOS-Flow (`profile` + `birthday`) runter auf
/// Flutter — ohne Intro-Slides für Android v1.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _OnboardStep { name, birthday, gender, underage, done }

class _OnboardingScreenState extends State<OnboardingScreen> {
  final UserProfileService _profile = UserProfileService();
  final TextEditingController _name = TextEditingController();
  DateTime? _birthday;
  String? _gender; // 'weiblich' | 'maennlich' | 'divers' | null = übersprungen
  bool _saving = false;
  late _OnboardStep _step;

  @override
  void initState() {
    super.initState();
    final existing = FirebaseAuth.instance.currentUser?.displayName ?? '';
    _name.text = existing;
    // Google liefert i.d.R. direkt einen Namen → Name-Step überspringen.
    _step = existing.trim().isEmpty ? _OnboardStep.name : _OnboardStep.birthday;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Wann hast du Geburtstag?',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _goToGender() async {
    if (_birthday == null) return;
    final age = UserProfileService.ageInYears(_birthday!);
    if (age < 18) {
      setState(() => _step = _OnboardStep.underage);
      return;
    }
    setState(() => _step = _OnboardStep.gender);
  }

  Future<void> _finish() async {
    if (_birthday == null) return;
    setState(() => _saving = true);
    try {
      await _profile.saveBirthday(
        _birthday!,
        name: _name.text.trim(),
        gender: _gender,
      );
      if (!mounted) return;
      setState(() => _step = _OnboardStep.done);
      // Done-Screen kurz zeigen und dann weg (AppRouter re-evaluated).
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      // Kein Navigator.pop — der AppRouter hört auf isOnboarded und
      // wechselt automatisch zur MainShell sobald wir hier `done` sind.
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht speichern: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E3FF), // Lavendel wie iOS
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _OnboardStep.name:
        return _buildNameStep();
      case _OnboardStep.birthday:
        return _buildBirthdayStep();
      case _OnboardStep.gender:
        return _buildGenderStep();
      case _OnboardStep.underage:
        return _buildUnderageStep();
      case _OnboardStep.done:
        return _buildDoneStep();
    }
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DazuWordmark(height: 28),
        const Spacer(flex: 2),
        _hero('Wie heißt', 'du?'),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          autofocus: true,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: DazuColors.brandViolet,
          ),
          decoration: InputDecoration(
            hintText: 'Dennis',
            hintStyle: GoogleFonts.bricolageGrotesque(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandViolet.withValues(alpha: 0.3),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                color: DazuColors.brandViolet,
                width: 1,
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                color: DazuColors.brandViolet,
                width: 2,
              ),
            ),
          ),
        ),
        const Spacer(flex: 3),
        _primaryButton(
          'Weiter',
          onTap: _name.text.trim().isEmpty
              ? null
              : () => setState(() => _step = _OnboardStep.birthday),
        ),
      ],
    );
  }

  Widget _buildBirthdayStep() {
    final txt = _birthday == null
        ? 'Geburtstag wählen'
        : '${_birthday!.day}.${_birthday!.month}.${_birthday!.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DazuWordmark(height: 28),
        const Spacer(flex: 2),
        _hero('Wann hast du', 'Geburtstag?'),
        const SizedBox(height: 24),
        Text(
          'Nur du siehst dein Alter — wir zeigen anderen „ab 25" o.ä.',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            color: DazuColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: _pickBirthday,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: const BorderSide(color: DazuColors.brandViolet, width: 1.5),
          ),
          child: Text(
            txt,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandViolet,
            ),
          ),
        ),
        const Spacer(flex: 3),
        _primaryButton(
          'Weiter',
          onTap: _birthday == null ? null : _goToGender,
        ),
      ],
    );
  }

  Widget _buildGenderStep() {
    Widget option(String label, String? value) {
      final selected = _gender == value;
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: selected ? DazuColors.brandViolet : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? DazuColors.brandViolet
                  : DazuColors.brandViolet.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: selected ? DazuColors.brandCream : DazuColors.brandViolet,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DazuWordmark(height: 28),
        const Spacer(flex: 2),
        _hero('Als was fühlst', 'du dich?'),
        const SizedBox(height: 24),
        Text(
          'Freiwillig. Schaltet den „nur Frauen"-Filter für Runden frei.',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            color: DazuColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        option('Weiblich', 'weiblich'),
        const SizedBox(height: 10),
        option('Männlich', 'maennlich'),
        const SizedBox(height: 10),
        option('Divers', 'divers'),
        const Spacer(flex: 3),
        _primaryButton(
          _saving ? 'Speichert …' : 'Fertig',
          onTap: _saving ? null : _finish,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() => _gender = null);
                    _finish();
                  },
            child: Text(
              'Überspringen',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DazuColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnderageStep() {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Noch zu früh.',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dazu ist für Leute ab 18. Komm wieder sobald es passt — '
            'wir sind dann immer noch da.',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () async {
              await widget.auth.signOut();
            },
            child: Text(
              'Abmelden',
              style: GoogleFonts.bricolageGrotesque(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DazuWordmark(height: 48),
          const SizedBox(height: 24),
          Text(
            'Alles klar.',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandViolet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(String black, String violet) {
    final base = GoogleFonts.bricolageGrotesque(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      height: 1.02,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: DazuColors.brandNight),
        children: [
          TextSpan(text: '$black\n'),
          TextSpan(
            text: violet,
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, {VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: DazuColors.brandViolet,
          disabledBackgroundColor:
              DazuColors.brandViolet.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        child: Text(
          label,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: DazuColors.brandCream,
          ),
        ),
      ),
    );
  }
}
