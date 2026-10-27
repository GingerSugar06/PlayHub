/// **Steam'i diskte bulmak** — kurulum yolu, kütüphaneler, önbellek.
///
/// ## Hız buradan geliyor
///
/// SAM oyun listesini `https://gib.me/sam/games.xml` adresinden indiriyor
/// (kırk bine yakın uygulama kimliği), sonra her biri için tek tek sahiplik
/// soruyor. Ağ beklemesi + on binlerce çağrı; açılışın yavaş olmasının
/// sebebi bu.
///
/// Burada ağ hiç kullanılmıyor. Steam, başarımı olan her oyunun şemasını
/// zaten diske yazıyor:
///
///     <Steam>/appcache/stats/UserGameStatsSchema_<appid>.bin
///
/// Bu klasörü listelemek, "başarımı olan ve bu hesapta görülmüş oyunlar"
/// listesini **anında** veriyor. Dosya adındaki sayı uygulama kimliği.
///
/// Adlar da yerelde: her kütüphane klasöründeki `appmanifest_<appid>.acf`
/// dosyasında `"name"` alanı var. İkisini birleştirince liste ağa hiç
/// çıkmadan doluyor.
library;

import 'dart:io';

/// Steam'in kurulu olduğu klasör (yoksa null).
///
/// Kayıt defterinden okunuyor — SAM da aynı anahtara bakıyor. `reg.exe`
/// kullanılıyor çünkü Dart'ın kayıt defteri okuması yok ve bunun için ayrı
/// bir FFI katmanı yazmak, tek bir dize için fazla.
String? steamInstallPath() {
  if (!Platform.isWindows) return null;
  for (final key in const [
    r'HKLM\Software\Valve\Steam',
    r'HKCU\Software\Valve\Steam',
    // 32 bit süreçten bakan bir Windows'ta 64 bit dal buraya düşüyor.
    r'HKLM\Software\WOW6432Node\Valve\Steam',
  ]) {
    for (final name in const ['InstallPath', 'SteamPath']) {
      final v = _regRead(key, name);
      if (v != null && Directory(v).existsSync()) return v;
    }
  }
  return null;
}

String? _regRead(String key, String name) {
  try {
    final r = Process.runSync('reg', ['query', key, '/v', name]);
    if (r.exitCode != 0) return null;
    final m = RegExp(r'REG_SZ\s+(.+)').firstMatch(r.stdout.toString());
    final v = m?.group(1)?.trim();
    if (v == null || v.isEmpty) return null;
    return v.replaceAll('/', Platform.pathSeparator);
  } catch (_) {
    return null;
  }
}

/// Başarım şeması diskte olan uygulama kimlikleri.
///
/// Sıra korunmuyor; çağıran taraf adına göre diziyor.
Set<int> appIdsWithSchema(String steamPath) {
  final dir = Directory('$steamPath\\appcache\\stats');
  if (!dir.existsSync()) return const {};
  final out = <int>{};
  final re = RegExp(r'UserGameStatsSchema_(\d+)\.bin$', caseSensitive: false);
  for (final f in dir.listSync()) {
    final m = re.firstMatch(f.path);
    if (m == null) continue;
    final id = int.tryParse(m.group(1)!);
    if (id != null) out.add(id);
  }
  return out;
}

/// Şema dosyasının yolu.
String schemaPath(String steamPath, int appId) =>
    '$steamPath\\appcache\\stats\\UserGameStatsSchema_$appId.bin';

/// Bütün kütüphane klasörleri (`steamapps` içeren dizinler).
///
/// Oyunlar tek diskte durmuyor; `libraryfolders.vdf` hepsini sayıyor. Dosya
/// biçimi sürümle değişti (eskiden düz `"1" "D:\\Games"`, şimdi her giriş bir
/// nesne ve içinde `"path"`), o yüzden ikisi de aranıyor.
List<String> libraryFolders(String steamPath) {
  final out = <String>{'$steamPath\\steamapps'};
  final f = File('$steamPath\\steamapps\\libraryfolders.vdf');
  if (f.existsSync()) {
    try {
      final text = f.readAsStringSync();
      for (final m in RegExp(r'"path"\s+"([^"]+)"').allMatches(text)) {
        out.add('${m.group(1)!.replaceAll(r'\\', r'\')}\\steamapps');
      }
      // Eski biçim: anahtar bir sayı, değer doğrudan yol.
      for (final m in RegExp(r'"\d+"\s+"([A-Za-z]:[^"]+)"').allMatches(text)) {
        out.add('${m.group(1)!.replaceAll(r'\\', r'\')}\\steamapps');
      }
    } catch (_) {}
  }
  return [
    for (final p in out)
      if (Directory(p).existsSync()) p,
  ];
}

/// Kurulu oyunların kimlik → ad eşlemesi (`appmanifest_*.acf`).
///
/// Yalnız KURULU oyunları kapsıyor. Kurulu olmayan ama şeması önbellekte
/// duran oyunlar için ad Steam istemcisinden isteniyor; o da yoksa kimlik
/// gösteriliyor. Adsız bırakmaktansa kimlik göstermek yeğ: oyuncu hangi
/// satıra bastığını görebilmeli.
Map<int, String> installedAppNames(String steamPath) {
  final out = <int, String>{};
  for (final lib in libraryFolders(steamPath)) {
    final d = Directory(lib);
    if (!d.existsSync()) continue;
    for (final f in d.listSync()) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('appmanifest_') || !name.endsWith('.acf')) continue;
      final id = int.tryParse(
          name.substring('appmanifest_'.length, name.length - 4));
      if (id == null) continue;
      try {
        final text = File(f.path).readAsStringSync();
        final m = RegExp(r'"name"\s+"([^"]*)"').firstMatch(text);
        if (m != null && m.group(1)!.trim().isNotEmpty) {
          out[id] = m.group(1)!.trim();
        }
      } catch (_) {}
    }
  }
  return out;
}

/// Oyunun yerel kapak görselinin yolu (yoksa null).
///
/// Steam kütüphane görsellerini zaten diske indiriyor:
/// `appcache/librarycache/<appid>/`. Ağa çıkmaya gerek yok ve bu klasör
/// şeması olan oyunlardan çok daha fazlasını kapsıyor (bu makinede 1352'ye
/// karşı 340).
///
/// Adaylar boy sırasına göre: dikey kapak listede en okunaklısı, yoksa yatay
/// başlık, o da yoksa logo. Hiçbiri yoksa arayüz baş harfe düşüyor.
String? coverPath(String steamPath, int appId) {
  final dir = '$steamPath\\appcache\\librarycache\\$appId';
  for (final ad in const [
    'library_600x900.jpg',
    'header.jpg',
    'capsule_231x87.jpg',
    'logo.png',
  ]) {
    final f = File('$dir\\$ad');
    if (f.existsSync()) return f.path;
  }
  // Yeni Steam sürümleri görselleri `<appid>\<özet>\` alt klasörlerine koyuyor.
  try {
    final d = Directory(dir);
    if (d.existsSync()) {
      for (final sub in d.listSync().whereType<Directory>()) {
        for (final ad in const ['library_600x900.jpg', 'header.jpg']) {
          final f = File('${sub.path}\\$ad');
          if (f.existsSync()) return f.path;
        }
      }
    }
  } catch (_) {}
  return null;
}
