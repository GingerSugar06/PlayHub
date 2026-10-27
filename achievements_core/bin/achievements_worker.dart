/// **İşçi süreç** — tek bir oyunun başarımlarını okuyup yazar.
///
/// ## Neden ayrı bir süreç
///
/// `steamclient.dll` uygulama kimliğini **ilk boru kurulduğunda** okuyor ve
/// süreç ömrü boyunca ona kilitleniyor. Ortam değişkenini değiştirip yeni
/// bir boru açmak işe yaramıyor; ölçüldü:
///
///     1. açılış: istenen 730     -> appId=730 ok
///     2. açılış: istenen 5067820 -> "Steam 730 uygulamasını verdi"
///
/// Yani tek bir süreçte oyun değiştirmek **mümkün değil**. SAM'in ayrı bir
/// `SAM.Game.exe` çalıştırmasının sebebi de bu.
///
/// Arayüz her oyun seçiminde bu işçiden bir tane açıyor, öncekini
/// kapatıyor. Arayüzün kendi süreci `appId 0` ile bağlı kalıyor (adlar ve
/// sahiplik için) ve hiçbir oyuna kilitlenmiyor.
///
/// ## Protokol
///
/// Girdi: her satır bir JSON komutu. Çıktı: her satır bir JSON yanıtı.
///
///     → (açılışta)            ← {"ok":true,"achievements":[…]}
///     → {"cmd":"apply","set":{"API_ADI":true}}
///                             ← {"ok":true,"stored":true,"states":{…}}
///     → {"cmd":"quit"}        ← (çıkar)
///
/// Hata da JSON: `{"ok":false,"error":"…"}`. Arayüzün kullanıcıya gösterecek
/// bir cümlesi her zaman olmalı.
library;

import 'dart:convert';
import 'dart:io';

import 'package:achievements_core/schema.dart';
import 'package:achievements_core/steam_client.dart';
import 'package:achievements_core/steam_paths.dart';

void main(List<String> args) {
  final appId = int.tryParse(args.isEmpty ? '' : args.first) ?? 0;
  if (appId == 0) {
    _say({'ok': false, 'code': 'usage', 'error': 'Uygulama kimliği verilmedi.'});
    exit(2);
  }
  final lang = args.length > 1 ? args[1] : 'english';

  final steam = steamInstallPath();
  if (steam == null) {
    _say({'ok': false, 'code': 'steamNotFound', 'error': 'Steam kurulumu bulunamadı.'});
    exit(3);
  }

  SteamClient client;
  try {
    client = SteamClient.open(appId);
  } on SteamException catch (e) {
    _say({'ok': false, 'code': e.reason.name, 'error': e.message});
    exit(4);
  } catch (e) {
    _say({'ok': false, 'error': '$e'});
    exit(4);
  }

  // İstatistikler eşzamansız geliyor: iste, kısa bekle, sonra oku.
  client.requestUserStats();
  sleep(const Duration(milliseconds: 400));

  final schema = loadSchema(steam, appId, lang: lang);
  if (schema == null || schema.achievements.isEmpty) {
    _say({
      'ok': false,
      'code': 'schemaMissing',
      'error': 'Bu oyunun başarım şeması Steam önbelleğinde yok. '
          'Oyunu bir kez başlatmak şemayı indiriyor.'
    });
    client.close();
    exit(0);
  }

  _say({
    'ok': true,
    'appId': appId,
    'achievements': [
      for (final a in schema.achievements)
        {
          'api': a.apiName,
          'title': a.title,
          'desc': a.description,
          'hidden': a.hidden,
          'icon': a.icon,
          'iconGray': a.iconGray,
          'unlocked': client.achieved(a.apiName) ?? false,
        }
    ],
  });

  // Komut döngüsü. `stdin` kapanırsa (arayüz öldü) süreç de kapanıyor —
  // yetim işçi bırakmak Steam'de açık boru biriktirirdi.
  String? line;
  while ((line = stdin.readLineSync(encoding: utf8)) != null) {
    Map<String, dynamic> cmd;
    try {
      cmd = jsonDecode(line!) as Map<String, dynamic>;
    } catch (_) {
      _say({'ok': false, 'error': 'Komut çözülemedi.'});
      continue;
    }
    switch (cmd['cmd']) {
      case 'apply':
        _apply(client, cmd['set']);
        break;
      case 'quit':
        client.close();
        exit(0);
      default:
        _say({'ok': false, 'error': 'Bilinmeyen komut.'});
    }
  }
  client.close();
}

void _apply(SteamClient client, Object? raw) {
  if (raw is! Map) {
    _say({'ok': false, 'error': 'Geçersiz değişiklik listesi.'});
    return;
  }
  var ok = 0;
  var fail = 0;
  raw.forEach((key, value) {
    final api = '$key';
    final want = value == true;
    final basarili = want ? client.unlock(api) : client.lock(api);
    if (basarili) {
      ok++;
    } else {
      fail++;
    }
  });
  // Tek bir yazma: her başarımdan sonra `StoreStats` çağırmak Steam'e
  // gereksiz yük ve arka arkaya bildirim demek.
  final stored = client.store();

  // Gerçek durumu GERİ OKU — "yazdım" demek yetmez.
  final states = <String, bool>{};
  raw.forEach((key, _) {
    states['$key'] = client.achieved('$key') ?? false;
  });

  _say({
    'ok': true,
    'stored': stored,
    'applied': ok,
    'failed': fail,
    'states': states,
  });
}

void _say(Object o) {
  stdout.writeln(jsonEncode(o));
  // Satır satır akış: arayüz beklemeden okuyabilmeli.
  stdout.flush();
}
