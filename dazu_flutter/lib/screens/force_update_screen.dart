import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/dazu_colors.dart';
import '../widgets/dazu_icons.dart';
import '../widgets/dazu_wordmark.dart';

/// Blockiert die ganze App, wenn die laufende Version unter
/// `/config/minSupportedVersion` liegt. Entspricht iOS `ForceUpdateView`
/// aus `SharedComponents.swift`.
///
/// Design: Cream-Hintergrund, dazu-Wordmark, lila/orange Hero,
/// pulsierender Missing-Dot als Zeichen „da fehlt noch was", großer
/// „Jetzt aktualisieren"-Button öffnet den Play-Store.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DazuColors.brandCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            children: [
              const DazuWordmark(height: 24),
              const Spacer(),
              const DazuMissingDotIcon(size: 64),
              const SizedBox(height: 24),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandNight,
                    height: 1.1,
                  ),
                  children: [
                    const TextSpan(text: 'Zeit für ein\n'),
                    TextSpan(
                      text: 'Update',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandViolet,
                      ),
                    ),
                    TextSpan(
                      text: '.',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Diese Version wird nicht mehr unterstützt. Lad kurz die neue Version — dann geht\'s weiter.',
                textAlign: TextAlign.center,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DazuColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _openStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DazuColors.brandViolet,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  child: Text(
                    'Jetzt aktualisieren',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    // Marketing-URL — der Play-Store-Deeplink leitet aus dem Browser
    // sauber in die Play-App weiter, wenn sie installiert ist.
    final uri = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.dazuapp.android');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
