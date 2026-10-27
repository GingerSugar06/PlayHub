/// Windows ile birlikte başlatma (HKCU\...\Run). Yönetici izni gerekmez.
library;

import 'dart:io';

const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _valueName = 'PlayHub';

Future<void> setLaunchAtLoginReg(bool enable) async {
  if (!Platform.isWindows) return;
  if (enable) {
    await Process.run('reg', [
      'add', _runKey, '/v', _valueName, '/t', 'REG_SZ',
      '/d', '"${Platform.resolvedExecutable}" --minimized', '/f',
    ]);
  } else {
    await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
  }
}

Future<bool> isLaunchAtLogin() async {
  if (!Platform.isWindows) return false;
  final r = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
  return r.exitCode == 0;
}
