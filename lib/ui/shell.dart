library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../achievements/achievements_page.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'boost_page.dart';
import 'dialogs.dart';
import 'stats_page.dart';
import 'widgets.dart';

class Shell extends StatelessWidget {
  const Shell({super.key, required this.app});
  final AppState app;

  Widget _page() => switch (app.section) {
        Section.boost => BoostPage(app: app),
        Section.achievements => AchievementsPage(app: app),
        Section.stats => StatsPage(app: app),
        Section.settings => SettingsPage(app: app),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          body: Column(children: [
            const _TitleBar(),
            const Divider(height: 1),
            Expanded(
              child: Row(children: [
                SizedBox(width: 224, child: NavRail(app: app)),
                const VerticalDivider(width: 1),
                Expanded(child: ColoredBox(color: C.bg, child: _page())),
              ]),
            ),
          ]),
        ),
      );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();
  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        color: C.panel,
        child: Row(children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.play_arrow_rounded, size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text('Play Hub', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          _WinBtn(Icons.remove_rounded, () => windowManager.minimize()),
          _WinBtn(Icons.crop_square_rounded, () async {
            (await windowManager.isMaximized()) ? windowManager.unmaximize() : windowManager.maximize();
          }, size: 15),
          _WinBtn(Icons.close_rounded, () => windowManager.close(), danger: true),
        ]),
      );
}

class _WinBtn extends StatefulWidget {
  const _WinBtn(this.icon, this.onTap, {this.danger = false, this.size = 18});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double size;
  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 48,
            height: 44,
            color: _h ? (widget.danger ? C.red : C.surface2) : Colors.transparent,
            child: Icon(widget.icon, size: widget.size, color: _h && widget.danger ? Colors.white : C.text),
          ),
        ),
      );
}

// ── Sol gezinme ─────────────────────────────────────────────────────────────

class NavRail extends StatelessWidget {
  const NavRail({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final live = app.totalLive();
    return Container(
      color: C.panel,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      child: Column(children: [
        _NavItem(app: app, section: Section.boost, icon: Icons.bolt_rounded, label: s.t('nav_boost'), badge: live > 0 ? '$live' : null),
        _NavItem(app: app, section: Section.achievements, icon: Icons.emoji_events_rounded, label: s.t('nav_ach')),
        _NavItem(app: app, section: Section.stats, icon: Icons.insights_rounded, label: s.t('nav_stats')),
        const Spacer(),
        if (live > 0) ...[_Summary(app: app), const SizedBox(height: 10)],
        _NavItem(app: app, section: Section.settings, icon: Icons.settings_rounded, label: s.t('settings')),
      ]),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final n = app.totalLive();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusDot(n > 0 ? C.green : C.text3, pulse: n > 0),
          const SizedBox(width: 8),
          Expanded(
            child: Text(n > 0 ? s.t('total_idling', {'a': '${app.liveAccounts()}', 'g': '$n'}) : s.t('nothing_idling'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: n > 0 ? C.text : C.text2)),
          ),
        ]),
        if (n > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton(
              onPressed: app.stopEverything,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              child: Text(s.t('stop_everything')),
            ),
          ),
        ],
      ]),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.app, required this.section, required this.icon, required this.label, this.badge});
  final AppState app;
  final Section section;
  final IconData icon;
  final String label;
  final String? badge;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.app.section == widget.section;
    final color = sel ? C.blue : C.text2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.app.setSection(widget.section),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: sel ? C.blue.withValues(alpha: 0.1) : (_h ? C.surface2 : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(widget.icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? C.blue : C.text)),
              ),
              if (widget.badge != null) Pill(widget.badge!, color: C.green),
            ]),
          ),
        ),
      ),
    );
  }
}
