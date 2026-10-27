/// "Bu bilgisayar" kipi: Steam istemcisinde açık hesap için oyun kasma.
///
/// Her oyun için ayrı bir işçi süreç (`idle_worker.exe`) çalışır. Yönetici,
/// kullanıcının İSTEDİĞİ oyun kümesini (`wanted`) tutar ve işçileri buna göre
/// ayakta tutar: Steam kapanırsa işçiler çıkar, Steam geri gelince yeniden
/// başlatılır.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:steam_worker/steam_session.dart';

enum WorkerPhase { starting, running, failed }

class WorkerInfo {
  WorkerInfo(this.appId) : startedAt = DateTime.now();
  final int appId;
  DateTime startedAt;
  WorkerPhase phase = WorkerPhase.starting;
  String? error;
  Process? process;
}

/// Steam'in aynı anda oynatabildiği uygulama sınırı.
const kMaxConcurrent = 32;

/// İşçi çalıştırılabilirini bulur (yanında → geliştirmede build/).
File? findWorkerExe() {
  final sep = Platform.pathSeparator;
  final beside = File('${File(Platform.resolvedExecutable).parent.path}${sep}idle_worker.exe');
  if (beside.existsSync()) return beside;
  final dev = File('${Directory.current.path}${sep}build${sep}idle_worker.exe');
  if (dev.existsSync()) return dev;
  return null;
}

class ThisPcManager extends ChangeNotifier {
  final Set<int> wanted = {};
  final Map<int, WorkerInfo> workers = {};
  Timer? _timer;
  bool steamReady = false;
  bool steamRunning = false;
  bool workerMissing = false;
  int _tick = 0;

  /// Kullanıcının istediği küme değişince kaydetmek için.
  VoidCallback? onWantedChanged;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _loop());
    _refreshSteam();
  }

  bool isIdling(int id) => wanted.contains(id);

  WorkerInfo? infoOf(int id) => workers[id];

  /// Gerçekten çalışan (Steam'e bildirilmiş) oyun sayısı.
  int get runningCount => workers.values.where((w) => w.phase == WorkerPhase.running).length;

  bool toggle(int id) {
    if (wanted.contains(id)) {
      wanted.remove(id);
      _kill(id);
    } else {
      if (wanted.length >= kMaxConcurrent) return false;
      wanted.add(id);
    }
    onWantedChanged?.call();
    notifyListeners();
    _reconcile();
    return true;
  }

  void setWanted(Iterable<int> ids) {
    wanted
      ..clear()
      ..addAll(ids.take(kMaxConcurrent));
    notifyListeners();
  }

  void stopAll() {
    wanted.clear();
    for (final id in workers.keys.toList()) {
      _kill(id);
    }
    onWantedChanged?.call();
    notifyListeners();
  }

  void _refreshSteam() {
    final r = SteamEnv.running();
    final ok = r && SteamEnv.signedIn();
    if (r != steamRunning || ok != steamReady) {
      steamRunning = r;
      steamReady = ok;
      notifyListeners();
    }
  }

  void _loop() {
    _tick++;
    if (_tick % 3 == 0) {
      _refreshSteam();
      _reconcile();
    }
    if (workers.isNotEmpty) notifyListeners(); // süre sayaçları için
  }

  void _reconcile() {
    // Artık istenmeyenleri kapat
    for (final id in workers.keys.toList()) {
      if (!wanted.contains(id)) _kill(id);
    }
    if (!steamReady) return;
    for (final id in wanted) {
      final w = workers[id];
      if (w == null || (w.phase == WorkerPhase.failed && DateTime.now().difference(w.startedAt).inSeconds > 20)) {
        _spawn(id);
      }
    }
  }

  Future<void> _spawn(int id) async {
    final exe = findWorkerExe();
    if (exe == null) {
      workerMissing = true;
      workers[id] = WorkerInfo(id)
        ..phase = WorkerPhase.failed
        ..error = 'worker_missing';
      notifyListeners();
      return;
    }
    workerMissing = false;
    final info = WorkerInfo(id);
    workers[id] = info;
    notifyListeners();
    try {
      final p = await Process.start(exe.path, ['$id']);
      info.process = p;
      final lines = p.stdout.transform(utf8.decoder).transform(const LineSplitter());
      lines.listen((line) {
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['ok'] == true) {
            info.phase = WorkerPhase.running;
            info.startedAt = DateTime.now();
          } else {
            info.phase = WorkerPhase.failed;
            info.error = '${j['error']}';
          }
          notifyListeners();
        } catch (_) {}
      });
      p.stderr.drain<void>();
      p.exitCode.then((code) {
        if (workers[id] == info) {
          if (wanted.contains(id)) {
            // Beklenmedik çıkış: kapanan Steam ya da hata. Yeniden denenecek.
            info.phase = WorkerPhase.failed;
            info.error ??= code == 10 ? 'steam_closed' : 'exit_$code';
            info.startedAt = DateTime.now();
          } else {
            workers.remove(id);
          }
          notifyListeners();
        }
      });
    } catch (e) {
      info.phase = WorkerPhase.failed;
      info.error = '$e';
      notifyListeners();
    }
  }

  void _kill(int id) {
    final w = workers.remove(id);
    final p = w?.process;
    if (p != null) {
      try {
        p.stdin.close();
      } catch (_) {}
      Future<void>.delayed(const Duration(milliseconds: 500), p.kill);
    }
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    for (final id in workers.keys.toList()) {
      _kill(id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
}
