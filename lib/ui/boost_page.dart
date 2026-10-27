/// "Saat kasma" sayfası: üstte hesap seçici, altında oyun kütüphanesi.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../engine/remote_account.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'library_view.dart';
import 'widgets.dart';

class BoostPage extends StatelessWidget {
  const BoostPage({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => Column(children: [
        AccountBar(app: app),
        const Divider(height: 1),
        Expanded(child: LibraryView(app: app)),
      ]);
}

class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    return Container(
      height: 68,
      color: C.panel,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _AccountChip(
                app: app,
                id: thisPcId,
                title: s.t('this_pc'),
                subtitle: app.thisUser.persona.isNotEmpty ? app.thisUser.persona : s.t('this_pc_sub'),
              ),
              for (final a in app.accounts)
                _AccountChip(
                  app: app,
                  id: a.id,
                  title: a.display.isEmpty ? s.t('connecting') : a.display,
                  subtitle: a.accountName,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => showAddAccount(context, app),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: Text(s.t('add_account')),
        ),
      ]),
    );
  }
}

class _AccountChip extends StatefulWidget {
  const _AccountChip({required this.app, required this.id, required this.title, required this.subtitle});
  final AppState app;
  final String id;
  final String title;
  final String subtitle;
  @override
  State<_AccountChip> createState() => _AccountChipState();
}

class _AccountChipState extends State<_AccountChip> {
  bool _h = false;

  (Color, String) _status() {
    final app = widget.app;
    final s = app.s;
    if (widget.id == thisPcId) {
      final n = app.thisPc.runningCount;
      if (n > 0) return (C.green, s.t('acc_idling', {'n': '$n'}));
      if (app.thisPc.wanted.isNotEmpty) return (C.amber, s.t('acc_waiting'));
      if (app.thisPc.steamReady) return (C.blue, s.t('acc_online'));
      return (C.text3, s.t('acc_steam_off'));
    }
    final r = app.remotes[widget.id];
    final a = app.accountOf(widget.id);
    if (r == null) return (C.text3, s.t('acc_offline'));
    switch (r.state) {
      case RemoteState.loggedOn:
        final n = a?.appIds.length ?? 0;
        return n > 0 ? (C.green, s.t('acc_idling', {'n': '$n'})) : (C.blue, s.t('acc_online'));
      case RemoteState.connecting:
      case RemoteState.disconnected:
        return (C.amber, s.t('acc_connecting'));
      case RemoteState.tokenInvalid:
      case RemoteState.badPassword:
        return (C.red, s.t('acc_needs_login'));
      case RemoteState.error:
        return (C.red, s.t('acc_error'));
      default:
        return (C.text3, s.t('acc_offline'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.app.selected == widget.id;
    final (color, status) = _status();
    final isPc = widget.id == thisPcId;
    final letter = widget.title.isEmpty ? '?' : widget.title.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(right: 10, top: 10, bottom: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.app.select(widget.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 210,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: sel ? C.blue.withValues(alpha: 0.09) : (_h ? C.surface2 : C.bg),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? C.blue : C.line, width: sel ? 1.4 : 1),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: isPc
                          ? [const Color(0xFF2B6CB0), const Color(0xFF4DA3FF)]
                          : [const Color(0xFF5B4FCF), const Color(0xFF8B7BFF)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isPc
                    ? const Icon(Icons.desktop_windows_rounded, size: 18, color: Colors.white)
                    : Text(letter, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.25)),
                  Row(children: [
                    StatusDot(color, size: 7, pulse: color == C.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(status,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, height: 1.25)),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
