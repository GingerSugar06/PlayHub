/// Başka hesaplar: Python ağ motoruyla (engine/engine.py) konuşan hesap oturumu.
///
/// Motor ayrı bir süreç; stdin/stdout üzerinden satır satır JSON. Şifre ve
/// token'lar yalnız bu boru üzerinden akar, diske yazılmaz (token'ı arayüz
/// güvenli depoya koyar).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../steam/library_scan.dart';

// ── Python bulucu ───────────────────────────────────────────────────────────

class PythonInfo {
  const PythonInfo({this.exe, this.cmd = const [], this.depsOk = false, this.error, this.version});
  final String? exe;

  /// Çalıştırılacak komut ve ön argümanları (örn. ['py', '-3'] ya da ['C:\...\python.exe']).
  final List<String> cmd;
  final bool depsOk;
  final String? error;
  final String? version;
  bool get found => exe != null;
}

File? findEngineScript() {
  final sep = Platform.pathSeparator;
  for (final base in [
    File(Platform.resolvedExecutable).parent.path,
    Directory.current.path,
  ]) {
    final f = File('$base${sep}engine${sep}engine.py');
    if (f.existsSync()) return f;
  }
  return null;
}

Future<PythonInfo> probePython() async {
  final script = findEngineScript();
  if (script == null) return const PythonInfo(error: 'engine_missing');
  final candidates = <List<String>>[
    ['py', '-3'],
    ['python'],
    ['python3'],
    // Kurulum sihirbazının kurduğu / kullanıcı profilindeki Python (PATH henüz yenilenmemiş olabilir)
    ..._userPythons(),
  ];
  for (final c in candidates) {
    try {
      final r = await Process.run(c.first, [...c.skip(1), script.path, '--check'])
          .timeout(const Duration(seconds: 25));
      final out = r.stdout.toString().trim();
      if (out.isEmpty) continue;
      final j = jsonDecode(out.split('\n').last) as Map<String, dynamic>;
      // Python bulundu; bağımlılıklar tamam mı?
      final exe = c.length == 1 ? c.first : c.join(' ');
      return PythonInfo(
        exe: exe,
        cmd: c,
        depsOk: j['ok'] == true,
        version: '${j['python']}',
        error: j['error'] as String?,
      );
    } catch (_) {
      continue;
    }
  }
  return const PythonInfo();
}

/// `%LOCALAPPDATA%\Programs\Python\Python3*\python.exe` (en yeni sürüm önce).
List<List<String>> _userPythons() {
  final base = Platform.environment['LOCALAPPDATA'];
  if (base == null) return const [];
  final dir = Directory('$base${Platform.pathSeparator}Programs${Platform.pathSeparator}Python');
  if (!dir.existsSync()) return const [];
  final found = <String>[
    for (final d in dir.listSync().whereType<Directory>())
      if (File('${d.path}${Platform.pathSeparator}python.exe').existsSync()) '${d.path}${Platform.pathSeparator}python.exe',
  ]..sort((a, b) => b.compareTo(a));
  return [for (final p in found) [p]];
}

/// `pip install -r requirements.txt` çalıştırır; satırları [onLine]'a akıtır.
Future<bool> installEngineDeps(PythonInfo py, void Function(String) onLine) async {
  final script = findEngineScript();
  if (script == null || py.exe == null) return false;
  final req = '${script.parent.path}${Platform.pathSeparator}requirements.txt';
  final parts = py.cmd;
  final p = await Process.start(parts.first, [...parts.skip(1), '-m', 'pip', 'install', '-r', req]);
  void pipe(Stream<List<int>> s) =>
      s.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
  pipe(p.stdout);
  pipe(p.stderr);
  return await p.exitCode == 0;
}

// ── Hesap oturumu ───────────────────────────────────────────────────────────

enum RemoteState {
  idle, // süreç yok / giriş yok
  connecting,
  qr,
  needTwoFa,
  needEmail,
  needConfirm,
  wrongCode,
  loggedOn,
  disconnected,
  badPassword,
  rateLimited,
  tokenInvalid,
  error,
}

RemoteState _stateFrom(String s) => switch (s) {
      'connecting' => RemoteState.connecting,
      'qr' => RemoteState.qr,
      'need_2fa' => RemoteState.needTwoFa,
      'need_email' => RemoteState.needEmail,
      'need_confirm' => RemoteState.needConfirm,
      'wrong_code' => RemoteState.wrongCode,
      'logged_on' => RemoteState.loggedOn,
      'disconnected' => RemoteState.disconnected,
      'bad_password' => RemoteState.badPassword,
      'rate_limited' => RemoteState.rateLimited,
      'token_invalid' => RemoteState.tokenInvalid,
      'error' => RemoteState.error,
      _ => RemoteState.idle,
    };

class RemoteAccount extends ChangeNotifier {
  RemoteAccount(this.id, {required this.credsDir, required this.logPath});

  final String id;
  final String credsDir;
  final String logPath;

