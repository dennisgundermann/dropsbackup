import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Nimmt ein neues Profilbild über Kamera oder Galerie, lädt es nach
/// Firebase Storage unter `profileImages/<uid>.jpg` und schreibt die
/// Download-URL unter `/users/<uid>/profileImageURL` in RTDB — gleiche
/// Pfade wie die iOS-App, damit beide die neuen Bilder sofort anzeigen.
class AvatarService {
  final ImagePicker _picker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Öffnet den System-Picker (Galerie) und uploadet. Returnt die neue
  /// Download-URL oder `null` wenn der User abgebrochen hat.
  Future<String?> pickAndUpload({ImageSource source = ImageSource.gallery}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null) return null;

    final file = File(x.path);
    final ref = _storage.ref('profileImages/$uid.jpg');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await task.ref.getDownloadURL();

    await _db.ref('users').child(uid).child('profileImageURL').set(url);

    // Auch im Firebase-Auth-Profil setzen (für Google-Default-Fallback
    // in Flutter + iOS).
    try {
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
    } catch (_) {}

    return url;
  }
}
