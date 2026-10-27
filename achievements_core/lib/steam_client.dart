/// **Steam istemcisine bağlanmak** — başarım okuma/yazma.
///
/// ## Neden `steam_api64.dll` DEĞİL
///
/// Oyunların yanında gelen `steam_api64.dll` tek bir uygulamaya bağlanmak
/// için: `SteamAPI_Init` çağıran süreç, o oyunu **oynuyor** sayılıyor ve
/// başka bir uygulamanın başarımlarına dokunamıyor.
///
/// Steam istemcisinin kendi kitaplığı (`steamclient.dll`) ise düşük seviyeli
/// arayüzü açıyor: bir boru (pipe) kur, kullanıcıya bağlan, İSTEDİĞİN
/// uygulama için `ISteamUserStats` iste. SAM de tam olarak bunu yapıyor.
///
/// ## Nasıl bağlanılıyor
///
/// 1. `SteamAppId` ortam değişkeni hedef oyuna kuruluyor — istemci hangi
///    uygulamanın istatistiklerini vereceğini buradan anlıyor.
/// 2. `steamclient.dll` Steam'in kurulum klasöründen yükleniyor.
/// 3. `CreateInterface("SteamClient018")` bir **C++ nesnesi** döndürüyor.
/// 4. `CreateSteamPipe` → `ConnectToGlobalUser` → `GetISteamUserStats`.
///
/// ## C++ nesnesini Dart'tan çağırmak
///
/// Dönen adres, ilk sözcüğü **vtable işaretçisi** olan bir nesne. Yöntemler o
/// tablodaki sıralarıyla duruyor; adları ikilide yok. Yani her yöntem
/// "tablonun N. girdisi" olarak çağrılıyor ve N'ler `ISteamUserStats013`
/// arayüzünün bildirim sırasından geliyor.
///
/// Windows x64'te C++ üye çağrısı, ilk argümanı `this` olan sıradan bir C
/// çağrısıyla aynı; ek bir hile gerekmiyor.
///
/// **Sıralar sürüme bağlı.** Arayüz sürümü değişirse (`013` → `014`) sıralar
/// kayar ve yanlış yöntem çağrılır. Bu yüzden sürüm dizgileri tek yerde
/// sabit ve `steam_client_test.dart` sırayı tutuyor.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'steam_paths.dart';

// ── Arayüz sürümleri ───────────────────────────────────────────────────────
const String kSteamClientVersion = 'SteamClient018';
const String kUserStatsVersion = 'STEAMUSERSTATS_INTERFACE_VERSION013';
const String kUtilsVersion = 'SteamUtils005';
const String kAppsVersion = 'STEAMAPPS_INTERFACE_VERSION008';
const String kApps001Version = 'STEAMAPPS_INTERFACE_VERSION001';
const String kUserVersion = 'SteamUser012';

// ── vtable sıraları (0 tabanlı) ────────────────────────────────────────────
//
// ISteamClient018
const int _cCreateSteamPipe = 0;
const int _cReleaseSteamPipe = 1;
const int _cConnectToGlobalUser = 2;
const int _cReleaseUser = 4;
const int _cGetISteamUser = 5;
const int _cGetISteamUtils = 9;
const int _cGetISteamUserStats = 13;
const int _cGetISteamApps = 15;

// ISteamUserStats013
const int _sGetAchievement = 5;
const int _sSetAchievement = 6;
const int _sClearAchievement = 7;
const int _sStoreStats = 9;
const int _sRequestUserStats = 15;

// ISteamUtils005
const int _uGetAppId = 9;

// ISteamApps008
const int _aIsSubscribedApp = 6;

// ISteamApps001 — tek yöntemi var.
const int _a1GetAppData = 0;

// ISteamUser012
const int _uGetSteamId = 2;

// ── Yerli imzalar ──────────────────────────────────────────────────────────
typedef _CreateInterfaceNative = Pointer<Void> Function(
    Pointer<Utf8> version, Pointer<Void> returnCode);
typedef _CreateInterfaceDart = Pointer<Void> Function(
    Pointer<Utf8> version, Pointer<Void> returnCode);

typedef _IntFromPtrNative = Int32 Function(Pointer<Void> self);
typedef _IntFromPtrDart = int Function(Pointer<Void> self);

