library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/autostart.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../engine/remote_account.dart';
import '../state/app_state.dart';
import 'widgets.dart';

// ═══ AppID ekle ═════════════════════════════════════════════════════════════

Future<void> showAddAppId(BuildContext context, AppState app) async {
  final s = app.s;
  final id = TextEditingController();
  final name = TextEditingController();
  String? err;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(s.t('add_appid'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('add_appid_msg'), style: const TextStyle(color: C.text2, fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 14),
            TextField(
              controller: id,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'AppID', hintText: '730'),
            ),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: InputDecoration(labelText: s.t('name_optional'))),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: C.red, fontSize: 12.5))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(id.text.trim());
              if (v == null || v <= 0) return setS(() => err = s.t('err_appid'));
              app.addCustomGame(v, name.text.trim());
              app.setTab(LibTab.library);
              Navigator.pop(ctx);
            },
            child: Text(s.t('add')),
          ),
        ],
      ),
    ),
  );
}

// ═══ Yeniden adlandır ═══════════════════════════════════════════════════════

Future<void> showRename(BuildContext context, AppState app, String id) async {
  final s = app.s;
  final a = app.accountOf(id);
  if (a == null) return;
  final c = TextEditingController(text: a.display);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('rename'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 340, child: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: s.t('nickname')))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
        FilledButton(
          onPressed: () {
            app.renameAccount(id, c.text);
            Navigator.pop(ctx);
          },
          child: Text(s.t('save')),
        ),
      ],
    ),
  );
}

// ═══ Hesap ekle / yeniden giriş ═════════════════════════════════════════════

Future<void> showAddAccount(BuildContext context, AppState app, {String? reauthId}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: _AddAccount(app: app, reauthId: reauthId),
      ),
    ),
  );
}

class _AddAccount extends StatefulWidget {
  const _AddAccount({required this.app, this.reauthId});
  final AppState app;
  final String? reauthId;
  @override
  State<_AddAccount> createState() => _AddAccountState();
}

