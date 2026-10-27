/// TR/EN çeviri tablosu: anahtar -> [Türkçe, English].
library;

class S {
  const S(this.code);
  final String code;
  bool get tr => code == 'tr';

  /// Steam şemasındaki dil adı (başarım başlıkları için).
  String get steamLang => tr ? 'turkish' : 'english';

  String t(String key, [Map<String, String>? args]) {
    final v = _m[key];
    var out = v == null ? key : v[tr ? 0 : 1];
    args?.forEach((k, val) => out = out.replaceAll('{$k}', val));
    return out;
  }

  static const _m = <String, List<String>>{
    // genel
    'add': ['Ekle', 'Add'],
    'cancel': ['Vazgeç', 'Cancel'],
    'save': ['Kaydet', 'Save'],
    'saved': ['Kaydedildi', 'Saved'],
    'open': ['Aç', 'Open'],
    'refresh': ['Yenile', 'Refresh'],
    'more': ['Daha fazla', 'More'],
    'remove': ['Kaldır', 'Remove'],
    'rename': ['Yeniden adlandır', 'Rename'],
    'connecting': ['Bağlanıyor…', 'Connecting…'],
    'settings': ['Ayarlar', 'Settings'],
    'language': ['Dil', 'Language'],
    'data': ['Veri', 'Data'],
    'general': ['Genel', 'General'],

    // hesaplar
    'accounts': ['Hesaplar', 'Accounts'],
    'this_pc': ['Bu bilgisayar', 'This PC'],
    'this_pc_sub': ['Steam’de açık hesap', 'Account signed in to Steam'],
    'this_pc_desc': ['Bu bilgisayarda açık olan Steam hesabı. Steam çalışıyor olmalı.', 'The account signed in to the Steam client on this PC. Steam must be running.'],
    'remote_desc': ['Steam istemcisi olmadan ağ üzerinden bağlanan hesap.', 'An account connected over the network, without the Steam client.'],
    'add_account': ['Hesap ekle', 'Add account'],
    'add_account_intro': [
      'Başka bir hesabı Steam istemcisi açık olmadan kasmak için giriş yap. Şifren diske yazılmaz; oturum anahtarı Windows’un güvenli deposunda saklanır.',
      'Sign in to idle another account without the Steam client. Your password is never written to disk; the session key lives in Windows’ secure credential store.'
    ],
    'account_added': ['Hesap eklendi', 'Account added'],
    'nickname': ['Takma ad', 'Nickname'],
    'nickname_optional': ['Takma ad (isteğe bağlı)', 'Nickname (optional)'],
    'remove_title': ['Hesap kaldırılsın mı?', 'Remove this account?'],
    'remove_msg': [
      'Oturum kapatılır ve hesap listeden silinir. Kayıtlı giriş anahtarı da silinir.',
      'The session is closed and the account is removed from the list. The saved login key is deleted too.'
    ],
    'relogin': ['Yeniden giriş yap', 'Sign in again'],
    'session_expired': ['Oturum süresi dolmuş. Kasmaya devam etmek için yeniden giriş yap.', 'The session has expired. Sign in again to keep idling.'],
    'need_login': ['Önce bu hesapta oturum aç.', 'Sign in to this account first.'],
    'acc_online': ['Çevrimiçi', 'Online'],
    'acc_offline': ['Çevrimdışı', 'Offline'],
    'acc_steam_off': ['Steam kapalı', 'Steam is off'],
    'acc_connecting': ['Bağlanıyor…', 'Connecting…'],
    'acc_waiting': ['Steam bekleniyor', 'Waiting for Steam'],
    'acc_needs_login': ['Giriş gerekli', 'Sign-in needed'],
    'acc_error': ['Hata', 'Error'],
    'acc_idling': ['{n} oyun kasılıyor', '{n} idling'],

    // giriş akışı
    'with_qr': ['QR kod', 'QR code'],
    'with_password': ['Şifre', 'Password'],
    'qr_instructions': [
      'Telefonda Steam uygulamasını aç → Steam Guard → “QR ile giriş” → kodu okut. Ek kod gerekmez.',
      'Open the Steam mobile app → Steam Guard → “Sign in with QR” → scan the code. No extra code needed.'
    ],
    'try_again': ['Tekrar dene', 'Try again'],
    'username': ['Kullanıcı adı', 'Username'],
    'password': ['Şifre', 'Password'],
    'password_note': ['Şifre yalnızca girişte bir kez kullanılır ve saklanmaz.', 'The password is used once to sign in and is never stored.'],
    'sign_in': ['Giriş yap', 'Sign in'],
    'guard_2fa': ['Steam Guard kodu', 'Steam Guard code'],
    'guard_email': ['E-posta kodu', 'Email code'],
    'guard_msg': ['Mobil uygulamandaki ya da e-postana gelen kodu gir.', 'Enter the code from your mobile app or the email Steam sent.'],
    'verify': ['Doğrula', 'Verify'],
    'wrong_code': ['Kod hatalı, tekrar dene.', 'Wrong code, try again.'],
    'st_logged_on': ['Çevrimiçi', 'Online'],
    'st_connecting': ['Bağlanıyor', 'Connecting'],
    'st_disconnected': ['Bağlantı koptu, yeniden deneniyor', 'Disconnected, retrying'],
    'st_token_invalid': ['Oturum geçersiz', 'Session invalid'],
    'st_bad_password': ['Kullanıcı adı veya şifre hatalı', 'Wrong username or password'],
    'st_rate_limited': ['Çok fazla deneme — birkaç dakika bekle', 'Too many attempts — wait a few minutes'],
    'st_error': ['Hata', 'Error'],

    // Steam / durum
    'steam_not_running': ['Steam kapalı', 'Steam not running'],
    'steam_not_signed': ['Steam’de oturum açık değil', 'Not signed in to Steam'],
    'steam_ready': ['Steam hazır', 'Steam ready'],
    'steam_missing': ['Steam kurulumu bulunamadı.', 'Steam installation not found.'],
    'queued_waiting_steam': [
      'Seçtiğin oyunlar sırada. Steam açılıp oturum açılınca kendiliğinden başlar.',
      'Your games are queued. They start automatically once Steam is running and signed in.'
    ],
    'queued_not_connected': ['Oyunlar sırada; hesap bağlanınca başlayacak.', 'Games are queued and will start once the account connects.'],
    'worker_missing': [
      'idle_worker.exe bulunamadı. Uygulamayı “tool\\build.ps1” ile derle ya da paketin tam çıkarıldığından emin ol.',
      'idle_worker.exe is missing. Build with “tool\\build.ps1” or make sure the package was fully extracted.'
    ],

    // motor
    'engine': ['Ağ motoru (Python)', 'Network engine (Python)'],
    'engine_desc': [
      'Başka hesapları Steam istemcisi olmadan kasmak için küçük bir Python motoru kullanılır. “Bu bilgisayar” modu Python gerektirmez.',
      'Idling other accounts without the Steam client uses a small Python engine. The “This PC” mode does not need Python.'
    ],
    'engine_ready': ['Motor hazır', 'Engine ready'],
    'engine_setup': ['Motoru kur', 'Set up engine'],
    'engine_python_missing': ['Python 3 bulunamadı. Başka hesaplar için kurman gerekir.', 'Python 3 was not found. It is required for other accounts.'],
    'engine_deps_missing': ['Motorun gerektirdiği paketler eksik.', 'The packages the engine needs are missing.'],
    'download_python': ['Python indir', 'Download Python'],
    'install_deps': ['Paketleri kur', 'Install packages'],
    'installing': ['Kuruluyor…', 'Installing…'],
    'recheck': ['Yeniden denetle', 'Re-check'],

    // kütüphane
    'search_hint': ['Oyun adı ya da AppID ara…', 'Search by game name or AppID…'],
    'tab_installed': ['Kurulu', 'Installed'],
    'tab_library': ['Kütüphane', 'Library'],
    'tab_favorites': ['Favoriler', 'Favorites'],
    'tab_idling': ['Kasılanlar', 'Idling'],
    'games_only': ['Yalnız oyunlar', 'Games only'],
    'installed': ['kurulu', 'installed'],
    'custom': ['özel', 'custom'],
    'idle': ['Kas', 'Idle'],
    'stop': ['Durdur', 'Stop'],
    'waiting': ['Bekliyor', 'Waiting'],
    'retrying': ['Deniyor', 'Retrying'],
    'fav_add': ['Favorilere ekle', 'Add to favorites'],
    'fav_remove': ['Favorilerden çıkar', 'Remove from favorites'],
    'remove_custom': ['Özel oyunu sil', 'Remove custom game'],
    'limit_reached': ['Steam aynı anda en fazla {n} oyunu destekler.', 'Steam supports at most {n} games at once.'],
    'total_idling': ['{a} hesap · {g} oyun kasılıyor', '{a} accounts · {g} games idling'],
    'nothing_idling': ['Şu an hiçbir şey kasılmıyor', 'Nothing is idling right now'],
    'stop_here': ['Bu hesabı durdur', 'Stop this account'],
    'stop_everything': ['Hepsini durdur', 'Stop everything'],
    'empty_fav': ['Henüz favori yok', 'No favorites yet'],
    'empty_fav_msg': ['Bir oyunun kalbine dokun; sık kullandıkların burada toplanır.', 'Tap the heart on a game; your regulars are collected here.'],
    'empty_idling': ['Kasılan oyun yok', 'No games idling'],
    'empty_idling_msg': ['Bir oyunun yanındaki “Kas” düğmesine bas.', 'Press the “Idle” button next to a game.'],
    'empty_search': ['Eşleşen oyun yok', 'No matching games'],
    'empty_search_msg': ['Başka bir ad ya da AppID dene; “Yalnız oyunlar” filtresini kapatmak da yardımcı olabilir.', 'Try another name or AppID; turning off “Games only” may help.'],
    'empty_pc': ['Oyun bulunamadı', 'No games found'],
    'empty_pc_msg': ['Steam kurulu ve en az bir oyun yüklü olmalı. Tüm kütüphaneni görmek için Web API anahtarı ekleyebilirsin.', 'Steam must be installed with at least one game. Add a Web API key to see your whole library.'],
    'api_key_hint_short': ['Ayarlar → Web API anahtarı', 'Settings → Web API key'],
    'empty_remote': ['Kütüphane yüklenmedi', 'Library not loaded'],
    'empty_remote_msg': ['Hesap bağlanınca oyunların burada listelenir. Bu arada AppID ile oyun ekleyebilirsin.', 'Your games are listed here once the account connects. Meanwhile you can add a game by AppID.'],
    'loading_library': ['Kütüphane yükleniyor…', 'Loading library…'],
    'loading_library_msg': ['Hesabındaki oyunlar Steam’den alınıyor. Birkaç saniye sürebilir.', 'Fetching the games on your account from Steam. This can take a few seconds.'],

    // AppID
    'add_appid': ['AppID ile oyun ekle', 'Add a game by AppID'],
    'add_appid_tip': ['Listede olmayan bir oyunu AppID ile ekle', 'Add a game that is not listed, by AppID'],
    'add_appid_msg': [
      'Oyunun AppID’si mağaza sayfasının adresindeki sayıdır (store.steampowered.com/app/730 → 730).',
      'A game’s AppID is the number in its store URL (store.steampowered.com/app/730 → 730).'
    ],
    'name_optional': ['Ad (isteğe bağlı)', 'Name (optional)'],
    'err_appid': ['Geçerli bir AppID yaz.', 'Enter a valid AppID.'],

    // ayarlar
    'set_tray': ['Kapatınca tepside çalışmaya devam et', 'Keep running in the tray when closed'],
    'set_tray_d': ['X’e basınca kasma durmaz; uygulama tepsiye iner.', 'The X button hides to the tray; idling continues.'],
    'set_login': ['Windows ile birlikte başlat', 'Launch with Windows'],
    'set_login_d': ['Kasılan oyunlar bilgisayar açılınca kendiliğinden sürdürülür.', 'Idling games resume by themselves when your PC starts.'],
    'set_min': ['Küçültülmüş başlat', 'Start minimized'],
    'set_min_d': ['Pencere açılmadan doğrudan tepsiye gider.', 'Goes straight to the tray without opening the window.'],
    'api_key': ['Steam Web API anahtarı', 'Steam Web API key'],
    'api_key_hint': [
      'İsteğe bağlı. “Bu bilgisayar” için kurulu olmayanlar dahil tüm kütüphaneni ve oynama sürelerini gösterir. Anahtar Windows’un güvenli deposunda saklanır.',
      'Optional. Shows your whole library, including uninstalled games, and playtimes for “This PC”. The key is kept in Windows’ secure credential store.'
    ],
    'get_api_key': ['Ücretsiz anahtar al', 'Get a free key'],
    'secrets_note': [
      'Hesap listesi ve favoriler yukarıdaki klasörde düz JSON olarak durur; oturum anahtarları ve API anahtarı orada DEĞİL, Windows Kimlik Bilgisi Yöneticisi’ndedir.',
      'The account list and favorites sit in the folder above as plain JSON; session keys and the API key are NOT there — they are in Windows Credential Manager.'
    ],
    'disclaimer': [
      'Resmî değildir; Valve ile bağlantısı yoktur. Kasma, Steam hizmet koşullarına ya da bazı oyunların kurallarına aykırı olabilir; sorumluluk sana aittir.',
      'Unofficial; not affiliated with Valve. Idling may violate Steam’s terms or some games’ rules; use at your own risk.'
    ],

    // gezinme
    'nav_boost': ['Saat kasma', 'Boost hours'],
    'nav_ach': ['Başarımlar', 'Achievements'],
    'nav_stats': ['İstatistikler', 'Statistics'],
    'page_boost_sub': ['Oyunlarını seç, Kas’a bas; pencereyi kapatsan da tepside sürer.', 'Pick games and press Idle; it keeps running in the tray.'],
    'page_ach_sub': ['Seçtiğin oyunun başarımlarını aç ya da kilitle.', 'Unlock or lock achievements for a game.'],
    'page_stats_sub': ['Ne kadar süre kastığını gör.', 'See how long you have boosted.'],
    'page_settings_sub': ['Dil, tepsi davranışı, Web API anahtarı ve ağ motoru.', 'Language, tray behaviour, Web API key and network engine.'],

    // istatistikler
    'stat_today': ['Bugün', 'Today'],
    'stat_total': ['Toplam', 'All time'],
    'stat_running': ['Şu an kasılan', 'Idling now'],
    'stat_last7': ['Son 7 gün', 'Last 7 days'],
    'stat_top': ['En çok kasılan oyunlar', 'Most boosted games'],
    'stat_none': ['Henüz kayıt yok', 'No data yet'],
    'stat_none_msg': ['Bir oyunu kasmaya başlayınca süreler burada birikir.', 'Boosted time collects here once you start a game.'],
    'stat_games': ['oyun', 'games'],

    // başarımlar
    'games_count': ['{n} oyun', '{n} games'],
    'search_games': ['Oyun ara…  (Ctrl+F)', 'Search games…  (Ctrl+F)'],
    'only_installed': ['Yalnız kurulu', 'Installed only'],
    'ach_steam_missing': ['Steam bulunamadı', 'Steam not found'],
    'ach_steam_missing_msg': [
      'Steam kurulu değil ya da kayıt defterinde görünmüyor. Steam’i kur, bir kez aç ve yenile.',
      'Steam is not installed or not in the registry. Install Steam, open it once and refresh.'
    ],
    'no_match': ['Eşleşme yok', 'No matches'],
    'no_match_msg': ['Farklı bir ad ya da uygulama kimliği dene.', 'Try a different name or AppID.'],
    'no_games': ['Başarımlı oyun bulunamadı', 'No games with achievements found'],
    'no_games_msg': [
      'Steam, başarımı olan oyunların şemasını bir kez açıldıktan sonra diske yazar. Oyunlarını Steam’de bir kere başlat ve yenile.',
      'Steam writes the achievement schema to disk after a game has been opened once. Launch your games in Steam once, then refresh.'
    ],
    'pick_game': ['Bir oyun seç', 'Pick a game'],
    'pick_game_msg': [
      'Soldaki listeden bir oyuna tıkla; başarımları burada açılır. Değişiklikler “Uygula” diyene kadar Steam’e yazılmaz.',
      'Click a game on the left to see its achievements here. Nothing is written to Steam until you press “Apply”.'
    ],
    'step1': ['Oyunu seç', 'Choose a game'],
    'step1_d': ['Kurulu olmayanlar da listelenir.', 'Uninstalled games are listed too.'],
    'step2': ['Başarımları işaretle', 'Mark achievements'],
    'step2_d': ['Tıklamak değişikliği biriktirir.', 'Clicking queues a change.'],
    'step3': ['Uygula', 'Apply'],
    'step3_d': ['Hepsi tek seferde Steam’e yazılır.', 'Everything is written to Steam at once.'],
    'failed_open': ['Açılamadı', 'Could not open'],
    'unknown_error': ['Bilinmeyen hata.', 'Unknown error.'],
    'search_ach': ['Başarım ara…', 'Search achievements…'],
    'only_locked': ['Yalnız kilitli', 'Locked only'],
    'hidden': ['Gizliler', 'Hidden'],
    'unlock_visible': ['Görünenleri aç', 'Unlock visible'],
    'lock_visible': ['Görünenleri kilitle', 'Lock visible'],
    'invert_visible': ['Görünenleri tersine çevir', 'Invert visible'],
    'no_filter_match': ['Süzgece uyan başarım yok', 'No achievements match'],
    'no_filter_match_msg': ['Süzgeçleri gevşetmeyi dene.', 'Try loosening the filters.'],
    'unlocked_of': ['{a} / {b} açık', '{a} / {b} unlocked'],
    'will_unlock': ['açılacak', 'will unlock'],
    'will_lock': ['kilitlenecek', 'will lock'],
    'hidden_badge': ['Gizli başarım', 'Hidden achievement'],
    'changes_pending': ['{n} değişiklik bekliyor', '{n} changes pending'],
    'undo': ['Geri al', 'Undo'],
    'apply': ['Uygula', 'Apply'],
    'applied': ['{n} değişiklik yazıldı', '{n} changes written'],
    'applied_failed': [' · {n} başarısız', ' · {n} failed'],
    'store_refused': [
      'Steam yazmayı reddetti. Oyun açıksa kapatıp yeniden dene.',
      'Steam refused the write. If the game is running, close it and try again.'
    ],
    'ach_worker_missing': [
      'achievements_worker.exe bulunamadı. Uygulamayı “tool\\build.ps1” ile derle ya da paketi eksiksiz çıkar.',
      'achievements_worker.exe not found. Build with “tool\\build.ps1” or extract the full package.'
    ],
    'steam_no_response': ['Steam yanıt vermedi. Steam açık ve oturum açık mı?', 'Steam did not respond. Is Steam running and signed in?'],
    'worker_died': ['Yardımcı süreç beklenmedik şekilde kapandı.', 'The helper process closed unexpectedly.'],
    'intro_title': ['Başlamadan önce', 'Before you start'],
    'intro_body': [
      'Başarımları elle değiştirmek Steam profilinde kalıcı iz bırakır ve bazı oyunların topluluk sıralamalarında fark edilebilir. Yalnızca kendi hesabında, ne yaptığını bilerek kullan.\n\nSteam açık ve oturum açılmış olmalı. Oyun açıkken yazma reddedilebilir.',
      'Changing achievements by hand leaves a permanent trace on your Steam profile and some games’ community rankings may notice it. Use it only on your own account and know what you are doing.\n\nSteam must be running and signed in. Writes can be refused while the game is open.'
    ],
    'intro_ok': ['Anladım', 'I understand'],
    'err_steamNotFound': ['Steam kurulumu bulunamadı. Steam kurulu ve açık olmalı.', 'Steam installation not found. Steam must be installed and running.'],
    'err_loadFailed': ['Steam kitaplığı yüklenemedi.', 'Could not load the Steam library.'],
    'err_createInterface': ['Steam arayüzü oluşturulamadı; Steam sürümü uyumsuz olabilir.', 'Could not create the Steam interface; your Steam version may be incompatible.'],
    'err_pipe': ['Steam borusu açılamadı. Steam açık mı?', 'Could not open the Steam pipe. Is Steam running?'],
    'err_user': ['Steam kullanıcısına bağlanılamadı. Steam’de oturum açık mı?', 'Could not connect to the Steam user. Are you signed in to Steam?'],
    'err_appIdMismatch': ['Steam başka bir uygulamayı verdi. Uygulamayı yeniden başlatıp tekrar dene.', 'Steam returned a different app. Restart the app and try again.'],
    'err_schemaMissing': ['Bu oyunun başarım şeması Steam önbelleğinde yok. Oyunu Steam’de bir kez başlatmak şemayı indirtir.', 'This game’s achievement schema is not in the Steam cache. Launching the game once in Steam downloads it.'],
    'err_usage': ['Geçersiz oyun kimliği.', 'Invalid game id.'],

    // tepsi
    'tray_show': ['Pencereyi göster', 'Show window'],
    'tray_stop_all': ['Hepsini durdur', 'Stop everything'],
    'tray_quit': ['Çıkış', 'Quit'],
    'tray_idling': ['{n} oyun kasılıyor', '{n} games idling'],
  };
}
