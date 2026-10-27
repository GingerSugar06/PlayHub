/// "Başarımlar" sayfası: solda oyun listesi, sağda seçili oyunun başarımları.
///
/// Kutuya basmak Steam'e yazmaz; alttaki çubuk "N değişiklik · Uygula" der
/// (Ctrl+S). Durumu renk değil açıklık anlatır: kilitli satırlar soluk.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../ui/widgets.dart';
import 'achievements_state.dart';
import 'library_scan.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key, required this.app});
  final AppState app;
  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  final _searchFocus = FocusNode();
  final _searchCtrl = TextEditingController();

  AppState get app => widget.app;
  AchievementsState get st => app.ach;

  @override
  void initState() {
    super.initState();
    if (st.libraryState == LoadState.idle) st.loadLibrary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeIntro();
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchCtrl.dispose();
    st.release();
    super.dispose();
  }

  Future<void> _maybeIntro() async {
    if (app.settings.achIntroSeen || !mounted) return;
    final s = app.s;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.emoji_events_rounded, color: C.gold),
          const SizedBox(width: 10),
          Text(s.t('intro_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(s.t('intro_body'), style: const TextStyle(color: C.text2, height: 1.55, fontSize: 14)),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('intro_ok')))],
      ),
    );
    app.settings.achIntroSeen = true;
    app.saveSettings();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final s = app.s;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
              const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
                if (st.pendingCount > 0 && !st.applying) st.apply();
              },
            },
            child: Focus(
              autofocus: false,
              child: Column(children: [
                PageHeader(
                  title: s.t('nav_ach'),
                  subtitle: s.t('page_ach_sub'),
                  actions: [
                    if (st.libraryState == LoadState.ready)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(s.t('games_count', {'n': '${st.games.length}'}), style: const TextStyle(color: C.text2, fontSize: 13)),
                      ),
                    IconButton(
                      tooltip: s.t('refresh'),
                      onPressed: st.libraryState == LoadState.busy ? null : st.loadLibrary,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(children: [
                    SizedBox(width: 330, child: _GamesPane(st: st, s: s, focus: _searchFocus, ctrl: _searchCtrl)),
                    const VerticalDivider(width: 1),
                    Expanded(child: _AchPane(st: st, s: s)),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}

// ── Oyun listesi ────────────────────────────────────────────────────────────

class _GamesPane extends StatelessWidget {
  const _GamesPane({required this.st, required this.s, required this.focus, required this.ctrl});
  final AchievementsState st;
  final dynamic s;
  final FocusNode focus;
  final TextEditingController ctrl;

  @override
  Widget build(BuildContext context) {
    final list = st.visibleGames;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          onChanged: st.setQuery,
          decoration: InputDecoration(
            hintText: s.t('search_games'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 8),
        child: Row(children: [
          Expanded(child: Text(s.t('games_count', {'n': '${list.length}'}), style: const TextStyle(color: C.text3, fontSize: 12))),
          Text(s.t('only_installed'), style: const TextStyle(color: C.text2, fontSize: 12.5)),
          const SizedBox(width: 4),
          Transform.scale(scale: 0.8, child: Switch(value: st.installedOnly, onChanged: st.setInstalledOnly)),
        ]),
      ),
      Expanded(child: _body(list)),
    ]);
  }

  Widget _body(List<GameEntry> list) {
    if (st.libraryState == LoadState.busy || st.libraryState == LoadState.idle) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (st.libraryState == LoadState.failed) {
      return EmptyState(icon: Icons.link_off_rounded, title: s.t('ach_steam_missing'), message: s.t('ach_steam_missing_msg'));
    }
    if (list.isEmpty) {
      return st.query.isNotEmpty
          ? EmptyState(icon: Icons.search_off_rounded, title: s.t('no_match'), message: s.t('no_match_msg'))
          : EmptyState(icon: Icons.sports_esports_outlined, title: s.t('no_games'), message: s.t('no_games_msg'));
    }
    return Scrollbar(
      child: ListView.builder(
        itemExtent: 66,
        itemCount: list.length,
        padding: const EdgeInsets.only(bottom: 10),
        itemBuilder: (_, i) => _GameTile(game: list[i], selected: st.selected?.appId == list[i].appId, onTap: () => st.select(list[i])),
      ),
    );
  }
}

class _GameTile extends StatefulWidget {
  const _GameTile({required this.game, required this.selected, required this.onTap});
  final GameEntry game;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: sel ? C.blue.withValues(alpha: 0.09) : (_h ? C.surface2 : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? C.blue.withValues(alpha: 0.6) : Colors.transparent),
          ),
          child: Row(children: [
            _Cover(game: g, width: 36, height: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: sel ? FontWeight.w600 : FontWeight.w500)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: g.installed ? C.green : C.text3.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(width: 7),
                  Text('${g.appId}', style: mono(11, color: C.text3)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Kapak: önce Steam'in yerel önbelleği, sonra CDN, sonra baş harf.
class _Cover extends StatelessWidget {
  const _Cover({required this.game, required this.width, required this.height, this.radius = 7});
  final GameEntry game;
  final double width, height, radius;

  @override
  Widget build(BuildContext context) {
    final letter = game.name.trim().isEmpty ? '?' : game.name.trim().characters.first.toUpperCase();
    Widget fallback() => Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          color: C.surface2,
          child: Text(letter, style: TextStyle(fontSize: width * 0.4, fontWeight: FontWeight.w700, color: C.text3)),
        );
    Widget net() => Image.network(
          'https://cdn.cloudflare.steamstatic.com/steam/apps/${game.appId}/library_600x900.jpg',
          fit: BoxFit.cover,
          width: width,
          height: height,
          cacheWidth: (width * 2.5).round(),
          errorBuilder: (_, _, _) => fallback(),
          loadingBuilder: (_, child, p) => p == null ? child : fallback(),
        );
    final path = game.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: path == null
            ? net()
            : Image.file(File(path),
                fit: BoxFit.cover,
                width: width,
                height: height,
                cacheWidth: (width * 2.5).round(),
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => net()),
      ),
    );
  }
}

// ── Başarım paneli ──────────────────────────────────────────────────────────

class _AchPane extends StatelessWidget {
  const _AchPane({required this.st, required this.s});
  final AchievementsState st;
  final dynamic s;

  @override
  Widget build(BuildContext context) {
    if (st.selected == null) return _Welcome(s: s);
    if (st.gameState == LoadState.busy) {
      return const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (st.gameState == LoadState.failed) {
      return EmptyState(icon: Icons.error_outline_rounded, title: s.t('failed_open'), message: st.gameError ?? s.t('unknown_error'));
    }
    final rows = st.visibleRows;
    return Column(children: [
      _Header(st: st, s: s),
      const Divider(height: 1),
      Expanded(
        child: rows.isEmpty
            ? EmptyState(icon: Icons.filter_alt_off_outlined, title: s.t('no_filter_match'), message: s.t('no_filter_match_msg'))
            : Scrollbar(
                child: ListView.builder(
                  itemExtent: 68,
                  itemCount: rows.length,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemBuilder: (_, i) => _Row(st: st, s: s, row: rows[i]),
                ),
              ),
      ),
      if (st.pendingCount > 0 || st.applyResult != null) _ApplyBar(st: st, s: s),
    ]);
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.s});
  final dynamic s;
  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.sports_esports_rounded, s.t('step1'), s.t('step1_d')),
      (Icons.checklist_rounded, s.t('step2'), s.t('step2_d')),
      (Icons.save_rounded, s.t('step3'), s.t('step3_d')),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: C.gold.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_events_rounded, size: 38, color: C.gold),
            ),
            const SizedBox(height: 18),
            Text(s.t('pick_game'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(s.t('pick_game_msg'), textAlign: TextAlign.center, style: const TextStyle(color: C.text2, fontSize: 13.5, height: 1.55)),
            const SizedBox(height: 24),
            Row(children: [
              for (final (i, (icon, title, desc)) in steps.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: Panel(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(icon, size: 22, color: C.blue),
                      const SizedBox(height: 10),
                      Text('${i + 1}. $title', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.3)),
                      const SizedBox(height: 3),
                      Text(desc, style: const TextStyle(color: C.text3, fontSize: 11.5, height: 1.4)),
                    ]),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.st, required this.s});
  final AchievementsState st;
  final dynamic s;

  @override
  Widget build(BuildContext context) {
    final g = st.selected!;
    final total = st.rows.length;
    final done = st.unlockedCount;
    final ratio = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: C.panel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Cover(game: g, width: 44, height: 60, radius: 9),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                Text(s.t('unlocked_of', {'a': '$done', 'b': '$total'}),
                    style: const TextStyle(color: C.blue, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Text('${(ratio * 100).round()}%', style: const TextStyle(color: C.text3, fontSize: 12.5)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: ratio),
                  duration: const Duration(milliseconds: 400),
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: C.blue, backgroundColor: C.surface2),
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                decoration: InputDecoration(hintText: s.t('search_ach'), prefixIcon: const Icon(Icons.search_rounded, size: 19)),
                onChanged: st.setAchQuery,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Toggle(label: s.t('only_locked'), active: st.onlyLocked, onTap: () => st.setOnlyLocked(!st.onlyLocked)),
          const SizedBox(width: 6),
          _Toggle(label: s.t('hidden'), active: st.showHidden, onTap: () => st.setShowHidden(!st.showHidden)),
          const SizedBox(width: 6),
          _Small(icon: Icons.done_all_rounded, tip: s.t('unlock_visible'), onTap: () => st.setAllVisible(true)),
          _Small(icon: Icons.remove_done_rounded, tip: s.t('lock_visible'), onTap: () => st.setAllVisible(false)),
          _Small(icon: Icons.swap_horiz_rounded, tip: s.t('invert_visible'), onTap: st.invertVisible),
        ]),
      ]),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.st, required this.s, required this.row});
  final AchievementsState st;
  final dynamic s;
  final AchievementRow row;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final st = widget.st;
    final s = widget.s;
    final on = r.pending;
    final url = r.def.iconUrl(st.selected!.appId, unlocked: on);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: () => st.toggle(r, !r.pending),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 3, 14, 3),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _h ? C.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: r.changed ? C.amber.withValues(alpha: 0.7) : (_h ? C.line : Colors.transparent)),
          ),
          child: Row(children: [
            Opacity(
              opacity: on ? 1 : 0.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: url == null ? _fallback(on) : Image.network(url, fit: BoxFit.cover, cacheWidth: 92, errorBuilder: (_, _, _) => _fallback(on)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(r.def.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? C.text : C.text2)),
                  ),
                  if (r.def.hidden) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: s.t('hidden_badge'), child: const Icon(Icons.visibility_off_outlined, size: 14, color: C.text3)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(r.def.desc.isEmpty ? r.def.api : r.def.desc,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: on ? C.text2 : C.text3)),
              ]),
            ),
            if (r.changed) Pill(on ? s.t('will_unlock') : s.t('will_lock'), color: C.amber),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? C.blue : Colors.transparent,
                border: Border.all(color: on ? C.blue : C.text3, width: 1.6),
              ),
              child: on ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _fallback(bool on) => Container(
        color: C.surface2,
        child: Icon(Icons.emoji_events_outlined, size: 24, color: on ? C.gold : C.text3),
      );
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.st, required this.s});
  final AchievementsState st;
  final dynamic s;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(color: C.panel, border: Border(top: BorderSide(color: C.line))),
        child: Row(children: [
          if (st.pendingCount > 0) ...[
            const Icon(Icons.pending_actions_rounded, size: 19, color: C.amber),
            const SizedBox(width: 10),
            Text(s.t('changes_pending', {'n': '${st.pendingCount}'}),
                style: const TextStyle(fontSize: 13.5, color: C.amber, fontWeight: FontWeight.w600)),
          ] else if (st.applyResult != null) ...[
            const Icon(Icons.check_circle_outline_rounded, size: 19, color: C.green),
            const SizedBox(width: 10),
            Flexible(child: Text(st.applyResult!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: C.text2))),
          ],
          const Spacer(),
          if (st.pendingCount > 0) TextButton(onPressed: st.applying ? null : st.revert, child: Text(s.t('undo'))),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (st.applying || st.pendingCount == 0) ? null : st.apply,
            icon: st.applying
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text('${s.t('apply')}  ·  Ctrl+S'),
          ),
        ]),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? C.blue.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? C.blue : C.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? C.blue : C.text2)),
        ),
      );
}

class _Small extends StatelessWidget {
  const _Small({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tip, icon: Icon(icon, size: 19), onPressed: onTap, visualDensity: VisualDensity.compact);
}