typedef _PipeFromIntNative = Int32 Function(Pointer<Void> self, Int32 pipe);
typedef _PipeFromIntDart = int Function(Pointer<Void> self, int pipe);

typedef _ReleaseUserNative = Void Function(
    Pointer<Void> self, Int32 pipe, Int32 user);
typedef _ReleaseUserDart = void Function(
    Pointer<Void> self, int pipe, int user);

typedef _GetIfaceNative = Pointer<Void> Function(
    Pointer<Void> self, Int32 user, Int32 pipe, Pointer<Utf8> version);
typedef _GetIfaceDart = Pointer<Void> Function(
    Pointer<Void> self, int user, int pipe, Pointer<Utf8> version);

typedef _GetUtilsNative = Pointer<Void> Function(
    Pointer<Void> self, Int32 pipe, Pointer<Utf8> version);
typedef _GetUtilsDart = Pointer<Void> Function(
    Pointer<Void> self, int pipe, Pointer<Utf8> version);

typedef _GetAchNative = Bool Function(
    Pointer<Void> self, Pointer<Utf8> name, Pointer<Bool> achieved);
typedef _GetAchDart = bool Function(
    Pointer<Void> self, Pointer<Utf8> name, Pointer<Bool> achieved);

typedef _NameBoolNative = Bool Function(Pointer<Void> self, Pointer<Utf8> name);
typedef _NameBoolDart = bool Function(Pointer<Void> self, Pointer<Utf8> name);

typedef _BoolFromPtrNative = Bool Function(Pointer<Void> self);
typedef _BoolFromPtrDart = bool Function(Pointer<Void> self);

typedef _U32FromPtrNative = Uint32 Function(Pointer<Void> self);
typedef _U32FromPtrDart = int Function(Pointer<Void> self);

/// `GetSteamID` bir CSteamID **nesnesi** döndürüyor, düz bir sayı değil.
///
/// 🐞 İlk hâli `Uint64 Function(Pointer<Void>)` idi ve her çağrıda başka bir
/// çöp değer veriyordu (3112930925481, 1796635674281…). Sebep çağrı
/// düzeni: MSVC, önemsiz olmayan bir sınıfı değerle döndürürken **gizli bir
/// dönüş işaretçisi** ekliyor ve x64'te o işaretçi İLK argüman oluyor;
/// `this` ikinciye kayıyor.
///
/// Sıra ölçülerek bulundu: `(gizli, this)` süreci düşürdü, `(this, gizli)`
/// beklenen SteamID64'ü verdi (76561198386527062). SAM'in x86 imzası da
/// aynı sırada — `thiscall`ta `this` ECX'te, gizli işaretçi ilk yığın
/// argümanı.
typedef _GetSteamIdNative = Void Function(
    Pointer<Void> self, Pointer<Uint64> ret);
typedef _GetSteamIdDart = void Function(
    Pointer<Void> self, Pointer<Uint64> ret);

typedef _SubscribedNative = Bool Function(Pointer<Void> self, Uint32 appId);
typedef _SubscribedDart = bool Function(Pointer<Void> self, int appId);

typedef _GetAppDataNative = Int32 Function(Pointer<Void> self, Uint32 appId,
    Pointer<Utf8> key, Pointer<Utf8> value, Int32 len);
typedef _GetAppDataDart = int Function(Pointer<Void> self, int appId,
    Pointer<Utf8> key, Pointer<Utf8> value, int len);

typedef _RequestUserStatsNative = Uint64 Function(
    Pointer<Void> self, Uint64 steamId);
typedef _RequestUserStatsDart = int Function(Pointer<Void> self, int steamId);

/// Bir C++ nesnesinin vtable'ından [index] numaralı yöntemi alır.
Pointer<NativeFunction<T>> _vfn<T extends Function>(
    Pointer<Void> object, int index) {
  final vtable = object.cast<Pointer<Void>>().value;
  return (vtable.cast<Pointer<NativeFunction<T>>>() + index).value;
}

/// Bağlantı kurulamama sebebi — arayüzde anlaşılır bir mesaj göstermek için.
enum SteamFailure {
  notWindows,
  steamNotFound,
  loadFailed,
  createInterface,
  pipe,
  user,
  appIdMismatch,
}

class SteamException implements Exception {
  const SteamException(this.reason, this.message);
  final SteamFailure reason;
  final String message;
  @override
  String toString() => message;
}