  RemoteState state = RemoteState.idle;
  String message = '';
  String qrUrl = '';
  String accountName = '';
  String steam64 = '';
  String persona = '';
  List<Game> owned = [];
  DateTime? loggedOnAt;

  /// Yeni refresh token geldiğinde (güvenli depoya yazmak için).
  void Function(String token)? onToken;

  /// Kimlik (ad/steam64) öğrenildiğinde.
  VoidCallback? onIdentity;

  Process? _proc;
  PythonInfo? python;

  bool get running => _proc != null;
  bool get isLoggedOn => state == RemoteState.loggedOn;
  bool get needsAttention => const {
        RemoteState.needTwoFa,
        RemoteState.needEmail,
        RemoteState.needConfirm,
        RemoteState.qr,
      }.contains(state);

  Future<bool> _ensureProcess() async {
    if (_proc != null) return true;
    python ??= await probePython();
    final py = python!;
    if (!py.found || !py.depsOk) {
      state = RemoteState.error;
      message = !py.found ? 'python_missing' : 'deps_missing';
      notifyListeners();
      return false;
    }
    final script = findEngineScript()!;
    final parts = py.cmd;
    try {
      final p = await Process.start(parts.first, [
        ...parts.skip(1),
        '-u',
        script.path,
        '--creds',
        credsDir,
        '--log',
        logPath,
      ]);
      _proc = p;
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
      p.stderr.drain<void>();
      p.exitCode.then((_) {
        if (_proc == p) {
          _proc = null;
          if (state != RemoteState.idle && state != RemoteState.badPassword) {
            if (state == RemoteState.loggedOn || state == RemoteState.connecting) {
              state = RemoteState.error;
              message = 'engine_exited';
            }
          }
          notifyListeners();
        }
      });
      return true;
    } catch (e) {
      state = RemoteState.error;
      message = '$e';
      notifyListeners();
      return false;
    }
  }

  void _onLine(String line) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (j['event']) {
      case 'state':
        final prev = state;
        state = _stateFrom('${j['state']}');
        message = '${j['message'] ?? ''}';
        if (state == RemoteState.loggedOn && prev != RemoteState.loggedOn) {
          loggedOnAt = DateTime.now();
        }
        if (state != RemoteState.qr) qrUrl = state == RemoteState.connecting ? '' : qrUrl;
      case 'qr':
        qrUrl = '${j['url']}';
      case 'identity':
        accountName = '${j['account_name'] ?? accountName}';
        steam64 = '${j['steam64'] ?? steam64}';
        persona = '${j['persona'] ?? persona}';
        onIdentity?.call();
      case 'token':
        onToken?.call('${j['refresh_token']}');
      case 'owned':
        final list = (j['games'] as List)
            .map((g) => Game(
                  appId: (g['appid'] as num).toInt(),
                  name: ((g['name'] as String?)?.isNotEmpty ?? false) ? g['name'] as String : 'App ${g['appid']}',
                ))
            .toList();
        // Adı henüz gelmemiş kayıtlar daha önce çözülmüş adı ezmesin.
        final known = {for (final g in owned) g.appId: g.name};
        for (final g in list) {
          if (g.name.startsWith('App ') && known[g.appId] != null) g.name = known[g.appId]!;
        }
        owned = list..sort((a, b) => a.lower.compareTo(b.lower));
    }
    notifyListeners();
  }

  void _send(Map<String, Object?> m) {
    try {
      _proc?.stdin.writeln(jsonEncode(m));
    } catch (_) {}
  }

  // ── Komutlar ──────────────────────────────────────────────────────────────
  Future<void> loginPassword(String username, String password, Iterable<int> appids) async {
    if (!await _ensureProcess()) return;
    state = RemoteState.connecting;
    notifyListeners();
    _send({'cmd': 'login_password', 'username': username, 'password': password, 'appids': appids.toList()});
  }

  Future<void> loginQr(Iterable<int> appids) async {
    if (!await _ensureProcess()) return;
    state = RemoteState.connecting;
    qrUrl = '';
    notifyListeners();
    _send({'cmd': 'login_qr', 'appids': appids.toList()});
  }

  Future<void> loginToken(String accountName, String token, Iterable<int> appids) async {
    if (!await _ensureProcess()) return;
    state = RemoteState.connecting;
    notifyListeners();
    _send({'cmd': 'login_token', 'account_name': accountName, 'refresh_token': token, 'appids': appids.toList()});
  }

  void submitGuard(String code) => _send({'cmd': 'guard', 'code': code});

  void setGames(Iterable<int> appids) => _send({'cmd': 'set_games', 'appids': appids.toList()});

  Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    _send({'cmd': 'quit'});
    try {
      p.stdin.close();
    } catch (_) {}
    Future<void>.delayed(const Duration(seconds: 2), p.kill);
    _proc = null;
    state = RemoteState.idle;
    qrUrl = '';
    notifyListeners();
  }
}
