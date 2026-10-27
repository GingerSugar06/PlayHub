/// "İstatistikler": bugün / toplam / şu an, son 7 gün grafiği, en çok kasılanlar.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../steam/library_scan.dart';
import 'widgets.dart';

String fmtHours(Duration d) {
  if (d.inMinutes < 1) return d.inSeconds > 0 ? '${d.inSeconds}s' : '0m';
  if (d.inHours < 1) return '${d.inMinutes}m';
  final h = d.inMinutes / 60;
  return '${h.toStringAsFixed(h >= 100 ? 0 : 1)}h';
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final days = app.lastDays(7);
    final top = app.topGames();
    final maxDay = days.map((d) => d.$2.inSeconds).fold<int>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      PageHeader(title: s.t('nav_stats'), subtitle: s.t('page_stats_sub')),
      Expanded(
        child: Scrollbar(
          child: ListView(padding: const EdgeInsets.fromLTRB(28, 4, 28, 28), children: [
            Row(children: [
              Expanded(child: _Stat(label: s.t('stat_today'), value: fmtHours(app.boostedOn(DateTime.now())), icon: Icons.today_rounded)),
              const SizedBox(width: 14),
              Expanded(child: _Stat(label: s.t('stat_total'), value: fmtHours(app.boostedAll), icon: Icons.all_inclusive_rounded)),
              const SizedBox(width: 14),
              Expanded(child: _Stat(label: s.t('stat_running'), value: '${app.totalLive()}', icon: Icons.bolt_rounded, color: C.green)),
            ]),
            const SizedBox(height: 18),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('stat_last7'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 170,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final (day, dur) in days)
                      Expanded(child: _Bar(day: day, dur: dur, ratio: dur.inSeconds / maxDay, today: day.day == DateTime.now().day, tr: s.tr)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('stat_top'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 10),
                if (top.isEmpty)
                  SizedBox(
                    height: 210,
                    child: EmptyState(icon: Icons.insights_rounded, title: s.t('stat_none'), message: s.t('stat_none_msg')),
                  )
                else
                  for (final (i, (id, dur)) in top.indexed)
                    _TopRow(
                      rank: i + 1,
                      game: Game(appId: id, name: app.nameOf(id)),
                      dur: dur,
                      ratio: dur.inSeconds / (top.first.$2.inSeconds == 0 ? 1 : top.first.$2.inSeconds),
                    ),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, this.color = C.blue});
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.text2, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2)),
            ]),
          ),
        ]),
      );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day, required this.dur, required this.ratio, required this.today, required this.tr});
  final bool tr;
  final DateTime day;
  final Duration dur;
  final double ratio;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final wd = tr
        ? const ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
        : const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(children: [
        SizedBox(height: 18, child: Text(dur.inSeconds == 0 ? '' : fmtHours(dur), style: const TextStyle(fontSize: 11, color: C.text2))),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: dur.inSeconds == 0 ? 0.02 : ratio.clamp(0.04, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: dur.inSeconds == 0 ? C.line : (today ? C.blue : C.blue.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${day.day}.${day.month}', style: TextStyle(fontSize: 11.5, color: today ? C.text : C.text3, fontWeight: today ? FontWeight.w600 : FontWeight.w400)),
        Text(wd[day.weekday], style: const TextStyle(fontSize: 10.5, color: C.text3)),
      ]),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.rank, required this.game, required this.dur, required this.ratio});
  final int rank;
  final Game game;
  final Duration dur;
  final double ratio;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(children: [
          SizedBox(width: 24, child: Text('$rank', style: const TextStyle(color: C.text3, fontWeight: FontWeight.w600))),
          GameCover(game: game, width: 88, height: 33),
          const SizedBox(width: 14),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio.clamp(0.0, 1.0), minHeight: 5, color: C.blue, backgroundColor: C.surface2),
              ),
            ]),
          ),
          SizedBox(width: 72, child: Text(fmtHours(dur), textAlign: TextAlign.right, style: mono(13, w: FontWeight.w600))),
        ]),
      );
}
