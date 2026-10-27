/// Yerel Steam kütüphanesi: kurulu oyunlar, oturum açan kullanıcı, Web API.
///
/// Hepsi salt okunur. Kurulu oyunlar `appmanifest_*.acf` dosyalarından gelir
/// (ağ ve anahtar gerekmez); tüm kütüphane için isteğe bağlı Steam Web API
/// anahtarı kullanılır.
library;

import 'dart:convert';
import 'dart:io';

import 'package:steam_worker/steam_session.dart';

class Game {
  Game({
    required this.appId,
    required this.name,
    this.installed = false,
    this.playtimeMin,
    this.custom = false,
  });

  final int appId;
  String name;
  bool installed;

  /// Toplam oynama süresi (dakika), bilinmiyorsa null.
  int? playtimeMin;
  bool custom;

  String get lower => name.toLowerCase();
}

/// Oyun olmayan uygulamalar (araçlar, çalışma zamanları, demolar…).
const _nonGameIds = {228980, 1070560, 1391110, 1628350, 1493710};
const _nonGameHints = [
  'redistributable', 'dedicated server', ' sdk', 'soundtrack', 'proton',
  'steam linux runtime', 'benchmark', 'steamworks',
];

bool isProbablyGame(Game g) {
  if (_nonGameIds.contains(g.appId)) return false;
  final l = g.lower;
  return !_nonGameHints.any(l.contains);
}

// ── VDF (Valve KeyValues) ayrıştırıcı ───────────────────────────────────────

/// Basit VDF metnini iç içe haritaya çevirir; hatalı yerleri atlar.
Map<String, dynamic> parseVdf(String text) {
  final tokens = RegExp(r'"((?:[^"\\]|\\.)*)"|([{}])').allMatches(text);
  final stack = <Map<String, dynamic>>[{}];
  String? key;
  for (final m in tokens) {
    final brace = m.group(2);
    if (brace == '{') {
      final node = <String, dynamic>{};
      if (key != null) {
        stack.last[key] = node;
        key = null;
      }
      stack.add(node);
    } else if (brace == '}') {
      if (stack.length > 1) stack.removeLast();
    } else {
      final v = m.group(1)!.replaceAll(r'\\', r'\').replaceAll(r'\"', '"');
      if (key == null) {
        key = v;
      } else {
        stack.last[key] = v;
        key = null;
      }
    }
  }
  return stack.first;
}

String _readText(File f) {
  try {
    return utf8.decode(f.readAsBytesSync(), allowMalformed: true);
  } catch (_) {
    return '';
  }
}

// ── Kütüphane klasörleri ve kurulu oyunlar ──────────────────────────────────

List<String> libraryFolders(String steam) {
  final out = <String>[steam];
  final f = File('$steam\\steamapps\\libraryfolders.vdf');
  if (f.existsSync()) {
    final data = parseVdf(_readText(f));
    final root = (data['libraryfolders'] ?? data) as Map<String, dynamic>;
    for (final v in root.values) {
      if (v is Map) {
        final p = v['path'];
        if (p is String && Directory(p).existsSync() && !out.contains(p)) out.add(p);
      }
    }
  }
  return out;
}

List<Game> installedGames(String steam) {
  final seen = <int>{};
  final out = <Game>[];
  for (final lib in libraryFolders(steam)) {
    final dir = Directory('$lib\\steamapps');
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('appmanifest_') || !name.endsWith('.acf')) continue;
      final state = parseVdf(_readText(f))['AppState'];
      if (state is! Map) continue;
      final id = int.tryParse('${state['appid']}');
      if (id == null || id == 0 || !seen.add(id)) continue;
      out.add(Game(appId: id, name: '${state['name'] ?? 'App $id'}', installed: true));
    }
  }
  out.sort((a, b) => a.lower.compareTo(b.lower));
  return out;
}

// ── Oturum açmış kullanıcı ──────────────────────────────────────────────────

class SteamUser {
  const SteamUser({this.steam64 = '', this.persona = '', this.accountName = ''});
  final String steam64;
  final String persona;
  final String accountName;
  bool get known => steam64.isNotEmpty;
}

const _steam64Base = 76561197960265728;

SteamUser activeUser(String steam) {
  final acc = SteamEnv.activeAccountId();
  final id64 = acc > 0 ? '${_steam64Base + acc}' : '';
  final f = File('$steam\\config\\loginusers.vdf');
  if (!f.existsSync()) return SteamUser(steam64: id64);
  final users = parseVdf(_readText(f))['users'];
  if (users is! Map) return SteamUser(steam64: id64);
  Map? best;
  var bestId = '';
  users.forEach((k, v) {
    if (v is! Map) return;
    if ('$k' == id64) {
      best = v;
      bestId = '$k';
    } else if (best == null && v['MostRecent'] == '1') {
      best = v;
      bestId = '$k';
    }
  });
  return SteamUser(
    steam64: id64.isNotEmpty ? id64 : bestId,
    persona: '${best?['PersonaName'] ?? ''}',
    accountName: '${best?['AccountName'] ?? ''}',
  );
}

// ── Steam Web API (isteğe bağlı) ────────────────────────────────────────────

Future<Map<String, dynamic>?> _getJson(Uri uri) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

/// Hesabın tüm oyunları (kurulu olmayanlar dahil). Hata/anahtarsız → boş liste.
Future<List<Game>> fetchOwnedGames(String steam64, String apiKey) async {
  if (steam64.isEmpty || apiKey.isEmpty) return [];
  final j = await _getJson(Uri.https('api.steampowered.com', '/IPlayerService/GetOwnedGames/v1/', {
    'key': apiKey,
    'steamid': steam64,
    'include_appinfo': '1',
    'include_played_free_games': '1',
    'format': 'json',
  }));
  final games = (j?['response'] as Map?)?['games'];
  if (games is! List) return [];
  return [
    for (final g in games)
      if (g is Map)
        Game(
          appId: (g['appid'] as num).toInt(),
          name: '${g['name'] ?? 'App ${g['appid']}'}',
          playtimeMin: (g['playtime_forever'] as num?)?.toInt(),
        ),
  ]..sort((a, b) => a.lower.compareTo(b.lower));
}

Future<String> fetchPersona(String steam64, String apiKey) async {
  if (steam64.isEmpty || apiKey.isEmpty) return '';
  final j = await _getJson(Uri.https('api.steampowered.com', '/ISteamUser/GetPlayerSummaries/v2/',
      {'key': apiKey, 'steamids': steam64}));
  final players = (j?['response'] as Map?)?['players'];
  if (players is List && players.isNotEmpty) return '${(players.first as Map)['personaname'] ?? ''}';
  return '';
}

/// Kapak görseli (Steam CDN, anahtarsız).
String coverUrl(int appId) =>
    'https://cdn.cloudflare.steamstatic.com/steam/apps/$appId/capsule_231x87.jpg';
