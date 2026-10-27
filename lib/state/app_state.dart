/// Uygulama durumu: hesaplar, kütüphaneler, kasma yöneticileri.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../achievements/achievements_state.dart';
import '../core/l10n.dart';
import '../data/store.dart';
import '../engine/remote_account.dart';
import '../engine/this_pc.dart';
import '../steam/library_scan.dart';
import 'package:steam_worker/steam_session.dart';

const thisPcId = 'thispc';

enum LibTab { installed, library, favorites, idling }

enum Section { boost, achievements, stats, settings }

class AppState extends ChangeNotifier {
  AppState(this.store, this.ps);

  final Store store;
  final PersistedState ps;
  final ThisPcManager thisPc = ThisPcManager();
  final Map<String, RemoteAccount> remotes = {};
  late final AchievementsState ach = AchievementsState(() => settings.lang);

  Settings get settings => ps.settings;
  S get s => S(settings.lang);

  // ── Seçim / görünüm ───────────────────────────────────────────────────────
  Section section = Section.boost;
  String selected = thisPcId;
  LibTab tab = LibTab.installed;
  String query = '';

  // ── Bu bilgisayar verisi ──────────────────────────────────────────────────
  String? steamPath;
  SteamUser thisUser = const SteamUser();
  List<Game> installed = [];
  List<Game> thisPcOwned = [];
  bool scanning = false;
  String apiKey = '';

  // ── Python motoru ─────────────────────────────────────────────────────────
  PythonInfo? python;
  bool probing = false;

  /// Hesap ekleme akışında, henüz kalıcı olmayan hesap.
  String? pendingId;

  List<AccountInfo> get accounts => ps.accounts;

  AccountInfo? accountOf(String id) {
    for (final a in ps.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ── Başlatma ──────────────────────────────────────────────────────────────
  Timer? _ticker;
  Timer? _saver;

  Future<void> init() async {
    // Satır sayaçları için saniyelik yenileme (yalnız kasılan bir şey varsa).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncSessions();
      if (totalLive() > 0 && section != Section.achievements) notifyListeners();
    });
    _saver = Timer.periodic(const Duration(seconds: 30), (_) => _save());
    apiKey = await store.readApiKey();
    thisPc
      ..setWanted(ps.thisPcWanted)
      ..onWantedChanged = () {
        ps.thisPcWanted = thisPc.wanted.toList();
        _save();
      }
      ..addListener(notifyListeners)
      ..start();

    for (final a in ps.accounts) {
      _attach(a);
    }
    await scanThisPc();
    notifyListeners();

    // Kayıtlı oturumları sürdür (şifre/QR sormadan).
    for (final a in ps.accounts) {
      if (a.autoResume && a.appIds.isNotEmpty) {
        final t = await store.readToken(a.id);
        if (t != null && a.accountName.isNotEmpty) {
          remotes[a.id]!.loginToken(a.accountName, t, a.appIds);
        }
      }
    }
  }

  RemoteAccount _attach(AccountInfo a) {
    final r = RemoteAccount(a.id, credsDir: store.credsDir(a.id), logPath: store.logPath(a.id));
    r.onToken = (t) => store.writeToken(a.id, t);
    r.onIdentity = () => _identity(a, r);
    r.addListener(notifyListeners);
    remotes[a.id] = r;
    return r;
  }

