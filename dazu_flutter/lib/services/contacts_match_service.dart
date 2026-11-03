import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ein Kontakt im Telefonbuch, der auch dazu-User ist.
@immutable
class MatchedContact {
  const MatchedContact({
    required this.name,
    required this.phone,
    required this.uid,
  });
  final String name;
  final String phone;
  final String uid;
}

/// Liest lokale Kontakte, normalisiert Telefonnummern (nur Ziffern +
/// führendes +) und schlägt sie in `/phoneIndex/<norm>` nach. Pendant
/// zu iOS `ContactsViewModel`.
class ContactsMatchService {
  ContactsMatchService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Fragt Permission + liest Kontakte, dann matched gegen phoneIndex.
  /// Liefert nur die Treffer (sortiert nach Name).
  Future<List<MatchedContact>> loadMatches() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return const [];

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    final seen = <String, MatchedContact>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        final norm = _normalize(p.number);
        if (norm.length < 7) continue;
        if (seen.containsKey(norm)) continue;
        try {
          final snap = await _db.ref('phoneIndex').child(norm).get();
          final v = snap.value;
          if (v is Map) {
            final uidRaw = v['uid'];
            if (uidRaw == null) continue;
            final String uid = uidRaw.toString();
            if (uid.isEmpty) continue;
            final dn = c.displayName ?? '';
            seen[norm] = MatchedContact(
              name: dn.isEmpty ? norm : dn,
              phone: norm,
              uid: uid,
            );
          }
        } catch (_) {}
      }
    }
    final list = seen.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// „+49 170 1234567" → „+491701234567". Reduziert auf +Ziffern, kein
  /// Umformen auf nationales Format.
  String _normalize(String raw) {
    final buf = StringBuffer();
    for (final c in raw.runes) {
      final ch = String.fromCharCode(c);
      if (ch == '+' && buf.isEmpty) buf.write(ch);
      if ('0123456789'.contains(ch)) buf.write(ch);
    }
    return buf.toString();
  }
}
