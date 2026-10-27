/// **İşçi köprüsü** — oyun başına açılan yardımcı süreçle konuşur.
///
/// `steamclient.dll` uygulama kimliğini ilk boruda kilitliyor; tek süreçte
/// oyun değiştirmek mümkün değil (ölçüm ve gerekçe `bin/achievements_worker.dart`
/// başlığında). Her seçimde yeni bir işçi açılıyor, öncekine `quit`
/// yollanıyor.
///
/// ## Neden JSON satırları
///
/// Paylaşılan bellek ya da soket kurmak bu iş için fazla. Süreç başına
/// birkaç kilobayt veri var; satır satır JSON hem ayıklaması kolay hem de
/// bir hata olduğunda çıktı doğrudan okunabiliyor.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart' show StreamQueue;

/// İşçi çalıştırılabilirinin yeri.
///
/// Sürüm paketinde `trophy_room.exe` ile yan yana duruyor. Geliştirmede
/// (`flutter run`) exe klasörü farklı olduğu için proje içindeki derlenmiş
/// kopyaya düşülüyor — yoksa araç yalnız sürüm derlemesinde çalışırdı.
File? _workerExe() {
  final yaninda = File(
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}achievements_worker.exe');
  if (yaninda.existsSync()) return yaninda;
  final gelistirme = File(
      '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}achievements_worker.exe');
  if (gelistirme.existsSync()) return gelistirme;
  return null;
}

/// Bir başarımın işçiden gelen hâli.
class WorkerAchievement {
  const WorkerAchievement({
    required this.api,
    required this.title,
    required this.desc,
    required this.hidden,
    required this.unlocked,
    this.icon = '',
    this.iconGray = '',
  });

  final String api;
  final String title;
  final String desc;
  final bool hidden;
  final bool unlocked;

  /// Steam CDN'indeki ikon dosya adları (açık / kilitli).
  final String icon;
  final String iconGray;

  /// İkonun adresi; ad yoksa null.
  String? iconUrl(int appId, {required bool unlocked}) {
    final n = unlocked ? icon : (iconGray.isNotEmpty ? iconGray : icon);
    if (n.isEmpty) return null;
    final file = n.contains('.') ? n : '$n.jpg';
    return 'https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/$appId/$file';
  }

  static WorkerAchievement fromJson(Map<String, dynamic> j) =>
      WorkerAchievement(
        api: '${j['api']}',
        title: '${j['title']}',
        desc: '${j['desc']}',
        hidden: j['hidden'] == true,
        unlocked: j['unlocked'] == true,
        icon: '${j['icon'] ?? ''}',
        iconGray: '${j['iconGray'] ?? ''}',
      );
}

class WorkerError implements Exception {
  const WorkerError(this.message, [this.code = '']);
  final String message;

  /// Makine okunur sebep ('steamNotFound', 'schemaMissing', 'worker_missing'…);
  /// arayüz bununla yerelleştirilmiş metin seçer.
  final String code;
  @override
  String toString() => message;
}

/// Açık bir işçi süreci.
class WorkerLink {
  WorkerLink._(this._proc, this._lines, this.achievements);

  final Process _proc;
  final StreamQueue<String> _lines;

  /// Açılışta gelen tam liste.
  final List<WorkerAchievement> achievements;

  /// Oyunu açar. Hata durumunda [WorkerError] fırlatır.
  static Future<WorkerLink> start(int appId, {String lang = 'turkish'}) async {
    final exe = _workerExe();
    if (exe == null) {
      throw const WorkerError('achievements_worker.exe not found', 'worker_missing');
    }
    final proc = await Process.start(exe.path, ['$appId', lang]);
    final lines = StreamQueue<String>(
        proc.stdout.transform(utf8.decoder).transform(const LineSplitter()));

    // İlk satır ya liste ya hata. Süreç hiç konuşmadan ölürse burada
    // takılmamak için zaman aşımı var.
    final String first;
    try {
      first = await lines.next.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      proc.kill();
      throw const WorkerError('Steam did not respond', 'steam_no_response');
    } catch (_) {
      proc.kill();
      throw const WorkerError('Helper closed unexpectedly', 'worker_died');
    }

    final j = jsonDecode(first) as Map<String, dynamic>;
    if (j['ok'] != true) {
      proc.kill();
      throw WorkerError('${j['error'] ?? 'Unknown error'}', '${j['code'] ?? ''}');
    }
    return WorkerLink._(
      proc,
      lines,
      [
        for (final a in (j['achievements'] as List))
          WorkerAchievement.fromJson(a as Map<String, dynamic>),
      ],
    );
  }

  /// Değişiklikleri yazar. Dönen: (yazıldı mı, güncel durumlar).
  Future<({bool stored, int applied, int failed, Map<String, bool> states})>
      apply(Map<String, bool> changes) async {
    _proc.stdin.writeln(jsonEncode({'cmd': 'apply', 'set': changes}));
    await _proc.stdin.flush();
    final line = await _lines.next.timeout(const Duration(seconds: 20));
    final j = jsonDecode(line) as Map<String, dynamic>;
    if (j['ok'] != true) {
      throw WorkerError('${j['error'] ?? 'Write failed'}', '${j['code'] ?? ''}');
    }
    return (
      stored: j['stored'] == true,
      applied: (j['applied'] as num?)?.toInt() ?? 0,
      failed: (j['failed'] as num?)?.toInt() ?? 0,
      states: {
        for (final e in (j['states'] as Map).entries)
          '${e.key}': e.value == true,
      },
    );
  }

  /// İşçiyi kapatır. Nazik `quit` yollanıyor; yanıt beklenmiyor çünkü süreç
  /// zaten kapanıyor.
  void close() {
    try {
      _proc.stdin.writeln(jsonEncode({'cmd': 'quit'}));
      _proc.stdin.close();
    } catch (_) {}
    // Yetim süreç bırakmamak için kısa bir gecikmeyle kesin kapatma.
    Future<void>.delayed(const Duration(seconds: 2), () {
      try {
        _proc.kill();
      } catch (_) {}
    });
  }
}
