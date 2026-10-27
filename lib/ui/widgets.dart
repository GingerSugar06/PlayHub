/// Ortak parçalar.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../steam/library_scan.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.line),
        ),
        child: child,
      );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 9, this.pulse = false});
  final Color color;
  final double size;
  final bool pulse;
  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
        if (pulse) BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8),
      ]),
    );
    return dot;
  }
}

/// Küçük renkli rozet.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = C.text2, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Oyun kapağı: Steam CDN'den gelir; yoksa baş harf.
class GameCover extends StatelessWidget {
  const GameCover({super.key, required this.game, this.width = 112, this.height = 42});
  final Game game;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final letter = game.name.isEmpty ? '?' : game.name.characters.first.toUpperCase();
    Widget fallback() => Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          color: C.surface2,
          child: Text(letter, style: const TextStyle(color: C.text3, fontWeight: FontWeight.w700, fontSize: 16)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          coverUrl(game.appId),
          fit: BoxFit.cover,
          cacheWidth: (width * 2).round(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback(),
          loadingBuilder: (ctx, child, p) => p == null ? child : fallback(),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                    color: C.surface, shape: BoxShape.circle, border: Border.all(color: C.line)),
                child: Icon(icon, size: 30, color: C.text3),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!,
                    textAlign: TextAlign.center, style: const TextStyle(color: C.text2, fontSize: 13.5, height: 1.5)),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
            ]),
          ),
        ),
      );
}

/// Üstte duran uyarı şeridi.
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, this.color = C.amber, this.icon = Icons.info_outline_rounded, this.action});
  final String text;
  final Color color;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ]),
      );
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 19, color: error ? C.red : C.green),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      duration: const Duration(seconds: 3),
    ));
}

String fmtClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String fmtPlaytime(int? minutes) {
  if (minutes == null) return '';
  if (minutes < 60) return '${minutes}m';
  final h = minutes / 60;
  return '${h.toStringAsFixed(h >= 100 ? 0 : 1)}h';
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, required String yes, required String no, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(message, style: const TextStyle(color: C.text2, height: 1.5, fontSize: 14)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Sayfa başlığı: büyük başlık + tek satır açıklama + sağda eylemler.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle, this.actions = const []});
  final String title;
  final String subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.text2, fontSize: 13)),
            ]),
          ),
          ...actions,
        ]),
      );
}
