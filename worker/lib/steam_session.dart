/// Steam istemcisine "bu uygulamayı oynuyorum" bağlantısı.
///
/// Oyunun kendi `steam_api64.dll`'i yerine Steam'in kendi `steamclient64.dll`
/// kitaplığı kullanılır (SAM / SteamAchievementManager'ın yöntemi):
///
///  1. `SteamAppId` ortam değişkeni hedef uygulamaya kurulur,
///  2. `CreateInterface("SteamClient018")` ile istemci nesnesi alınır,
///  3. `CreateSteamPipe` + `ConnectToGlobalUser` ile bir boru açılır.
///
/// Boru açık kaldığı sürece Steam bu süreci o uygulamayı oynuyor sayar. Böylece
/// oyunun kurulu olmasına ya da `steam_api64.dll` bulunmasına gerek kalmaz.
///
/// C++ nesnesi Dart'tan vtable sırasıyla çağrılır (ilk sözcük vtable işaretçisi).
/// Sıralar `ISteamClient018` arayüzüne bağlıdır; sürüm değişirse kayar.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _clientVersion = 'SteamClient018';
const _utilsVersion = 'SteamUtils005';

// ISteamClient018 vtable sıraları
const _createPipe = 0;
const _releasePipe = 1;
const _connectUser = 2;
const _releaseUser = 4;
const _getUtils = 9;
// ISteamUtils005
const _utilsGetAppId = 9;

typedef _CreateIfaceN = Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>);
typedef _CreateIfaceD = Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>);
typedef _IntPtrN = Int32 Function(Pointer<Void>);
typedef _IntPtrD = int Function(Pointer<Void>);
typedef _PipeN = Int32 Function(Pointer<Void>, Int32);
typedef _PipeD = int Function(Pointer<Void>, int);
typedef _RelUserN = Void Function(Pointer<Void>, Int32, Int32);
typedef _RelUserD = void Function(Pointer<Void>, int, int);
typedef _UtilsN = Pointer<Void> Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _UtilsD = Pointer<Void> Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _U32N = Uint32 Function(Pointer<Void>);
typedef _U32D = int Function(Pointer<Void>);

Pointer<NativeFunction<T>> _vfn<T extends Function>(Pointer<Void> obj, int i) {
  final vtable = obj.cast<Pointer<Void>>().value;
  return (vtable.cast<Pointer<NativeFunction<T>>>() + i).value;
}

enum SteamFailure { notWindows, steamNotFound, loadFailed, interface, pipe, user, appMismatch }

class SteamException implements Exception {
  const SteamException(this.reason, this.message);
  final SteamFailure reason;
  final String message;
  @override
  String toString() => message;
}

/// Açık bir Steam oturumu.
class SteamSession {
  SteamSession._(this._client, this._pipe, this._user, this.appId);
  final Pointer<Void> _client;
  final int _pipe;
  final int _user;
  final int appId;
  bool _closed = false;