/// Steam istemcisine açılmış bir oturum. Tek bir uygulamaya bağlı.
class SteamClient {
  SteamClient._(this._lib, this._client, this._pipe, this._user, this.appId);

  // ignore: unused_field
  final DynamicLibrary _lib;
  final Pointer<Void> _client;
  final int _pipe;
  final int _user;

  /// Bu oturumun bağlı olduğu uygulama.
  final int appId;

  Pointer<Void> _userStats = nullptr;
  Pointer<Void> _apps = nullptr;
  Pointer<Void> _steamUser = nullptr;
  bool _closed = false;

  /// Hedef uygulama için oturum açar.
  ///
  /// [appId] her çağrıda ortam değişkenine yazılıyor; aynı süreçte başka bir
  /// oyuna geçmek için oturumu kapatıp yenisini açmak gerekiyor (istemci
  /// uygulama kimliğini boru kurulurken okuyor).
  static SteamClient open(int appId) {
    if (!Platform.isWindows) {
      throw const SteamException(
          SteamFailure.notWindows, 'Bu uygulama yalnız Windows’ta çalışır.');
    }
    final steam = steamInstallPath();
    if (steam == null) {
      throw const SteamException(SteamFailure.steamNotFound,
          'Steam kurulumu bulunamadı. Steam kurulu ve açık olmalı.');
    }

    // appId 0 = **üstveri kipi**: hiçbir oyuna bağlanmadan bağlanmak.
    //
    // Bu kipte `ISteamApps001.GetAppData` ile HERHANGİ bir uygulamanın adını
    // sorabiliyoruz. Kütüphane listesindeki kurulu olmayan oyunların adı
    // buradan geliyor — şemalarında `gamename` çoğu zaman yok.
    //
    // Ortam değişkeni kurulmuyor: kurulursa istemci o oyuna kilitleniyor ve
    // bir daha başkasına geçilemiyor (gerekçe `SteamClient.open` başlığı).
    if (appId != 0) {
      _setEnv('SteamAppId', '$appId');
      _setEnv('SteamGameId', '$appId');
    }
    // 🐞 `steamclient64.dll` iki komşusuna dayanıyor: `tier0_s64.dll` ve
    // `vstdlib_s64.dll`. İkisi de Steam'in KÖK klasöründe. Arama yolu oraya
    // çevrilmezse yükleme "geçerli bir Win32 uygulaması değil" gibi
    // yanıltıcı hatalarla düşüyor.
    //
    // `SetDllDirectory` TEK bir yol alıyor — noktalı virgülle liste vermek
    // (SAM'in yaptığı gibi) yolu geçersiz kılıyor ve bağımlılıklar hiç
    // bulunamıyor. İlk denemede tam olarak bu oldu.
    _setDllDirectory(steam);

    // 🐞 SAM 32 bit derlendiği için `steamclient.dll` yüklüyor. Bu uygulama
    // 64 bit; o dosya x86 ve yüklenmeye çalışıldığında Windows 193 hatası
    // veriyor ("%1 is not a valid Win32 application"). 64 bit karşılığı
    // `steamclient64.dll` ve aynı klasörde duruyor.
    //
    // İkisi de deneniyor: ileride 32 bit bir yapı alınırsa ya da Steam
    // düzeni değiştirirse uygulama sessizce ölmesin.
    DynamicLibrary? lib;
    Object? sonHata;
    for (final ad in const ['steamclient64.dll', 'steamclient.dll']) {
      try {
        lib = DynamicLibrary.open('$steam\\$ad');
        break;
      } catch (e) {
        // Sıradakini dene; sebebi sakla — yutulan hata teşhisi imkânsız
        // kılıyor.
        sonHata = e;
      }
    }
    if (lib == null) {
      throw SteamException(SteamFailure.loadFailed,
          'Steam kitaplığı yüklenemedi: $sonHata');
    }

    final createInterface = lib
        .lookupFunction<_CreateInterfaceNative, _CreateInterfaceDart>(
            'CreateInterface');

    final vPtr = kSteamClientVersion.toNativeUtf8();
    final Pointer<Void> client;
    try {
      client = createInterface(vPtr, nullptr);
    } finally {
      calloc.free(vPtr);
    }
    if (client == nullptr) {
      throw const SteamException(SteamFailure.createInterface,
          '$kSteamClientVersion oluşturulamadı. Steam sürümü uyumsuz olabilir.');
    }

    final pipe = _vfn<_IntFromPtrNative>(client, _cCreateSteamPipe)
        .asFunction<_IntFromPtrDart>()(client);
    if (pipe == 0) {
      throw const SteamException(
          SteamFailure.pipe, 'Steam borusu açılamadı. Steam açık mı?');
    }

    final user = _vfn<_PipeFromIntNative>(client, _cConnectToGlobalUser)
        .asFunction<_PipeFromIntDart>()(client, pipe);
    if (user == 0) {
      throw const SteamException(SteamFailure.user,
          'Steam kullanıcısına bağlanılamadı. Steam’de oturum açık mı?');
    }

    final c = SteamClient._(lib, client, pipe, user, appId);

    // Doğrulama: istemci gerçekten İSTEDİĞİMİZ uygulamayı mı verdi. Ortam
    // değişkeni bir sebeple okunmadıysa burada yakalanıyor — yoksa başka bir
    // oyunun başarımları değiştirilirdi.
    final utils = _vfn<_GetUtilsNative>(client, _cGetISteamUtils)
        .asFunction<_GetUtilsDart>()(client, pipe, kUtilsVersion.toNativeUtf8());
    if (appId != 0 && utils != nullptr) {
      final got = _vfn<_U32FromPtrNative>(utils, _uGetAppId)
          .asFunction<_U32FromPtrDart>()(utils);
      if (got != appId) {
        c.close();
        throw SteamException(SteamFailure.appIdMismatch,
            'Steam $got uygulamasını verdi, $appId isteniyordu.');
      }
    }
    return c;
  }

