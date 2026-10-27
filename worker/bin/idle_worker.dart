/// İşçi süreç: TEK bir uygulamayı "oynuyor" gösterir.
///
/// `steamclient64.dll` uygulama kimliğini ilk boruda kilitler; bu yüzden her
/// oyun için ayrı bir süreç gerekir. Arayüz bu işçiden oyun başına bir tane
/// açar ve kapatmak için süreci sonlandırır (ya da stdin'i kapatır).
///
/// Çıktı (tek satır JSON): {"ok":true} ya da {"ok":false,"error":"…"}
///
/// Derleme: `dart compile exe bin/idle_worker.dart -o build/idle_worker.exe`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:steam_worker/steam_session.dart';

void _say(Map<String, Object?> m) => stdout.writeln(jsonEncode(m));

void main(List<String> args) {
  final appId = int.tryParse(args.isEmpty ? '' : args.first) ?? 0;
  if (appId <= 0) {
    _say({'ok': false, 'error': 'usage: idle_worker <appid>'});
    exit(2);
  }
  if (!SteamEnv.ready()) {
    _say({'ok': false, 'error': 'steam_not_ready'});
    exit(3);
  }
  final SteamSession session;
  try {
    session = SteamSession.open(appId);
  } on SteamException catch (e) {
    _say({'ok': false, 'error': e.message});
    exit(4);
  } catch (e) {
    _say({'ok': false, 'error': '$e'});
    exit(4);
  }
  _say({'ok': true});

  // Arayüz ölürse stdin kapanır; yetim süreç bırakma.
  stdin.listen((_) {}, onDone: () {
    session.close();
    exit(0);
  }, onError: (_) {
    session.close();
    exit(0);
  });

  // Steam kapanırsa çık; arayüz hazır olunca yeniden başlatır.
  Timer.periodic(const Duration(seconds: 4), (_) {
    if (!SteamEnv.running()) {
      session.close();
      exit(10);
    }
  });
}
