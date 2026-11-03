import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Pendant zu iOS `AppStore.checkMinSupportedVersion()`. Liest den Pfad
/// `/config/minSupportedVersion` (dazu wird derselbe Firebase-Pfad wie
/// in iOS verwendet, damit beide Apps gemeinsam geblockt werden können)
/// und vergleicht ihn semver-mäßig mit der laufenden App-Version.
class ForceUpdateService {
  ForceUpdateService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Returns true, wenn die aktuelle App-Version unterhalb des
  /// Mindest-Supports liegt und der User den Play-Store öffnen muss.
  /// Liest ZUERST `/config/androidMinSupportedVersion` — iOS- und
  /// Android-Builds haben eigene Versionsschemas, deswegen eigene Keys.
  /// Fehler (Pfad existiert nicht, offline) → false, damit die App im
  /// Zweifel benutzbar bleibt.
  Future<bool> requiresForceUpdate() async {
    try {
      final snap =
          await _db.ref('config/androidMinSupportedVersion').get();
      final minVersion = snap.value?.toString();
      if (minVersion == null || minVersion.isEmpty) return false;
      final info = await PackageInfo.fromPlatform();
      return _isLessThan(info.version, minVersion);
    } catch (_) {
      return false;
    }
  }

  bool _isLessThan(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] < pb[i]) return true;
      if (pa[i] > pb[i]) return false;
    }
    return false;
  }

  List<int> _parse(String v) {
    final parts = v.split('.').take(3).toList();
    final nums = parts.map((p) => int.tryParse(p) ?? 0).toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }
}
