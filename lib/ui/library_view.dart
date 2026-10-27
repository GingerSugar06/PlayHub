library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../engine/remote_account.dart';
import '../engine/this_pc.dart';
import '../state/app_state.dart';
import '../steam/library_scan.dart';
import 'dialogs.dart';
import 'widgets.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final id = app.selected;
    final games = app.visibleGames();

    return Column(children: [
      _Header(app: app),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(children: [
          _Banners(app: app),
          _Toolbar(app: app),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(child: _GameList(app: app, games: games)),
      if (app.totalLive() > 0) _BottomBar(app: app, key: ValueKey('bar$id')),
      // s kullanılmıyor uyarısını önlemek için
      if (s.code.isEmpty) const SizedBox.shrink(),
    ]);
  }
}

// ── Başlık ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final isPc = app.selected == thisPcId;
    final a = app.accountOf(app.selected);
    final name = isPc
        ? (app.thisUser.persona.isNotEmpty ? app.thisUser.persona : s.t('this_pc'))
        : (a?.display.isNotEmpty ?? false ? a!.display : s.t('connecting'));
    final sub = isPc
        ? [
            if (app.thisUser.accountName.isNotEmpty) '@${app.thisUser.accountName}',
            if (app.thisUser.steam64.isNotEmpty) app.thisUser.steam64,
          ].join('  ·  ')
        : [
            if ((a?.accountName ?? '').isNotEmpty) '@${a!.accountName}',
            if ((a?.steam64 ?? '').isNotEmpty) a!.steam64,
          ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              _StatusPill(app: app),
            ]),
            const SizedBox(height: 4),
            Text(sub.isEmpty ? (isPc ? s.t('this_pc_desc') : s.t('remote_desc')) : sub,
                style: const TextStyle(color: C.text2, fontSize: 12.5)),
          ]),
        ),
        if (isPc)
          IconButton(
            tooltip: s.t('refresh'),
            onPressed: app.scanning ? null : app.refresh,
            icon: app.scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          )
        else
          PopupMenuButton<String>(
            tooltip: s.t('more'),
            color: C.surface2,
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) async {
              if (v == 'rename') {
                showRename(context, app, app.selected);
              } else if (v == 'relogin') {
                showAddAccount(context, app, reauthId: app.selected);
              } else if (v == 'remove') {
                final ok = await confirm(context,
                    title: s.t('remove_title'),
                    message: s.t('remove_msg'),
                    yes: s.t('remove'),
                    no: s.t('cancel'),
                    danger: true);
                if (ok) await app.removeAccount(app.selected);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(s.t('rename'))),
              PopupMenuItem(value: 'relogin', child: Text(s.t('relogin'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'remove', child: Text(s.t('remove'), style: const TextStyle(color: C.red))),
            ],
          ),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final s = app.s;
    if (app.selected == thisPcId) {
      final t = app.thisPc;
      if (!t.steamRunning) return Pill(s.t('steam_not_running'), color: C.text3);
      if (!t.steamReady) return Pill(s.t('steam_not_signed'), color: C.amber);
      return Pill(s.t('steam_ready'), color: C.green, icon: Icons.check_rounded);
    }
    final r = app.remotes[app.selected];
    if (r == null) return const SizedBox.shrink();
    final (text, color) = switch (r.state) {
      RemoteState.loggedOn => (s.t('st_logged_on'), C.green),
      RemoteState.connecting => (s.t('st_connecting'), C.amber),
      RemoteState.disconnected => (s.t('st_disconnected'), C.amber),
      RemoteState.tokenInvalid => (s.t('st_token_invalid'), C.red),
      RemoteState.badPassword => (s.t('st_bad_password'), C.red),
      RemoteState.rateLimited => (s.t('st_rate_limited'), C.red),
      RemoteState.error => (s.t('st_error'), C.red),
      _ => (s.t('acc_offline'), C.text3),
    };
    return Pill(text, color: color);
  }
}

// ── Uyarı şeritleri ─────────────────────────────────────────────────────────

