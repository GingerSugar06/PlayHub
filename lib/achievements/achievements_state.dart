/// Başarım yöneticisinin durumu: oyun listesi, seçili oyun, bekleyen değişiklikler.
///
/// Kutucuğa basmak Steam'e hemen yazmaz; değişiklikler biriktirilir ve
/// "Uygula" ile tek `StoreStats` olarak gider. Gerçek durum uygulamadan sonra
/// işçiden geri okunur.
library;

import 'package:flutter/foundation.dart';

import '../core/l10n.dart';
import 'library_scan.dart';
import 'worker_link.dart';

class AchievementRow {
  AchievementRow({required this.def, required this.unlocked}) : pending = unlocked;
  final WorkerAchievement def;

  /// Steam'deki gerçek durum.
  bool unlocked;

  /// Kullanıcının istediği durum.
  bool pending;

  bool get changed => pending != unlocked;
}

enum LoadState { idle, busy, ready, failed }

class AchievementsState extends ChangeNotifier {
  AchievementsState(this._lang);

  /// Geçerli dil kodunu (tr/en) veren işlev.
  final String Function() _lang;
  S get s => S(_lang());

  // ── Kütüphane ─────────────────────────────────────────────────────────────
  LoadState libraryState = LoadState.idle;
  List<GameEntry> games = const [];
  String query = '';
  bool installedOnly = false;

  List<GameEntry> get visibleGames {
    final q = query.trim().toLowerCase();
    return [
      for (final g in games)
        if ((!installedOnly || g.installed) && (q.isEmpty || g.searchKey.contains(q))) g,
    ];
  }

  Future<void> loadLibrary() async {
    libraryState = LoadState.busy;
    notifyListeners();
    final scan = await scanLibrary();
    games = scan.games;
    libraryState = scan.steamPath == null ? LoadState.failed : LoadState.ready;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setInstalledOnly(bool v) {
    installedOnly = v;
    notifyListeners();
  }

  // ── Seçili oyun ───────────────────────────────────────────────────────────
  GameEntry? selected;
  LoadState gameState = LoadState.idle;
  String? gameError;
  List<AchievementRow> rows = const [];
  WorkerLink? _link;
  bool onlyLocked = false;
  bool showHidden = true;
  String achQuery = '';

  List<AchievementRow> get visibleRows {
    final q = achQuery.trim().toLowerCase();
    return [
      for (final r in rows)
        if ((!onlyLocked || !r.pending) &&
            (showHidden || !r.def.hidden) &&
            (q.isEmpty || r.def.title.toLowerCase().contains(q) || r.def.api.toLowerCase().contains(q)))
          r,
    ];
  }

  int get pendingCount => rows.where((r) => r.changed).length;
  int get unlockedCount => rows.where((r) => r.pending).length;

  void setAchQuery(String q) {
    achQuery = q;
    notifyListeners();
  }

  void setOnlyLocked(bool v) {
    onlyLocked = v;
    notifyListeners();
  }

  void setShowHidden(bool v) {
    showHidden = v;
    notifyListeners();
  }

  String errorText(WorkerError e) {
    final key = switch (e.code) {
      '' => null,
      'worker_missing' => 'ach_worker_missing',
      'steam_no_response' || 'worker_died' => e.code,
      final c => 'err_$c',
    };
    if (key != null) {
      final txt = s.t(key);
      if (txt != key) return txt;
    }
    return e.message;
  }

  Future<void> select(GameEntry g) async {
    if (selected?.appId == g.appId && gameState == LoadState.ready) return;
    _closeLink();
    selected = g;
    gameState = LoadState.busy;
    gameError = null;
    applyResult = null;
    rows = const [];
    achQuery = '';
    notifyListeners();
    try {
      // Her oyun için yeni süreç: steamclient64.dll AppID'yi ilk boruda kilitler.
      final link = await WorkerLink.start(g.appId, lang: s.steamLang);
      if (selected?.appId != g.appId) {
        link.close();
        return;
      }
      _link = link;
      rows = [for (final a in link.achievements) AchievementRow(def: a, unlocked: a.unlocked)];
      gameState = LoadState.ready;
    } on WorkerError catch (e) {
      gameState = LoadState.failed;
      gameError = errorText(e);
    } catch (e) {
      gameState = LoadState.failed;
      gameError = '$e';
    }
    notifyListeners();
  }

  /// Dil değişince başlıklar yeni dille yeniden okunsun.
  void reloadSelected() {
    final g = selected;
    if (g == null) return;
    selected = null;
    select(g);
  }

  void toggle(AchievementRow r, bool value) {
    r.pending = value;
    notifyListeners();
  }

  void setAllVisible(bool value) {
    for (final r in visibleRows) {
      r.pending = value;
    }
    notifyListeners();
  }

  void invertVisible() {
    for (final r in visibleRows) {
      r.pending = !r.pending;
    }
    notifyListeners();
  }

  void revert() {
    for (final r in rows) {
      r.pending = r.unlocked;
    }
    notifyListeners();
  }

  // ── Uygula ────────────────────────────────────────────────────────────────
  bool applying = false;
  String? applyResult;

  Future<void> apply() async {
    final link = _link;
    if (link == null || applying) return;
    final changed = rows.where((r) => r.changed).toList();
    if (changed.isEmpty) return;
    applying = true;
    applyResult = null;
    notifyListeners();
    try {
      final r = await link.apply({for (final row in changed) row.def.api: row.pending});
      for (final row in rows) {
        final st = r.states[row.def.api];
        if (st != null) row.unlocked = st;
        row.pending = row.unlocked;
      }
      applyResult = r.stored
          ? s.t('applied', {'n': '${r.applied}'}) + (r.failed > 0 ? s.t('applied_failed', {'n': '${r.failed}'}) : '')
          : s.t('store_refused');
    } on WorkerError catch (e) {
      applyResult = errorText(e);
    } catch (e) {
      applyResult = '$e';
    }
    applying = false;
    notifyListeners();
  }

  void _closeLink() {
    _link?.close();
    _link = null;
  }

  /// Sayfadan çıkınca açık işçiyi bırak.
  void release() {
    _closeLink();
    selected = null;
    gameState = LoadState.idle;
    rows = const [];
    applyResult = null;
  }

  @override
  void dispose() {
    _closeLink();
    super.dispose();
  }
}