  Pointer<Void> get _stats {
    if (_userStats == nullptr) {
      final v = kUserStatsVersion.toNativeUtf8();
      try {
        _userStats = _vfn<_GetIfaceNative>(_client, _cGetISteamUserStats)
            .asFunction<_GetIfaceDart>()(_client, _user, _pipe, v);
      } finally {
        calloc.free(v);
      }
    }
    return _userStats;
  }

  Pointer<Void> get _appsIface {
    if (_apps == nullptr) {
      final v = kAppsVersion.toNativeUtf8();
      try {
        _apps = _vfn<_GetIfaceNative>(_client, _cGetISteamApps)
            .asFunction<_GetIfaceDart>()(_client, _user, _pipe, v);
      } finally {
        calloc.free(v);
      }
    }
    return _apps;
  }

  Pointer<Void> get _userIface {
    if (_steamUser == nullptr) {
      final v = kUserVersion.toNativeUtf8();
      try {
        _steamUser = _vfn<_GetIfaceNative>(_client, _cGetISteamUser)
            .asFunction<_GetIfaceDart>()(_client, _user, _pipe, v);
      } finally {
        calloc.free(v);
      }
    }
    return _steamUser;
  }

  /// Oturum açmış oyuncunun SteamID64'ü (0 = okunamadı).
  ///
  /// Gizli dönüş işaretçisiyle çağrılıyor — gerekçe `_GetSteamIdNative`.
  int get steamId64 {
    final u = _userIface;
    if (u == nullptr) return 0;
    final out = calloc<Uint64>();
    try {
      _vfn<_GetSteamIdNative>(u, _uGetSteamId)
          .asFunction<_GetSteamIdDart>()(u, out);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  Pointer<Void> _apps001 = nullptr;

  Pointer<Void> get _apps1Iface {
    if (_apps001 == nullptr) {
      final v = kApps001Version.toNativeUtf8();
      try {
        _apps001 = _vfn<_GetIfaceNative>(_client, _cGetISteamApps)
            .asFunction<_GetIfaceDart>()(_client, _user, _pipe, v);
      } finally {
        calloc.free(v);
      }
    }
    return _apps001;
  }

  /// Uygulamanın mağaza üstverisi (`name`, `logo`, `type`…).
  ///
  /// Bu, oyun listesinin ad kaynağı. Şemadaki `gamename` çoğu oyunda YOK
  /// (yalnız Valve yapımlarında var ve orada bile iç ad olabiliyor:
  /// CS2 → "ValveTestApp260"). Steam istemcisi ise her uygulamanın adını
  /// biliyor ve ağa çıkmadan veriyor.
  String appData(int id, String key) {
    final a = _apps1Iface;
    if (a == nullptr) return '';
    final k = key.toNativeUtf8();
    final buf = calloc<Uint8>(1024);
    try {
      final n = _vfn<_GetAppDataNative>(a, _a1GetAppData)
          .asFunction<_GetAppDataDart>()(a, id, k, buf.cast<Utf8>(), 1024);
      if (n <= 0) return '';
      return buf.cast<Utf8>().toDartString();
    } catch (_) {
      return '';
    } finally {
      calloc.free(k);
      calloc.free(buf);
    }
  }

  /// Bu hesap oyuna sahip mi.
  bool ownsApp(int id) {
    final a = _appsIface;
    if (a == nullptr) return false;
    return _vfn<_SubscribedNative>(a, _aIsSubscribedApp)
        .asFunction<_SubscribedDart>()(a, id);
  }

  /// İstatistikleri istemciden ister. Yanıt eşzamansız gelir; çağıran taraf
  /// kısa bir süre bekleyip [achieved] okumayı deniyor.
  void requestUserStats() {
    final s = _stats;
    if (s == nullptr) return;
    final id = steamId64;
    if (id == 0) return;
    _vfn<_RequestUserStatsNative>(s, _sRequestUserStats)
        .asFunction<_RequestUserStatsDart>()(s, id);
  }

  /// Başarım açık mı. `null` = Steam henüz bilmiyor (istatistikler gelmedi).
  bool? achieved(String apiName) {
    final s = _stats;
    if (s == nullptr) return null;
    final n = apiName.toNativeUtf8();
    final out = calloc<Bool>();
    try {
      final ok = _vfn<_GetAchNative>(s, _sGetAchievement)
          .asFunction<_GetAchDart>()(s, n, out);
      return ok ? out.value : null;
    } finally {
      calloc.free(n);
      calloc.free(out);
    }
  }

  /// Başarımı açar. Yazma diske ancak [store] ile iniyor.
  bool unlock(String apiName) => _nameCall(_sSetAchievement, apiName);

  /// Başarımı kapatır.
  bool lock(String apiName) => _nameCall(_sClearAchievement, apiName);

  bool _nameCall(int index, String apiName) {
    final s = _stats;
    if (s == nullptr) return false;
    final n = apiName.toNativeUtf8();
    try {
      return _vfn<_NameBoolNative>(s, index).asFunction<_NameBoolDart>()(s, n);
    } finally {
      calloc.free(n);
    }
  }

  /// Değişiklikleri Steam'e yazar. Bu çağrı olmadan hiçbiri kalıcı olmaz.
  bool store() {
    final s = _stats;
    if (s == nullptr) return false;
    return _vfn<_BoolFromPtrNative>(s, _sStoreStats)
        .asFunction<_BoolFromPtrDart>()(s);
  }

  /// Boruyu ve kullanıcıyı bırakır. Bırakılmazsa Steam istemcisinde açık
  /// bağlantı birikiyor.
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      if (_user != 0) {
        _vfn<_ReleaseUserNative>(_client, _cReleaseUser)
            .asFunction<_ReleaseUserDart>()(_client, _pipe, _user);
      }
      if (_pipe != 0) {
        _vfn<_PipeFromIntNative>(_client, _cReleaseSteamPipe)
            .asFunction<_PipeFromIntDart>()(_client, _pipe);
      }
    } catch (_) {
      // Kapanışta hata: süreç zaten bitiyor olabilir.
    }
  }
}

// ── Windows yardımcıları ───────────────────────────────────────────────────
//
// Dart'ta ortam değişkeni YAZMA yok (`Platform.environment` salt okunur) ve
// DLL arama yolunu değiştirmenin de karşılığı yok. İkisi de doğrudan
// Windows'tan çağrılıyor.

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(Pointer<Utf8>, Pointer<Utf8>) _setEnvW = _kernel32
    .lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('SetEnvironmentVariableA');

void _setEnv(String name, String value) {
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  try {
    _setEnvW(n, v);
  } finally {
    calloc.free(n);
    calloc.free(v);
  }
}

final int Function(Pointer<Utf8>) _setDllDir = _kernel32.lookupFunction<
    Int32 Function(Pointer<Utf8>),
    int Function(Pointer<Utf8>)>('SetDllDirectoryA');

void _setDllDirectory(String path) {
  final p = path.toNativeUtf8();
  try {
    _setDllDir(p);
  } finally {
    calloc.free(p);
  }
}