class _Banners extends StatelessWidget {
  const _Banners({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final list = <Widget>[];
    if (app.selected == thisPcId) {
      final t = app.thisPc;
      if (t.workerMissing) {
        list.add(Banner2(text: s.t('worker_missing'), color: C.red, icon: Icons.build_circle_outlined));
      } else if (!t.steamReady && t.wanted.isNotEmpty) {
        list.add(Banner2(text: s.t('queued_waiting_steam'), icon: Icons.hourglass_top_rounded));
      } else if (!t.steamReady && app.installed.isEmpty && app.steamPath == null) {
        list.add(Banner2(text: s.t('steam_missing'), color: C.red));
      }
    } else {
      final r = app.remotes[app.selected];
      if (r != null) {
        if (r.state == RemoteState.error && (r.message == 'python_missing' || r.message == 'deps_missing')) {
          list.add(Banner2(
            text: s.t(r.message == 'python_missing' ? 'engine_python_missing' : 'engine_deps_missing'),
            color: C.red,
            icon: Icons.terminal_rounded,
            action: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => showSettings(context, app),
              child: Text(s.t('engine_setup')),
            ),
          ));
        } else if (r.state == RemoteState.tokenInvalid || r.state == RemoteState.badPassword) {
          list.add(Banner2(
            text: s.t('session_expired'),
            color: C.red,
            icon: Icons.lock_clock_rounded,
            action: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => showAddAccount(context, app, reauthId: app.selected),
              child: Text(s.t('relogin')),
            ),
          ));
        } else if (r.state == RemoteState.error) {
          list.add(Banner2(text: '${s.t('st_error')}: ${r.message}', color: C.red));
        } else if (r.state == RemoteState.idle && (app.accountOf(app.selected)?.appIds.isNotEmpty ?? false)) {
          list.add(Banner2(text: s.t('queued_not_connected'), icon: Icons.hourglass_top_rounded));
        }
      }
    }
    return Column(children: list);
  }
}

// ── Araç çubuğu ─────────────────────────────────────────────────────────────

class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.app});
  final AppState app;
  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  final _ctrl = TextEditingController();
  String _lastSel = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.s;
    if (_lastSel != app.selected) {
      _lastSel = app.selected;
      _ctrl.text = '';
    }
    final idlingN = app.idlingIds(app.selected).length;
    final favN = app.favoritesOf(app.selected).length;

    Widget tab(LibTab t, String label, {int? count}) {
      final on = app.tab == t;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => app.setTab(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? C.blue.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: on ? C.blue : C.text2)),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(fontSize: 12, color: on ? C.blue : C.text3, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            onChanged: app.setQuery,
            decoration: InputDecoration(
              hintText: s.t('search_hint'),
              prefixIcon: const Icon(Icons.search_rounded, size: 21),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        app.setQuery('');
                        setState(() {});
                      }),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: s.t('add_appid_tip'),
          child: OutlinedButton.icon(
            onPressed: () => showAddAppId(context, app),
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('AppID'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: C.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (app.selected == thisPcId) tab(LibTab.installed, s.t('tab_installed')),
            tab(LibTab.library, s.t('tab_library')),
            tab(LibTab.favorites, s.t('tab_favorites'), count: favN),
            tab(LibTab.idling, s.t('tab_idling'), count: idlingN),
          ]),
        ),
        const Spacer(),
        Text(s.t('games_only'), style: const TextStyle(color: C.text2, fontSize: 13)),
        const SizedBox(width: 6),
        Switch(value: app.settings.gamesOnly, onChanged: app.setGamesOnly),
      ]),
    ]);
  }
}

// ── Oyun listesi ────────────────────────────────────────────────────────────

class _GameList extends StatelessWidget {
  const _GameList({required this.app, required this.games});
  final AppState app;
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    if (app.scanning && games.isEmpty && app.selected == thisPcId) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (games.isEmpty) {
      return switch (app.tab) {
        LibTab.favorites => EmptyState(icon: Icons.favorite_border_rounded, title: s.t('empty_fav'), message: s.t('empty_fav_msg')),
        LibTab.idling => EmptyState(icon: Icons.bolt_outlined, title: s.t('empty_idling'), message: s.t('empty_idling_msg')),
        _ => app.query.isNotEmpty
            ? EmptyState(icon: Icons.search_off_rounded, title: s.t('empty_search'), message: s.t('empty_search_msg'))
            : _noGames(context),
      };
    }
    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        itemCount: games.length,
        itemExtent: 66,
        itemBuilder: (_, i) => GameRow(key: ValueKey('${app.selected}-${games[i].appId}'), app: app, game: games[i]),
      ),
    );
  }

  Widget _noGames(BuildContext context) {
    final s = app.s;
    if (app.selected == thisPcId) {
      return EmptyState(
        icon: Icons.sports_esports_outlined,
        title: s.t('empty_pc'),
        message: app.apiKey.isEmpty ? '${s.t('empty_pc_msg')}\n${s.t('api_key_hint_short')}' : s.t('empty_pc_msg'),
        action: OutlinedButton(onPressed: () => showSettings(context, app), child: Text(s.t('settings'))),
      );
    }
    final r = app.remotes[app.selected];
    final loading = r != null && (r.isLoggedOn || r.state == RemoteState.connecting);
    return EmptyState(
      icon: Icons.cloud_sync_outlined,
      title: loading ? s.t('loading_library') : s.t('empty_remote'),
      message: loading ? s.t('loading_library_msg') : s.t('empty_remote_msg'),
    );
  }
}

