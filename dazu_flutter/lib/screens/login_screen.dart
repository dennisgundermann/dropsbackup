import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_wordmark.dart';

/// Login-Screen im dazu-Look: Hero-Headline, großer „Mit Google anmelden"-
/// Button, winzige Rechts-/Datenschutz-Zeile unten. Minimal, kein
/// Scroll, kein Onboarding — das kommt später als eigener Flow.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _handleGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = 'Anmeldung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DazuWordmark(height: 28),
              const Spacer(flex: 2),
              _buildHero(),
              const SizedBox(height: 24),
              Text(
                'Spontan treffen in deiner Stadt. Keine Chats, keine Profile — nur Pläne für heute.',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  color: DazuColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(flex: 3),
              _buildGoogleButton(),
              const SizedBox(height: 12),
              _buildPhoneButton(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 13,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(child: _buildLegalLine()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalLine() {
    final small = GoogleFonts.bricolageGrotesque(
      fontSize: 11,
      color: DazuColors.textTertiary,
    );
    final link = small.copyWith(
      color: DazuColors.brandViolet,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w700,
    );
    TapGestureRecognizer open(String url) => TapGestureRecognizer()
      ..onTap = () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: small,
        children: [
          const TextSpan(text: 'Mit der Anmeldung akzeptierst du '),
          TextSpan(
            text: 'AGB',
            style: link,
            recognizer: open('https://dazuapp.com/nutzungsbedingungen.html'),
          ),
          const TextSpan(text: ' & '),
          TextSpan(
            text: 'Datenschutz',
            style: link,
            recognizer: open('https://dazuapp.com/datenschutz.html'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final base = GoogleFonts.bricolageGrotesque(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      height: 1.02,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: DazuColors.brandNight),
        children: [
          const TextSpan(text: 'Komm\n'),
          TextSpan(
            text: 'dazu',
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
          TextSpan(
            text: '.',
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _openPhoneSheet,
        icon: const Icon(Icons.phone_outlined, color: DazuColors.brandViolet),
        label: Text(
          'Mit Telefonnummer',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: DazuColors.brandViolet,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: DazuColors.brandViolet.withValues(alpha: 0.4),
            width: 1.5,
          ),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Future<void> _openPhoneSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _PhoneAuthSheet(auth: widget.auth),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _handleGoogle,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: DazuColors.brandCream,
                ),
              )
            : Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: DazuColors.brandCream,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  'G',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                ),
              ),
        label: Text(
          _loading ? 'Einen Moment …' : 'Mit Google anmelden',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: DazuColors.brandCream,
          ),
        ),
      ),
    );
  }
}

/// SMS-Flow-Sheet: Nummer eingeben → „Code anfordern" → 6-stelligen
/// SMS-Code eintippen → Firebase sign-in. Auf Android holt Firebase
/// den Code über Google Play Services oft automatisch (silent).
class _PhoneAuthSheet extends StatefulWidget {
  const _PhoneAuthSheet({required this.auth});

  final AuthService auth;

  @override
  State<_PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<_PhoneAuthSheet> {
  final _phone = TextEditingController(text: '+49');
  final _code = TextEditingController();
  String? _verificationId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final p = _phone.text.trim();
    if (p.length < 6) {
      setState(() => _error = 'Nummer ergänzen (inkl. Ländercode).');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    await widget.auth.startPhoneVerification(
      phoneNumber: p,
      onCodeSent: (vid) {
        if (!mounted) return;
        setState(() {
          _verificationId = vid;
          _sending = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _sending = false;
        });
      },
      onAutoVerified: () {
        if (mounted) Navigator.pop(context);
      },
    );
  }

  Future<void> _verifyCode() async {
    final c = _code.text.trim();
    if (c.length < 4 || _verificationId == null) return;
    setState(() => _sending = true);
    try {
      await widget.auth.verifyPhoneCode(
        verificationId: _verificationId!,
        smsCode: c,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCodeStep = _verificationId != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCodeStep ? 'SMS-Code' : 'Deine Nummer',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandNight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasCodeStep
                  ? '6-stelliger Code aus der SMS.'
                  : 'Mit Ländercode, z.B. +49 170 1234567.',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 13,
                color: DazuColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (!hasCodeStep)
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              )
            else
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 12,
                    color: Colors.red.shade700,
                  )),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _sending ? null : (hasCodeStep ? _verifyCode : _requestCode),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: DazuColors.brandCream,
                        ),
                      )
                    : Text(
                        hasCodeStep ? 'Anmelden' : 'Code anfordern',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: DazuColors.brandCream,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