class _AddAccountState extends State<_AddAccount> {
  late final RemoteAccount r;
  int mode = 0; // 0 = QR, 1 = şifre
  final nick = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  final code = TextEditingController();
  bool started = false;
  bool done = false;
  bool installing = false;
  final installLog = <String>[];

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    r = widget.reauthId != null ? app.reauth(widget.reauthId!) : app.beginAddAccount();
    r.addListener(_onChange);
    _ensureEngine();
  }

  @override
  void dispose() {
    r.removeListener(_onChange);
    nick.dispose();
    user.dispose();
    pass.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _ensureEngine() async {
    if (app.python == null) await app.probeEngine();
    r.python = app.python;
    if (mounted) {
      setState(() {});
      if (_engineReady && mode == 0) _startQr();
    }
  }

  bool get _engineReady => (app.python?.found ?? false) && (app.python?.depsOk ?? false);

  void _startQr() {
    if (started) return;
    started = true;
    r.loginQr(const []);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (r.state == RemoteState.loggedOn && !done) {
      done = true;
      _finish();
    }
  }

  Future<void> _finish() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.reauthId != null) {
      final a = app.accountOf(widget.reauthId!);
      if (a != null && a.appIds.isNotEmpty) r.setGames(a.appIds);
    } else {
      await app.commitPending(label: nick.text.trim());
    }
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(app.s.t('account_added'))));
  }

  Future<void> _cancel() async {
    if (widget.reauthId == null) {
      await app.discardPending();
    } else if (!r.isLoggedOn) {
      await r.stop();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.reauthId != null ? s.t('relogin') : s.t('add_account'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          IconButton(onPressed: _cancel, icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 4),
        Text(s.t('add_account_intro'), style: const TextStyle(color: C.text2, fontSize: 13, height: 1.5)),
        const SizedBox(height: 16),
        if (app.probing || app.python == null)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
        else if (!_engineReady)
          _engineSetup(s)
        else
          _flow(s),
      ]),
    );
  }

  // ── Motor kurulumu ────────────────────────────────────────────────────────
  Widget _engineSetup(S s) {
    final py = app.python!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Banner2(
        text: !py.found ? s.t('engine_python_missing') : s.t('engine_deps_missing'),
        color: C.amber,
        icon: Icons.terminal_rounded,
      ),
      if (!py.found)
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.https('www.python.org', '/downloads/'), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(s.t('download_python')),
        )
      else
        FilledButton.icon(
          onPressed: installing
              ? null
              : () async {
                  setState(() {
                    installing = true;
                    installLog.clear();
                  });
                  await installEngineDeps(py, (l) {
                    if (mounted) setState(() => installLog.add(l));
                  });
                  await app.probeEngine();
                  if (mounted) {
                    setState(() => installing = false);
                    if (_engineReady && mode == 0) _startQr();
                  }
                },
          icon: installing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download_rounded, size: 19),
          label: Text(installing ? s.t('installing') : s.t('install_deps')),
        ),
      if (installLog.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(installLog.takeLast(40).join('\n'), style: mono(11, color: C.text2)),
          ),
        ),
    ]);
  }

  // ── Giriş akışı ───────────────────────────────────────────────────────────
  Widget _flow(S s) {
    final st = r.state;
    final needCode = st == RemoteState.needTwoFa || st == RemoteState.needEmail || st == RemoteState.wrongCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.reauthId == null) ...[
        TextField(controller: nick, decoration: InputDecoration(labelText: s.t('nickname_optional'))),
        const SizedBox(height: 14),
      ],
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 0, icon: const Icon(Icons.qr_code_2_rounded, size: 18), label: Text(s.t('with_qr'))),
          ButtonSegment(value: 1, icon: const Icon(Icons.password_rounded, size: 18), label: Text(s.t('with_password'))),
        ],
        selected: {mode},
        onSelectionChanged: (v) {
          setState(() => mode = v.first);
          if (mode == 0 && !started) _startQr();
        },
      ),
      const SizedBox(height: 18),
      if (needCode) _codeBox(s) else if (mode == 0) _qrBox(s) else _passwordBox(s),
    ]);
  }

  Widget _qrBox(S s) {
    final st = r.state;
    return Center(
      child: Column(children: [
        Container(
          width: 236,
          height: 236,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.center,
          child: r.qrUrl.isEmpty
              ? (st == RemoteState.error
                  ? const Icon(Icons.error_outline_rounded, size: 48, color: Colors.black26)
                  : const CircularProgressIndicator(strokeWidth: 2.5))
              : Padding(
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(data: r.qrUrl, version: QrVersions.auto, backgroundColor: Colors.white),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          st == RemoteState.error ? _errText(s) : s.t('qr_instructions'),
          textAlign: TextAlign.center,
          style: TextStyle(color: st == RemoteState.error ? C.red : C.text2, fontSize: 13, height: 1.5),
        ),
        if (st == RemoteState.error)
          TextButton(
            onPressed: () {
              started = false;
              _startQr();
            },
            child: Text(s.t('try_again')),
          ),
      ]),
    );
  }

  Widget _passwordBox(S s) {
    final st = r.state;
    final busy = st == RemoteState.connecting;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.t('password_note'), style: const TextStyle(color: C.text3, fontSize: 12, height: 1.45)),
      const SizedBox(height: 12),
      TextField(controller: user, decoration: InputDecoration(labelText: s.t('username'))),
      const SizedBox(height: 10),
      TextField(
        controller: pass,
        obscureText: true,
        decoration: InputDecoration(labelText: s.t('password')),
        onSubmitted: (_) => _signIn(),
      ),
      if (st == RemoteState.badPassword || st == RemoteState.rateLimited || st == RemoteState.error)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_errText(s), style: const TextStyle(color: C.red, fontSize: 13)),
        ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : _signIn,
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s.t('sign_in')),
        ),
      ),
    ]);
  }

  void _signIn() {
    if (user.text.trim().isEmpty || pass.text.isEmpty) return;
    r.loginPassword(user.text.trim(), pass.text, const []);
    pass.clear();
  }

  Widget _codeBox(S s) {
    final st = r.state;
    final email = st == RemoteState.needEmail;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(email ? s.t('guard_email') : s.t('guard_2fa'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      const SizedBox(height: 4),
      Text(s.t('guard_msg'), style: const TextStyle(color: C.text2, fontSize: 13, height: 1.45)),
      const SizedBox(height: 14),
      TextField(
        controller: code,
        autofocus: true,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: mono(24, w: FontWeight.w600),
        decoration: const InputDecoration(hintText: '•••••'),
        onSubmitted: (_) => _sendCode(),
      ),
      if (st == RemoteState.wrongCode)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('wrong_code'), style: const TextStyle(color: C.red, fontSize: 13))),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: _sendCode, child: Text(s.t('verify')))),
    ]);
  }

  void _sendCode() {
    final v = code.text.trim();
    if (v.isEmpty) return;
    r.submitGuard(v);
    code.clear();
  }

  String _errText(S s) => switch (r.state) {
        RemoteState.badPassword => s.t('st_bad_password'),
        RemoteState.rateLimited => s.t('st_rate_limited'),
        _ => '${s.t('st_error')}: ${r.message}',
      };
}

