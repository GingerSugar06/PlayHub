/// **Oyun şeması** — başarım tanımlarını Steam'in önbelleğinden okur.
///
/// Kaynak: `appcache/stats/UserGameStatsSchema_<appid>.bin` (ikili
/// KeyValues; çözücü `key_values.dart`).
///
/// ## Yapı
///
/// ```
/// <appid>
///   gamename            → oyunun İÇ adı ("ValveTestApp260" olabilir)
///   stats
///     <sıra>
///       type_int = 4    → bu düğüm BAŞARIM taşıyor
///       bits
///         <sıra>
///           name        → API adı (SetAchievement bunu istiyor)
///           bit         → bit numarası (bize gerekmiyor)
///           display
///             name  { english, turkish, … , token }
///             desc  { english, … }
///             hidden = 0|1
///             icon      → açık ikon dosyası
///             icon_gray → kilitli ikon dosyası
/// ```
///
/// `type_int` 4 olmayan düğümler istatistik (sayaç); bu uygulama başarımlara
/// bakıyor, onlar atlanıyor.
///
/// ## Dil seçimi
///
/// Metinler dil dil duruyor. İstenen dil yoksa İngilizce'ye, o da yoksa ilk
/// bulunan dile düşülüyor: adsız bir satır göstermektense yabancı dilde
/// göstermek yeğ.
library;

import 'dart:io';
import 'dart:typed_data';

import 'key_values.dart';
import 'steam_paths.dart';

/// Tek bir başarımın tanımı (durumu DEĞİL — o Steam'den geliyor).
class AchievementDef {
  const AchievementDef({
    required this.apiName,
    required this.title,
    required this.description,
    required this.hidden,
    required this.icon,
    required this.iconGray,
  });

  /// `SetAchievement`/`ClearAchievement`'in istediği ad.
  final String apiName;

  final String title;
  final String description;

  /// Steam'de "gizli" işaretli mi (açılana kadar açıklaması saklanır).
  final bool hidden;

  /// İkon dosya adları — Steam'in CDN'inde ve yerel önbellekte bu adla durur.
  final String icon;
  final String iconGray;
}

/// Bir oyunun başarım şeması.
class GameSchema {
  const GameSchema({
    required this.appId,
    required this.internalName,
    required this.achievements,
  });

  final int appId;

  /// Şemadaki `gamename`. Bu genelde İÇ ad: CS2 için "ValveTestApp260".
  /// Listede gösterilecek ad `appmanifest`ten geliyor; bu yalnız yedek.
  final String internalName;

  final List<AchievementDef> achievements;
}

/// Şemayı okur ve çözer. Dosya yoksa/bozuksa null.
GameSchema? loadSchema(String steamPath, int appId, {String lang = 'english'}) {
  final f = File(schemaPath(steamPath, appId));
  if (!f.existsSync()) return null;
  Uint8List bytes;
  try {
    bytes = f.readAsBytesSync();
  } catch (_) {
    return null;
  }
  final root = parseBinaryKeyValues(bytes);
  final app = root['$appId'];
  if (app == null) return null;

  final out = <AchievementDef>[];
  final stats = app['stats'];
  if (stats != null) {
    for (final s in stats.children) {
      // Yeni biçimde `type` metin ("achievements"), eskisinde `type_int` 4.
      final isAch = s['type_int']?.asInt() == 4 ||
          (s['type']?.asString().toLowerCase() == 'achievements');
      if (!isAch) continue;
      final bits = s['bits'];
      if (bits == null) continue;
      for (final b in bits.children) {
        final api = b['name']?.asString() ?? '';
        if (api.isEmpty) continue;
        final d = b['display'];
        out.add(AchievementDef(
          apiName: api,
          title: _pick(d?['name'], lang, api),
          description: _pick(d?['desc'], lang, ''),
          hidden: d?['hidden']?.asBool() ?? false,
          icon: d?['icon']?.asString() ?? '',
          iconGray: d?['icon_gray']?.asString() ?? '',
        ));
      }
    }
  }
  return GameSchema(
    appId: appId,
    internalName: app['gamename']?.asString() ?? '',
    achievements: out,
  );
}

/// Şemadan YALNIZ oyun adını okur.
///
/// Liste ekranı için var: üç yüz oyunun tamamını tam çözmek gereksiz iş
/// olurdu. Yine de tam çözümleme yapıyor — dosyalar küçük (birkaç yüz KB) ve
/// ayrı bir "hızlı geçiş" çözücüsü yazmak, iki ayrı biçim varsayımı
/// sürdürmek demekti.
String? schemaGameName(String steamPath, int appId) {
  final f = File(schemaPath(steamPath, appId));
  if (!f.existsSync()) return null;
  try {
    final root = parseBinaryKeyValues(f.readAsBytesSync());
    final n = root['$appId']?['gamename']?.asString() ?? '';
    return n.isEmpty ? null : n;
  } catch (_) {
    return null;
  }
}

String _pick(KeyValue? node, String lang, String fallback) {
  if (node == null) return fallback;
  final want = node[lang]?.asString();
  if (want != null && want.trim().isNotEmpty) return want;
  final en = node['english']?.asString();
  if (en != null && en.trim().isNotEmpty) return en;
  for (final c in node.children) {
    // `token` bir metin değil, çeviri anahtarı — ad olarak gösterilmemeli.
    if (c.name.toLowerCase() == 'token') continue;
    final v = c.value;
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return fallback;
}
