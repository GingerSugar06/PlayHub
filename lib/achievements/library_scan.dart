/// **Kütüphane taraması** — başarımı olan oyunları ANINDA listeler.
///
/// ## SAM neden yavaş
///
/// SAM açılışta `https://gib.me/sam/games.xml` indiriyor: kırk bine yakın
/// uygulama kimliği. Sonra her biri için Steam'e "bu bende var mı?" diye
/// soruyor. Ağ beklemesi + on binlerce IPC çağrısı.
///
/// ## Burada ne yapılıyor
///
/// Hiç ağ yok. Steam, başarımı olan her oyunun şemasını zaten diske yazıyor
/// (`appcache/stats/UserGameStatsSchema_<appid>.bin`). O klasörü listelemek
/// hem "hangi oyunlarda başarım var" hem de "bu hesap onları görmüş"
/// sorusunu tek seferde cevaplıyor.
///
/// Adlar iki yerden: kuruluysa `appmanifest_<appid>.acf`, değilse şemanın
/// içindeki `gamename`. `appmanifest` önce geliyor çünkü şemadaki ad iç ad
/// olabiliyor (CS2 için "ValveTestApp260").
///
/// ## Neden ayrı bir isolate'te
///
/// Üç yüz şema dosyası açıp adını okumak birkaç yüz milisaniye sürüyor.
/// Arayüz ipliğinde yapılırsa pencere o kadar süre donuyor — hız iddiasında
/// olan bir uygulamada ilk izlenim tam da bu olurdu.
library;

import 'dart:isolate';

import 'package:achievements_core/schema.dart';
import 'package:achievements_core/steam_client.dart';
import 'package:achievements_core/steam_paths.dart';

/// Listede bir satır.
class GameEntry {
  const GameEntry({
    required this.appId,
    required this.name,
    required this.installed,
    this.cover,
  });

  final int appId;
  final String name;

  /// Kurulu mu (adı `appmanifest`ten geldi mi).
  final bool installed;

  /// Yerel kapak görselinin yolu (yoksa null) — gerekçe `coverPath`.
  final String? cover;

  /// Aramada kullanılan küçük harfli biçim — her tuşta yeniden üretmemek için.
  String get searchKey => '${name.toLowerCase()} $appId';
}

/// Taramanın sonucu.
class LibraryScan {
  const LibraryScan({required this.steamPath, required this.games});
  final String? steamPath;
  final List<GameEntry> games;
}

/// Kütüphaneyi tarar. Steam bulunamazsa boş liste döner.
Future<LibraryScan> scanLibrary() => Isolate.run(_scan);

LibraryScan _scan() {
  final steam = steamInstallPath();
  if (steam == null) return const LibraryScan(steamPath: null, games: []);

  final ids = appIdsWithSchema(steam);
  final installed = installedAppNames(steam);

  // yazmıyor."* Şemadaki `gamename` çoğu oyunda YOK (ölçüldü: 1108750,
  // 113200, 1239690 → null). Adları Steam istemcisi biliyor.
  //
  // İstemciye **appId 0** ile bağlanılıyor: bu kipte hiçbir oyuna
  // kilitlenmiyoruz ve `GetAppData` herhangi bir kimliği cevaplıyor.
  SteamClient? meta;
  try {
    meta = SteamClient.open(0);
  } catch (_) {
    // Steam kapalıysa adlar yerel kaynaklara düşüyor; liste yine geliyor.
  }

  final out = <GameEntry>[];
  for (final id in ids) {
    final kurulu = installed[id];
    var ad = (kurulu != null && kurulu.trim().isNotEmpty) ? kurulu : '';
    if (ad.isEmpty) ad = meta?.appData(id, 'name') ?? '';
    if (ad.isEmpty) ad = schemaGameName(steam, id) ?? '$id';
    out.add(GameEntry(
      appId: id,
      name: ad,
      installed: kurulu != null,
      cover: coverPath(steam, id),
    ));
  }
  meta?.close();

  // Kurulular önce, sonra ada göre. Oyuncunun aradığı oyun neredeyse her
  // zaman kurulu olan; onları başa almak aramayı çoğu zaman gereksiz kılıyor.
  out.sort((a, b) {
    if (a.installed != b.installed) return a.installed ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return LibraryScan(steamPath: steam, games: out);
}
