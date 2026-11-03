import 'package:flutter_test/flutter_test.dart';
import 'package:dazu_flutter/services/content_filter.dart';

void main() {
  group('ContentFilter.hasBlockedWord', () {
    test('clean activity passes', () {
      expect(ContentFilter.hasBlockedWord('Kaffee trinken'), isFalse);
      expect(ContentFilter.hasBlockedWord('Spaziergang'), isFalse);
      expect(ContentFilter.hasBlockedWord('Feierabendbier'), isFalse);
    });

    test('direct slur blocked', () {
      expect(ContentFilter.hasBlockedWord('fick dich'), isTrue);
      expect(ContentFilter.hasBlockedWord('ARSCHLOCH'), isTrue);
      expect(ContentFilter.hasBlockedWord('puto'), isTrue);
    });

    test('leetspeak normalization', () {
      expect(ContentFilter.hasBlockedWord('f@ggot'), isTrue);
      expect(ContentFilter.hasBlockedWord('B!TCH'), isTrue);
      expect(ContentFilter.hasBlockedWord('c0ño perra'), isTrue);
    });

    test('separator obfuscation strips to full word (f.u.c.k)', () {
      // iOS-Parität: `.`, `*`, `_`, `-`, `·`, `‧` werden gestrippt, dann
      // match. `f.u.c.k.` → `fuck`, `f_u_c_k` → `fuck`. Aber `f*ck` →
      // `fck` (nicht im Blocklist), weil Separatoren KEINE Vokale sind.
      expect(ContentFilter.hasBlockedWord('f.u.c.k.'), isTrue);
      expect(ContentFilter.hasBlockedWord('f_u_c_k'), isTrue);
      expect(ContentFilter.hasBlockedWord('f-u-c-k'), isTrue);
      // Nicht gematcht — Separator ersetzt KEINE Buchstaben:
      expect(ContentFilter.hasBlockedWord('f*ck'), isFalse);
    });

    test('space-obfuscation (second pass)', () {
      expect(ContentFilter.hasBlockedWord('f u c k'), isTrue);
    });

    test('longer blocklist word matched before shorter prefix', () {
      // „arschloch" vor „arsch" (längste-zuerst in combined regex).
      final match = ContentFilter.firstMatch(activityName: 'arschloch');
      expect(match?.word, 'arschloch');
    });

    test('description-only match still fires', () {
      final hit = ContentFilter.firstMatch(
        activityName: 'Kaffee trinken',
        description: 'bringt euren muschi mit',
      );
      expect(hit, isNotNull);
      expect(hit!.inField, contains('muschi'));
    });

    test('whole-word boundary — substring does not match', () {
      // „spast" ist in Blocklist, aber „spazieren" sollte nicht matchen.
      expect(ContentFilter.hasBlockedWord('spazieren gehen'), isFalse);
    });

    test('non-ASCII slur matched (umlauts)', () {
      expect(ContentFilter.hasBlockedWord('vögeln'), isTrue);
      expect(ContentFilter.hasBlockedWord('erschießen'), isTrue);
    });

    test('empty / whitespace is clean', () {
      expect(ContentFilter.hasBlockedWord(''), isFalse);
      expect(ContentFilter.hasBlockedWord('   '), isFalse);
    });
  });

  group('ContentFilter.firstMatchInProfileName', () {
    test('clean name passes', () {
      expect(
          ContentFilter.firstMatchInProfileName('Anna Müller'), isNull);
    });

    test('slurred name blocked (standalone slur word)', () {
      // „nazi_fan" wird zu „nazifan" normalisiert (_ gestrippt) und
      // matcht wegen fehlender Wortgrenze NICHT — iOS-Parität. Nur
      // echte Standalone-Slurs greifen.
      expect(ContentFilter.firstMatchInProfileName('bitch'), isNotNull);
      expect(ContentFilter.firstMatchInProfileName('maria bitch'), isNotNull);
      expect(ContentFilter.firstMatchInProfileName('nazi'), isNotNull);
    });
  });
}