extension _Last<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}

// ═══ Ayarlar ═════════════════════════════════════════════════════════════════

/// Eski çağrı noktaları için: ayarlar artık bir sayfa.
void showSettings(BuildContext context, AppState app) => app.setSection(Section.settings);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app});
  final AppState app;
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  late final TextEditingController key = TextEditingController(text: widget.app.apiKey);
  bool installing = false;
  final installLog = <String>[];

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    if (app.python == null) app.probeEngine();
    app.addListener(_r);
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.removeListener(_r);
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = app.s;
    final st = app.settings;
    Widget sw(String t, String d, bool v, ValueChanged<bool> on) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(d, style: const TextStyle(color: C.text3, fontSize: 12, height: 1.4)),
              ]),
            ),
            Switch(value: v, onChanged: on),
          ]),
        );
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t.toUpperCase(), style: const TextStyle(color: C.text3, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        );

    final py = app.python;
    return Column(children: [
        PageHeader(title: s.t('settings'), subtitle: s.t('page_settings_sub')),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Panel(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                section(s.t('general')),
                Row(children: [
                  Expanded(child: Text(s.t('language'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: 'tr', label: Text('Türkçe')), ButtonSegment(value: 'en', label: Text('English'))],
                    selected: {st.lang},
                    onSelectionChanged: (v) => app.setLang(v.first),
                  ),
                ]),
                sw(s.t('set_tray'), s.t('set_tray_d'), st.closeToTray, (v) {
                  st.closeToTray = v;
                  app.saveSettings();
                }),
                sw(s.t('set_login'), s.t('set_login_d'), st.launchAtLogin, (v) async {
                  st.launchAtLogin = v;
                  await setLaunchAtLoginReg(v);
                  await app.saveSettings();
                }),
                sw(s.t('set_min'), s.t('set_min_d'), st.startMinimized, (v) {
                  st.startMinimized = v;
                  app.saveSettings();
                }),

                section(s.t('api_key')),
                Text(s.t('api_key_hint'), style: const TextStyle(color: C.text2, fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: key, obscureText: true, decoration: const InputDecoration(hintText: 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'))),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () async {
                      await app.setApiKey(key.text);
                      if (context.mounted) toast(context, s.t('saved'));
                    },
                    child: Text(s.t('save')),
                  ),
                ]),
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.https('steamcommunity.com', '/dev/apikey'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(s.t('get_api_key')),
                ),

                section(s.t('engine')),
                Text(s.t('engine_desc'), style: const TextStyle(color: C.text2, fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 10),
                _engineRow(s, py),
                if (installLog.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    height: 110,
                    width: double.infinity,
                    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
                    child: SingleChildScrollView(reverse: true, child: Text(installLog.takeLast(40).join('\n'), style: mono(11, color: C.text2))),
                  ),

                section(s.t('data')),
                Row(children: [
                  Expanded(child: Text(app.store.path, style: mono(11.5, color: C.text2))),
                  OutlinedButton(
                    onPressed: () => Platform.isWindows ? Process.run('explorer', [app.store.path]) : null,
                    child: Text(s.t('open')),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(s.t('secrets_note'), style: const TextStyle(color: C.text3, fontSize: 12, height: 1.45)),
                const SizedBox(height: 14),
                Text(s.t('disclaimer'), style: const TextStyle(color: C.text3, fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 8),
              ]),
              ),
              ),
              ),
            ),
          ),
        ),
      ]);
  }

  Widget _engineRow(S s, PythonInfo? py) {
    if (app.probing || py == null) {
      return const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))]);
    }
    final ok = py.found && py.depsOk;
    return Row(children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ok ? C.green : C.amber, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          !py.found ? s.t('engine_python_missing') : (py.depsOk ? '${s.t('engine_ready')} · Python ${py.version}' : s.t('engine_deps_missing')),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (py.found && !py.depsOk)
        FilledButton(
          onPressed: installing
              ? null
              : () async {
                  setState(() {
                    installing = true;
                    installLog.clear();
                  });
                  await installEngineDeps(py, (l) {
                    if (mounted) setState(() => installLog.add(l));
                  });
                  await app.probeEngine();
                  if (mounted) setState(() => installing = false);
                },
          child: Text(installing ? s.t('installing') : s.t('install_deps')),
        ),
      TextButton(onPressed: app.probeEngine, child: Text(s.t('recheck'))),
    ]);
  }
}