  /// [appId] için oturum açar. Hata olursa [SteamException] fırlatır.
  static SteamSession open(int appId) {
    if (!Platform.isWindows) {
      throw const SteamException(SteamFailure.notWindows, 'Windows only');
    }
    final steam = SteamEnv.installPath();
    if (steam == null) {
      throw const SteamException(SteamFailure.steamNotFound, 'Steam not found');
    }
    _setEnv('SteamAppId', '$appId');
    _setEnv('SteamGameId', '$appId');
    // steamclient64.dll, tier0_s64.dll ve vstdlib_s64.dll'ye dayanır; ikisi de
    // Steam'in kök klasöründe. Arama yolu oraya çevrilmezse yükleme yanıltıcı
    // hatalarla düşer.
    _setDllDirectory(steam);

    DynamicLibrary? lib;
    Object? last;
    for (final name in const ['steamclient64.dll']) {
      try {
        lib = DynamicLibrary.open('$steam\\$name');
        break;
      } catch (e) {
        last = e;
      }
    }
    if (lib == null) {
      throw SteamException(SteamFailure.loadFailed, 'Could not load steamclient64.dll: $last');
    }

    final create = lib.lookupFunction<_CreateIfaceN, _CreateIfaceD>('CreateInterface');
    final v = _clientVersion.toNativeUtf8();
    final Pointer<Void> client;
    try {
      client = create(v, nullptr);
    } finally {
      calloc.free(v);
    }
    if (client == nullptr) {
      throw const SteamException(SteamFailure.interface, 'SteamClient interface unavailable');
    }

    final pipe = _vfn<_IntPtrN>(client, _createPipe).asFunction<_IntPtrD>()(client);
    if (pipe == 0) {
      throw const SteamException(SteamFailure.pipe, 'Could not open Steam pipe');
    }
    final user = _vfn<_PipeN>(client, _connectUser).asFunction<_PipeD>()(client, pipe);
    if (user == 0) {
      _vfn<_PipeN>(client, _releasePipe).asFunction<_PipeD>()(client, pipe);
      throw const SteamException(SteamFailure.user, 'Could not connect to the Steam user');
    }

    final s = SteamSession._(client, pipe, user, appId);

    // Doğrulama: Steam gerçekten istediğimiz uygulamayı mı verdi?
    final uv = _utilsVersion.toNativeUtf8();
    try {
      final utils = _vfn<_UtilsN>(client, _getUtils).asFunction<_UtilsD>()(client, pipe, uv);
      if (utils != nullptr) {
        final got = _vfn<_U32N>(utils, _utilsGetAppId).asFunction<_U32D>()(utils);
        if (got != appId) {
          s.close();
          throw SteamException(SteamFailure.appMismatch, 'Steam returned app $got, expected $appId');
        }
      }
    } finally {
      calloc.free(uv);
    }
    return s;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _vfn<_RelUserN>(_client, _releaseUser).asFunction<_RelUserD>()(_client, _pipe, _user);
      _vfn<_PipeN>(_client, _releasePipe).asFunction<_PipeD>()(_client, _pipe);
    } catch (_) {}
  }
}

/// Steam'in çalışma durumu (kayıt defteri üzerinden).
class SteamEnv {
  static String? installPath() {
    if (!Platform.isWindows) return null;
    for (final key in const [
      r'HKCU\Software\Valve\Steam',
      r'HKLM\Software\WOW6432Node\Valve\Steam',
      r'HKLM\Software\Valve\Steam',
    ]) {
      for (final name in const ['SteamPath', 'InstallPath']) {
        final v = _regRead(key, name);
        if (v != null) {
          final p = v.replaceAll('/', '\\');
          if (Directory(p).existsSync()) return p;
        }
      }
    }
    return null;
  }

  /// Steam açık mı (ActiveProcess\pid > 0).
  static bool running() => _regDword(r'HKCU\Software\Valve\Steam\ActiveProcess', 'pid') > 0;

  /// Steam'de bir kullanıcı oturum açmış mı.
  static bool signedIn() => _regDword(r'HKCU\Software\Valve\Steam\ActiveProcess', 'ActiveUser') > 0;

  /// Oturum açmış kullanıcının 32 bit hesap kimliği (0 = yok).
  static int activeAccountId() => _regDword(r'HKCU\Software\Valve\Steam\ActiveProcess', 'ActiveUser');

  static bool ready() => running() && signedIn();

  /// Steam'in o an "çalışan uygulama" olarak bildirdiği kimlik (0 = yok).
  static int runningAppId() => _regDword(r'HKCU\Software\Valve\Steam', 'RunningAppID');

  static String? _regRead(String key, String name) {
    try {
      final r = Process.runSync('reg', ['query', key, '/v', name]);
      if (r.exitCode != 0) return null;
      final m = RegExp(r'REG_\w+\s+(.+)').firstMatch(r.stdout.toString());
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static int _regDword(String key, String name) {
    final v = _regRead(key, name);
    if (v == null) return 0;
    if (v.startsWith('0x')) return int.tryParse(v.substring(2), radix: 16) ?? 0;
    return int.tryParse(v) ?? 0;
  }
}

// ── Windows yardımcıları ───────────────────────────────────────────────────
DynamicLibrary? _k32;
DynamicLibrary get _kernel32 => _k32 ??= DynamicLibrary.open('kernel32.dll');

void _setEnv(String name, String value) {
  final f = _kernel32.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('SetEnvironmentVariableA');
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  try {
    f(n, v);
  } finally {
    calloc.free(n);
    calloc.free(v);
  }
}

void _setDllDirectory(String path) {
  final f = _kernel32
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('SetDllDirectoryA');
  final p = path.toNativeUtf8();
  try {
    f(p);
  } finally {
    calloc.free(p);
  }
}