  void _identity(AccountInfo a, RemoteAccount r) {
    var changed = false;
    if (r.accountName.isNotEmpty && a.accountName != r.accountName) {
      a.accountName = r.accountName;
      changed = true;
    }
    if (r.steam64.isNotEmpty && a.steam64 != r.steam64) {
      a.steam64 = r.steam64;
      changed = true;
    }
    if (r.persona.isNotEmpty && a.persona != r.persona) {
      a.persona = r.persona;
      changed = true;
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  // ── Bu bilgisayar: tarama ─────────────────────────────────────────────────
  Future<void> scanThisPc() async {
    scanning = true;
    notifyListeners();
    steamPath = SteamEnv.installPath();
    if (steamPath != null) {
      installed = await compute(installedGames, steamPath!);
      thisUser = activeUser(steamPath!);
      if (apiKey.isNotEmpty && thisUser.known) {
        thisPcOwned = await fetchOwnedGames(thisUser.steam64, apiKey);
      }
    }
    for (final g in [...installed, ...thisPcOwned]) {
      ps.names[g.appId] = g.name;
    }
    scanning = false;
    notifyListeners();
  }

  /// Seçili hesabı yeniden tara / kütüphaneyi tazele.
  Future<void> refresh() async {
    if (selected == thisPcId) {
      await scanThisPc();
    }
  }

  // ── Kütüphane ─────────────────────────────────────────────────────────────
  /// Bir hesabın gösterilecek tüm oyunları (süzgeç öncesi).
  List<Game> gamesFor(String id) {
    final map = <int, Game>{};
    void put(Game g) {
      final cur = map[g.appId];
      if (cur == null) {
        map[g.appId] = Game(
          appId: g.appId,
          name: g.name,
          installed: g.installed,
          playtimeMin: g.playtimeMin,
          custom: g.custom,
        );
      } else {
        if (cur.name.startsWith('App ') && !g.name.startsWith('App ')) cur.name = g.name;
        cur.installed = cur.installed || g.installed;
        cur.playtimeMin ??= g.playtimeMin;
      }
    }

    if (id == thisPcId) {
      thisPcOwned.forEach(put);
      installed.forEach(put);
    } else {
      remotes[id]?.owned.forEach(put);
      // Kurulu oyun adları bu bilgisayardan da gelebilir
      for (final g in installed) {
        if (map.containsKey(g.appId)) {
          map[g.appId]!.name = g.name;
        }
      }
    }
    for (final c in ps.custom[id] ?? const <CustomGame>[]) {
      final g = map[c.appId];
      if (g == null) {
        map[c.appId] = Game(appId: c.appId, name: c.name, custom: true);
      } else {
        g.custom = true;
      }
    }
    // Kasılması istenen ama listede olmayanlar da görünsün.
    for (final a in idlingIds(id)) {
      map.putIfAbsent(a, () => Game(appId: a, name: _nameAnywhere(a)));
    }
    return map.values.toList()..sort((a, b) => a.lower.compareTo(b.lower));
  }

  String _nameAnywhere(int appId) {
    for (final g in installed) {
      if (g.appId == appId) return g.name;
    }
    for (final g in thisPcOwned) {
      if (g.appId == appId) return g.name;
    }
    for (final r in remotes.values) {
      for (final g in r.owned) {
        if (g.appId == appId) return g.name;
      }
    }
    return 'App $appId';
  }

  /// Seçili hesap için görünür liste (sekme + arama + "yalnız oyunlar").
  List<Game> visibleGames() {
    final all = gamesFor(selected);
    final favs = favoritesOf(selected);
    final idling = idlingIds(selected).toSet();
    final q = query.trim().toLowerCase();
    return [
      for (final g in all)
        if (_inTab(g, favs, idling) &&
            (q.isEmpty || g.lower.contains(q) || '${g.appId}'.contains(q)) &&
            (!settings.gamesOnly || tab == LibTab.idling || idling.contains(g.appId) || g.custom || isProbablyGame(g)))
          g,
    ];
  }

  bool _inTab(Game g, Set<int> favs, Set<int> idling) => switch (tab) {
        LibTab.installed => g.installed,
        LibTab.library => true,
        LibTab.favorites => favs.contains(g.appId),
        LibTab.idling => idling.contains(g.appId),
      };

  Set<int> favoritesOf(String id) => ps.favorites.putIfAbsent(id, () => {});

  void toggleFavorite(int appId) {
    final f = favoritesOf(selected);
    if (!f.remove(appId)) f.add(appId);
    _save();
    notifyListeners();
  }

  void addCustomGame(int appId, String name) {
    final list = ps.custom.putIfAbsent(selected, () => []);
    if (!list.any((c) => c.appId == appId)) {
      list.add(CustomGame(appId, name.isEmpty ? _nameAnywhere(appId) : name));
    }
    _save();
    notifyListeners();
  }

  void removeCustomGame(int appId) {
    ps.custom[selected]?.removeWhere((c) => c.appId == appId);
    _save();
    notifyListeners();
  }

  // ── Kasma durumu ──────────────────────────────────────────────────────────
  List<int> idlingIds(String id) {
    if (id == thisPcId) return thisPc.wanted.toList();
    return accountOf(id)?.appIds ?? const [];
  }

  bool isIdling(String id, int appId) => idlingIds(id).contains(appId);

  /// Gerçekten Steam'e bildirilmiş (çalışıyor) mu?
  bool isLive(String id, int appId) {
    if (id == thisPcId) return thisPc.workers[appId]?.phase == WorkerPhase.running;
    final r = remotes[id];
    return r != null && r.isLoggedOn && isIdling(id, appId);
  }

  DateTime? liveSince(String id, int appId) {
    if (id == thisPcId) {
      final w = thisPc.workers[appId];
      return w?.phase == WorkerPhase.running ? w!.startedAt : null;
    }
    return remotes[id]?.loggedOnAt;
  }

  int totalLive() {
    var n = thisPc.runningCount;
    for (final a in ps.accounts) {
      final r = remotes[a.id];
      if (r != null && r.isLoggedOn) n += a.appIds.length;
    }
    return n;
  }

  int liveAccounts() {
    var n = thisPc.runningCount > 0 ? 1 : 0;
    for (final a in ps.accounts) {
      final r = remotes[a.id];
      if (r != null && r.isLoggedOn && a.appIds.isNotEmpty) n++;
    }
    return n;
  }

  /// Bir oyunun kasılmasını aç/kapat. Hata varsa anahtar döndürür.
  Future<String?> toggleIdle(int appId) async {
    if (selected == thisPcId) {
      if (!thisPc.isIdling(appId) && !thisPc.steamReady && thisPc.wanted.isEmpty && !SteamEnv.ready()) {
        // Steam kapalıyken de sıraya alınabilir; Steam açılınca başlar.
      }
      final ok = thisPc.toggle(appId);
      return ok ? null : 'limit';
    }
    final a = accountOf(selected);
    final r = remotes[selected];
    if (a == null || r == null) return null;
    if (a.appIds.contains(appId)) {
      a.appIds.remove(appId);
    } else {
      if (a.appIds.length >= kMaxConcurrent) return 'limit';
      a.appIds.add(appId);
    }
    await _save();
    notifyListeners();
    return _syncRemote(a, r);
  }

  Future<String?> _syncRemote(AccountInfo a, RemoteAccount r) async {
    if (r.isLoggedOn) {
      r.setGames(a.appIds);
      if (a.appIds.isEmpty) {
        // Boşta oturum açık tutmaya gerek yok.
        await r.stop();
      }
      return null;
    }
    if (a.appIds.isEmpty) return null;
    final t = await store.readToken(a.id);
    if (t == null || a.accountName.isEmpty) return 'need_login';
    if (!r.running || r.state == RemoteState.idle || r.state == RemoteState.error || r.state == RemoteState.tokenInvalid) {
      await r.loginToken(a.accountName, t, a.appIds);
    }
    return null;
  }

  Future<void> stopAllSelected() async {
    if (selected == thisPcId) {
      thisPc.stopAll();
    } else {
      final a = accountOf(selected);
      final r = remotes[selected];
      if (a == null || r == null) return;
      a.appIds.clear();
      await _save();
      await r.stop();
    }
    notifyListeners();
  }

  Future<void> stopEverything() async {
    thisPc.stopAll();
    for (final a in ps.accounts) {
      a.appIds.clear();
      await remotes[a.id]?.stop();
    }
    await _save();
    notifyListeners();
  }

  // ── Hesaplar ──────────────────────────────────────────────────────────────
  String _newId() => 'acc${Random().nextInt(0xFFFFFF).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch % 100000}';

  /// Hesap ekleme akışını başlatır; henüz kalıcı değil.
  RemoteAccount beginAddAccount() {
    final id = _newId();
    pendingId = id;
    final a = AccountInfo(id: id);
    return _attach(a)..onIdentity = () => _identity(a, remotes[id]!);
  }

  /// Girişi tamamlanan hesabı kalıcı yapar.
  Future<AccountInfo> commitPending({String label = ''}) async {
    final id = pendingId!;
    final r = remotes[id]!;
    final a = AccountInfo(
      id: id,
      label: label,
      accountName: r.accountName,
      persona: r.persona,
      steam64: r.steam64,
    );
    r.onIdentity = () => _identity(a, r);
    ps.accounts.add(a);
    pendingId = null;
    selected = id;
    tab = LibTab.library;
    await _save();
    notifyListeners();
    return a;
  }

  /// Girişi tamamlanmadan vazgeçilen hesabı temizler.
  Future<void> discardPending() async {
    final id = pendingId;
    if (id == null) return;
    pendingId = null;
    final r = remotes.remove(id);
    await r?.stop();
    r?.dispose();
    await store.deleteToken(id);
    notifyListeners();
  }

  /// Mevcut hesabı yeniden giriş yaptırmak için hazırlar (token geçersiz).
  RemoteAccount reauth(String id) => remotes[id]!;

  Future<void> removeAccount(String id) async {
    final r = remotes.remove(id);
    await r?.stop();
    r?.dispose();
    ps.accounts.removeWhere((a) => a.id == id);
    ps.favorites.remove(id);
    ps.custom.remove(id);
    await store.deleteToken(id);
    if (selected == id) selected = thisPcId;
    await _save();
    notifyListeners();
  }

  void renameAccount(String id, String label) {
    accountOf(id)?.label = label.trim();
    _save();
    notifyListeners();
  }

  // ── Seçim ─────────────────────────────────────────────────────────────────
  void select(String id) {
    if (selected == id) return;
    selected = id;
    tab = id == thisPcId ? LibTab.installed : LibTab.library;
    query = '';
    notifyListeners();
  }

  void setTab(LibTab t) {
    tab = t;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ── Ayarlar ───────────────────────────────────────────────────────────────
  Future<void> setApiKey(String key) async {
    apiKey = key.trim();
    await store.writeApiKey(apiKey);
    await scanThisPc();
  }

  void setLang(String l) {
    settings.lang = l;
    _save();
    notifyListeners();
    ach.reloadSelected();
  }

  void setGamesOnly(bool v) {
    settings.gamesOnly = v;
    _save();
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await _save();
    notifyListeners();
  }

  Future<void> probeEngine() async {
    probing = true;
    notifyListeners();
    python = await probePython();
    for (final r in remotes.values) {
      r.python = python;
    }
    probing = false;
    notifyListeners();
  }

  Future<void> _save() => store.save(ps, open: _openRecs());

  // ── İstatistikler: kasma süresi kaydı ─────────────────────────────────────
  /// anahtar ('thispc:730' / 'accId:730') → (appId, başlangıç)
  final Map<String, (int, DateTime)> _open = {};

  Set<String> _liveKeys() => {
        for (final e in thisPc.workers.entries)
          if (e.value.phase == WorkerPhase.running) '$thisPcId:${e.key}',
        for (final a in ps.accounts)
          if (remotes[a.id]?.isLoggedOn ?? false)
            for (final id in a.appIds) '${a.id}:$id',
      };

  void _syncSessions() {
    final live = _liveKeys();
    for (final k in live) {
      _open.putIfAbsent(k, () => (int.parse(k.split(':').last), DateTime.now()));
    }
    for (final k in _open.keys.toList()) {
      if (!live.contains(k)) _closeSession(k);
    }
  }

  void _closeSession(String k) {
    final o = _open.remove(k);
    if (o == null) return;
    final end = DateTime.now();
    if (end.difference(o.$2).inSeconds >= 10) {
      ps.sessions.add(SessionRec(o.$1, o.$2.millisecondsSinceEpoch, end.millisecondsSinceEpoch));
      _save();
    }
  }

  List<SessionRec> _openRecs() => [
        for (final o in _open.values)
          SessionRec(o.$1, o.$2.millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch),
      ];

  Iterable<SessionRec> get _allSessions => [...ps.sessions, ..._openRecs()];

  Duration _sum(Iterable<SessionRec> r, {int? from, int? to}) {
    var ms = 0;
    for (final x in r) {
      final a = from != null && x.start < from ? from : x.start;
      final b = to != null && x.end > to ? to : x.end;
      if (b > a) ms += b - a;
    }
    return Duration(milliseconds: ms);
  }

  Duration get boostedAll => _sum(_allSessions);

  Duration boostedOn(DateTime day) {
    final from = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    return _sum(_allSessions, from: from, to: from + const Duration(days: 1).inMilliseconds);
  }

  List<(DateTime, Duration)> lastDays(int n) {
    final now = DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        (DateTime(now.year, now.month, now.day).subtract(Duration(days: i)), boostedOn(now.subtract(Duration(days: i)))),
    ];
  }

  /// En çok kasılan oyunlar: (appId, süre).
  List<(int, Duration)> topGames([int n = 8]) {
    final by = <int, List<SessionRec>>{};
    for (final r in _allSessions) {
      by.putIfAbsent(r.appId, () => []).add(r);
    }
    final out = [for (final e in by.entries) (e.key, _sum(e.value))]..sort((a, b) => b.$2.compareTo(a.$2));
    return out.take(n).toList();
  }

  String nameOf(int appId) => ps.names[appId] ?? _nameAnywhere(appId);

  void setSection(Section s) {
    if (section == s) return;
    section = s;
    notifyListeners();
  }

  // ── Kapanış ───────────────────────────────────────────────────────────────
  Future<void> shutdown() async {
    _ticker?.cancel();
    _saver?.cancel();
    ach.dispose();
    for (final k in _open.keys.toList()) {
      _closeSession(k);
    }
    await _save();
    await thisPc.shutdown();
    for (final r in remotes.values) {
      await r.stop();
    }
  }
}