class GameRow extends StatefulWidget {
  const GameRow({super.key, required this.app, required this.game});
  final AppState app;
  final Game game;
  @override
  State<GameRow> createState() => _GameRowState();
}

class _GameRowState extends State<GameRow> {
  bool _h = false;

  Future<void> _toggle() async {
    final app = widget.app;
    final err = await app.toggleIdle(widget.game.appId);
    if (!mounted || err == null) return;
    final s = app.s;
    if (err == 'limit') {
      toast(context, s.t('limit_reached', {'n': '$kMaxConcurrent'}), error: true);
    } else if (err == 'need_login') {
      toast(context, s.t('need_login'), error: true);
      showAddAccount(context, app, reauthId: app.selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.s;
    final g = widget.game;
    final id = app.selected;
    final idling = app.isIdling(id, g.appId);
    final live = app.isLive(id, g.appId);
    final fav = app.favoritesOf(id).contains(g.appId);
    final since = app.liveSince(id, g.appId);

    final worker = id == thisPcId ? app.thisPc.workers[g.appId] : null;
    final failed = worker?.phase == WorkerPhase.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
          decoration: BoxDecoration(
            color: _h ? C.surface2 : C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: live ? C.green.withValues(alpha: 0.5) : (idling ? C.amber.withValues(alpha: 0.4) : C.line)),
          ),
          child: Row(children: [
            GameCover(game: g),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Row(children: [
                  Text('${g.appId}', style: mono(11.5, color: C.text3)),
                  if (g.playtimeMin != null) ...[
                    const SizedBox(width: 10),
                    Text(fmtPlaytime(g.playtimeMin), style: const TextStyle(color: C.text3, fontSize: 11.5)),
                  ],
                  if (g.installed) ...[const SizedBox(width: 10), Pill(s.t('installed'), color: C.blue)],
                  if (g.custom) ...[const SizedBox(width: 10), Pill(s.t('custom'), color: C.text2)],
                ]),
              ]),
            ),
            if (g.custom)
              IconButton(
                tooltip: s.t('remove_custom'),
                visualDensity: VisualDensity.compact,
                onPressed: idling ? null : () => app.removeCustomGame(g.appId),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            IconButton(
              tooltip: fav ? s.t('fav_remove') : s.t('fav_add'),
              visualDensity: VisualDensity.compact,
              onPressed: () => app.toggleFavorite(g.appId),
              icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: fav ? C.heart : C.text3),
            ),
            const SizedBox(width: 6),
            _IdleButton(
              idling: idling,
              live: live,
              failed: failed,
              since: since,
              onTap: _toggle,
              label: s.t('idle'),
              stopLabel: s.t('stop'),
              waitingLabel: failed ? s.t('retrying') : s.t('waiting'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _IdleButton extends StatelessWidget {
  const _IdleButton({
    required this.idling,
    required this.live,
    required this.failed,
    required this.since,
    required this.onTap,
    required this.label,
    required this.stopLabel,
    required this.waitingLabel,
  });
  final bool idling, live, failed;
  final DateTime? since;
  final VoidCallback onTap;
  final String label, stopLabel, waitingLabel;

  @override
  Widget build(BuildContext context) {
    if (!idling) {
      return SizedBox(
        width: 128,
        height: 38,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(label),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
        ),
      );
    }
    final color = live ? C.green : (failed ? C.red : C.amber);
    final started = since;
    return SizedBox(
      width: 128,
      height: 38,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.16),
          foregroundColor: color,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.stop_rounded, size: 18),
          const SizedBox(width: 6),
          Text(
            live && started != null ? fmtClock(DateTime.now().difference(started)) : waitingLabel,
            style: live ? mono(12.5, color: color, w: FontWeight.w600) : TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

// ── Alt çubuk ───────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final here = app.idlingIds(app.selected).length;
    final total = app.totalLive();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(color: C.panel, border: Border(top: BorderSide(color: C.line))),
      child: Row(children: [
        StatusDot(total > 0 ? C.green : C.text3, pulse: total > 0),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            total > 0 ? s.t('total_idling', {'a': '${app.liveAccounts()}', 'g': '$total'}) : s.t('nothing_idling'),
            style: TextStyle(color: total > 0 ? C.text : C.text2, fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ),
        if (here > 0)
          OutlinedButton.icon(
            onPressed: app.stopAllSelected,
            icon: const Icon(Icons.stop_rounded, size: 19),
            label: Text(s.t('stop_here')),
          ),
        if (total > here) ...[
          const SizedBox(width: 8),
          TextButton(onPressed: app.stopEverything, child: Text(s.t('stop_everything'))),
        ],
      ]),
    );
  }
}
