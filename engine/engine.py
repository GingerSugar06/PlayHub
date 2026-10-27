#!/usr/bin/env python3
"""Play Hub - ağ motoru (başka hesaplar için).

Steam istemcisi açık olmadan, Steam ağına (CM) doğrudan bağlanıp bir hesabı
"şu oyunları oynuyor" konumuna getirir. Her hesap için bir süreç çalışır;
Flutter arayüzü bu sürece stdin/stdout üzerinden satır satır JSON ile konuşur.

KOMUTLAR (stdin, her satır bir JSON):
  {"cmd":"login_password","username":"…","password":"…"}
  {"cmd":"login_qr"}
  {"cmd":"login_token","account_name":"…","refresh_token":"…"}
  {"cmd":"guard","code":"ABC12"}          Steam Guard kodu (2FA ya da e-posta)
  {"cmd":"set_games","appids":[730,440]}  oynanan oyunları canlı güncelle
  {"cmd":"quit"}

OLAYLAR (stdout, her satır bir JSON):
  {"event":"state","state":"connecting|qr|need_2fa|need_email|need_confirm|
                    wrong_code|logged_on|disconnected|bad_password|
                    rate_limited|token_invalid|error","message":"…"}
  {"event":"qr","url":"…"}
  {"event":"identity","account_name":"…","steam64":"…","persona":"…"}
  {"event":"token","refresh_token":"…"}        (arayüz güvenli depoya yazar)
  {"event":"owned","games":[{"appid":1,"name":"…"}]}

Şifre ASLA diske yazılmaz; yalnızca bellekte tutulur ve girişten sonra silinir.
Günlük dosyası (--log) gizli veri içermez.

Gereksinimler: Python 3.9+, `pip install -r engine/requirements.txt`
"""

import os

os.environ.setdefault("PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION", "python")

import argparse
import json
import logging
import queue
import random
import sys
import threading
import time
from base64 import b64encode

log = logging.getLogger("engine")


# ── çıktı ────────────────────────────────────────────────────────────────────
_out_lock = threading.Lock()


def emit(event, **kw):
    kw["event"] = event
    line = json.dumps(kw, ensure_ascii=False)
    with _out_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def set_state(state, message=""):
    emit("state", state=state, message=message)


# ── bağımlılık denetimi ──────────────────────────────────────────────────────
def check():
    info = {"ok": False, "python": sys.version.split()[0]}
    try:
        import gevent  # noqa: F401
        import steam
        import google.protobuf as pb
        import requests  # noqa: F401
        from Cryptodome.PublicKey import RSA  # noqa: F401
        from steam.protobufs import steammessages_auth_pb2  # noqa: F401

        info.update(ok=True, steam=steam.__version__, protobuf=pb.__version__)
    except Exception as e:  # pragma: no cover
        info["error"] = f"{type(e).__name__}: {e}"
    print(json.dumps(info))


# ── motor ────────────────────────────────────────────────────────────────────
class Engine:
    PLATFORM_STEAMCLIENT = 1
    API = "https://api.steampowered.com/IAuthenticationService"

    def __init__(self, creds_dir):
        import gevent
        from steam.client import SteamClient
        from steam.enums import EResult

        self.gevent = gevent
        self.EResult = EResult
        self.client = SteamClient()
        if creds_dir:
            try:
                os.makedirs(creds_dir, exist_ok=True)
                self.client.set_credential_location(creds_dir)
            except Exception:
                pass

        self.cmds: "queue.Queue" = queue.Queue()
        self.appids: set = set()
        self.login_id = random.randint(1, 0xFFFFFFFE)
        self.account_name = ""
        self.refresh_token = ""
        self.want_quit = False
        self.guard_code = None
        self.guard_event = gevent.event.Event()
        self.login_greenlet = None
        self.logged_in = False

        @self.client.on(SteamClient.EVENT_LOGGED_ON)
        def _on_logged_on():
            self._send_games()

    # ── stdin okuyucu (ayrı iş parçacığı) ────────────────────────────────────
    def start_reader(self):
        def run():
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                try:
                    self.cmds.put(json.loads(line))
                except Exception:
                    log.warning("geçersiz komut satırı")
            self.cmds.put({"cmd": "quit"})  # stdin kapandı: arayüz öldü

        threading.Thread(target=run, daemon=True).start()

    # ── ağ yardımcıları ──────────────────────────────────────────────────────
    def _ensure_connected(self, timeout=20):
        c = self.client
        if not c.connected and not c._connecting:
            if not c.connect():
                return False
        if not c.channel_secured:
            c.wait_event(c.EVENT_CHANNEL_SECURED, timeout=timeout)
        return c.channel_secured

    def _cm_logon_with_token(self, account_name, token):
        from steam.core.msg import MsgProto
        from steam.enums import EOSType
        from steam.enums.emsg import EMsg
        from steam.steamid import SteamID

        c = self.client
        if not self._ensure_connected():
            return self.EResult.TryAnotherCM
        c.username = account_name
        m = MsgProto(EMsg.ClientLogon)
        m.header.steamid = SteamID(type="Individual", universe="Public")
        m.body.protocol_version = 65580
        m.body.client_package_version = 1561159470
        m.body.client_os_type = EOSType.Windows10
        m.body.client_language = "english"
        m.body.should_remember_password = True
        m.body.supports_rate_limit_response = True
        m.body.chat_mode = c.chat_mode
        m.body.obfuscated_private_ip.v4 = self.login_id
        m.body.account_name = account_name
        m.body.access_token = token
        c.send(m)
        resp = c.wait_msg(EMsg.ClientLogOnResponse, timeout=30)
        return self.EResult(resp.body.eresult) if resp else self.EResult.Fail

    # ── yeni kimlik doğrulama (IAuthenticationService) ───────────────────────
    def _auth_call(self, method, msg, get=False):
        import requests

        if not hasattr(self, "_http"):
            self._http = requests.Session()
            self._http.headers.update({"User-Agent": "Mozilla/5.0 (PlayHub)"})
        data = {"input_protobuf_encoded": b64encode(msg.SerializeToString()).decode()}
        url = f"{self.API}/{method}/v1/"
        if get:
            return self._http.get(url, params=data, timeout=20)
        return self._http.post(url, data=data, timeout=20)

    @staticmethod
    def _eresult(resp):
        try:
            return int(resp.headers.get("x-eresult", "1"))
        except ValueError:
            return 1

    def _poll_until_token(self, client_id, request_id, interval):
        """Onay gelene kadar yokla; (refresh_token, account_name) döndürür."""
        from steam.protobufs.steammessages_auth_pb2 import (
            CAuthentication_PollAuthSessionStatus_Request as PollReq,
            CAuthentication_PollAuthSessionStatus_Response as PollResp,
        )

        deadline = time.time() + 300
        while not self.want_quit and time.time() < deadline:
            self.gevent.sleep(max(interval, 2))
            try:
                req = PollReq()
                req.client_id = client_id
                req.request_id = request_id
                r = self._auth_call("PollAuthSessionStatus", req)
                pb = PollResp()
                pb.ParseFromString(r.content)
            except Exception as e:
                log.warning("yoklama hatası: %s", e)
                continue
            if pb.new_client_id:
                client_id = pb.new_client_id
            if pb.new_challenge_url:
                emit("qr", url=pb.new_challenge_url)
            if pb.refresh_token:
                return pb.refresh_token, pb.account_name
        return None, None

    def _login_qr(self):
        from steam.protobufs.steammessages_auth_pb2 import (
            CAuthentication_BeginAuthSessionViaQR_Request as QRReq,
            CAuthentication_BeginAuthSessionViaQR_Response as QRResp,
        )

        try:
            req = QRReq()
            req.device_friendly_name = "Play Hub"
            req.platform_type = self.PLATFORM_STEAMCLIENT
            r = self._auth_call("BeginAuthSessionViaQR", req)
            qr = QRResp()
            qr.ParseFromString(r.content)
        except Exception as e:
            set_state("error", f"qr_start_failed: {e}")
            return False
        if not qr.challenge_url:
            set_state("error", "qr_empty_response")
            return False
        set_state("qr")
        emit("qr", url=qr.challenge_url)
        token, name = self._poll_until_token(qr.client_id, qr.request_id, qr.interval or 5.0)
        if not token:
            if not self.want_quit:
                set_state("error", "qr_timeout")
            return False
        return self._finish_with_token(name, token)

    def _login_password(self, username, password):
        from Cryptodome.Cipher import PKCS1_v1_5
        from Cryptodome.PublicKey import RSA
        from steam.protobufs.steammessages_auth_pb2 import (
            CAuthentication_BeginAuthSessionViaCredentials_Request as BeginReq,
            CAuthentication_BeginAuthSessionViaCredentials_Response as BeginResp,
            CAuthentication_GetPasswordRSAPublicKey_Request as RsaReq,
            CAuthentication_GetPasswordRSAPublicKey_Response as RsaResp,
            CAuthentication_UpdateAuthSessionWithSteamGuardCode_Request as GuardReq,
        )

        set_state("connecting")
        try:
            rr = RsaReq()
            rr.account_name = username
            r = self._auth_call("GetPasswordRSAPublicKey", rr, get=True)
            rsa = RsaResp()
            rsa.ParseFromString(r.content)
            if not rsa.publickey_mod:
                set_state("bad_password")
                return False
            key = RSA.construct((int(rsa.publickey_mod, 16), int(rsa.publickey_exp, 16)))
            enc = b64encode(PKCS1_v1_5.new(key).encrypt(password.encode("utf-8"))).decode()

            req = BeginReq()
            req.device_friendly_name = "Play Hub"
            req.account_name = username
            req.encrypted_password = enc
            req.encryption_timestamp = rsa.timestamp
            req.remember_login = True
            req.platform_type = self.PLATFORM_STEAMCLIENT
            req.persistence = 1  # k_ESessionPersistence_Persistent
            req.website_id = "Client"
            r = self._auth_call("BeginAuthSessionViaCredentials", req)
            er = self._eresult(r)
            if er == 5:
                set_state("bad_password")
                return False
            if er in (84, 87):
                set_state("rate_limited")
                return False
            if er != 1:
                set_state("error", f"eresult_{er}")
                return False
            begin = BeginResp()
            begin.ParseFromString(r.content)
        except Exception as e:
            log.exception("kimlik doğrulama başlatılamadı")
            set_state("error", f"{type(e).__name__}: {e}")
            return False
        finally:
            password = ""  # noqa: F841 - bellekte tutma

        types = {c.confirmation_type for c in begin.allowed_confirmations}
        # 1=None 2=E-posta kodu 3=Aygıt kodu 4=Aygıt onayı 5=E-posta onayı
        code_type = 3 if 3 in types else (2 if 2 in types else 0)
        if code_type:
            set_state("need_2fa" if code_type == 3 else "need_email")
            while not self.want_quit:
                self.guard_event.clear()
                self.guard_code = None
                if not self.guard_event.wait(timeout=300):
                    set_state("error", "guard_timeout")
                    return False
                if self.want_quit:
                    return False
                g = GuardReq()
                g.client_id = begin.client_id
                g.steamid = begin.steamid
                g.code = self.guard_code
                g.code_type = code_type
                gr = self._auth_call("UpdateAuthSessionWithSteamGuardCode", g)
                ge = self._eresult(gr)
                if ge == 1:
                    break
                set_state("wrong_code")
                self.gevent.sleep(0.3)
                set_state("need_2fa" if code_type == 3 else "need_email")
        elif 4 in types or 5 in types:
            set_state("need_confirm")
        token, name = self._poll_until_token(begin.client_id, begin.request_id, begin.interval or 5.0)
        if not token:
            if not self.want_quit:
                set_state("error", "login_timeout")
            return False
        return self._finish_with_token(name or username, token)

    def _finish_with_token(self, account_name, token):
        set_state("connecting")
        res = self._cm_logon_with_token(account_name, token)
        if res != self.EResult.OK:
            log.info("CM girişi başarısız: %s", res)
            set_state("token_invalid" if res in (
                self.EResult.AccessDenied, self.EResult.InvalidPassword,
                self.EResult.Expired, self.EResult.LoggedInElsewhere) else "error", str(res))
            return False
        self.account_name = account_name
        self.refresh_token = token
        emit("token", refresh_token=token)
        self._after_logon()
        return True

    def _login_token(self, account_name, token):
        set_state("connecting")
        res = self._cm_logon_with_token(account_name, token)
        if res != self.EResult.OK:
            log.info("token girişi başarısız: %s", res)
            set_state("token_invalid" if res != self.EResult.TryAnotherCM else "error", str(res))
            return False
        self.account_name = account_name
        self.refresh_token = token
        self._after_logon()
        return True

    def _after_logon(self):
        self.logged_in = True
        self._send_games()
        self.gevent.spawn(self._announce_identity)
        self.gevent.spawn(self._fetch_owned)

    def _announce_identity(self):
        for _ in range(20):
            try:
                if self.client.user and self.client.user.name:
                    break
            except Exception:
                pass
            self.gevent.sleep(0.5)
        try:
            sid = str(self.client.steam_id.as_64) if self.client.steam_id else ""
        except Exception:
            sid = ""
        try:
            persona = (self.client.user.name or "") if self.client.user else ""
        except Exception:
            persona = ""
        emit("identity", account_name=self.account_name, steam64=sid, persona=persona)

    # ── oyunlar ──────────────────────────────────────────────────────────────
    def _send_games(self):
        if not self.client.logged_on:
            return
        try:
            self.client.games_played(sorted(self.appids))
            set_state("logged_on", f"{len(self.appids)}")
        except Exception as e:
            log.warning("games_played hatası: %s", e)

    def _fetch_owned(self):
        c = self.client
        try:
            for _ in range(20):
                if c.licenses:
                    break
                self.gevent.sleep(0.5)
            pkg_ids = list(c.licenses.keys())
            appids = set()
            for i in range(0, len(pkg_ids), 300):
                try:
                    info = c.get_product_info(packages=pkg_ids[i:i + 300], timeout=25) or {}
                except Exception:
                    continue
                for pdata in info.get("packages", {}).values():
                    aps = pdata.get("appids", {})
                    for a in (aps.values() if isinstance(aps, dict) else aps):
                        try:
                            appids.add(int(a))
                        except Exception:
                            pass
            if not appids:
                return
            emit("owned", games=[{"appid": a, "name": ""} for a in sorted(appids)])
            lst, result = sorted(appids), []
            for i in range(0, len(lst), 250):
                try:
                    ainfo = c.get_product_info(apps=lst[i:i + 250], timeout=25) or {}
                except Exception:
                    ainfo = {}
                for aid, ad in ainfo.get("apps", {}).items():
                    common = ad.get("common", {}) if isinstance(ad, dict) else {}
                    if (common.get("type", "") or "").lower() in ("", "game"):
                        result.append({"appid": int(aid), "name": common.get("name", "") or ""})
                if result:
                    emit("owned", games=sorted(result, key=lambda x: x["name"].lower()))
        except Exception as e:
            log.warning("sahip olunan oyunlar alınamadı: %s", e)

    # ── yeniden bağlanma ─────────────────────────────────────────────────────
    def _relogin(self):
        try:
            self.client.reconnect(maxdelay=15)
        except Exception:
            return False
        if not self._ensure_connected():
            return False
        return self._cm_logon_with_token(self.account_name, self.refresh_token) == self.EResult.OK

    # ── komut işleme ─────────────────────────────────────────────────────────
    def handle(self, cmd):
        name = cmd.get("cmd")
        if name == "quit":
            self.want_quit = True
            self.guard_event.set()
        elif name == "set_games":
            self.appids = {int(a) for a in cmd.get("appids", [])}
            if self.logged_in:
                self._send_games()
        elif name == "guard":
            self.guard_code = str(cmd.get("code", "")).strip().upper()
            self.guard_event.set()
        elif name in ("login_password", "login_qr", "login_token"):
            if self.login_greenlet and not self.login_greenlet.dead:
                return
            self.appids = {int(a) for a in cmd.get("appids", [])} or self.appids
            if name == "login_password":
                self.login_greenlet = self.gevent.spawn(
                    self._login_password, cmd.get("username", ""), cmd.get("password", ""))
            elif name == "login_qr":
                self.login_greenlet = self.gevent.spawn(self._login_qr)
            else:
                self.login_greenlet = self.gevent.spawn(
                    self._login_token, cmd.get("account_name", ""), cmd.get("refresh_token", ""))

    def run(self):
        self.start_reader()
        set_state("idle")
        while not self.want_quit:
            try:
                while True:
                    self.handle(self.cmds.get_nowait())
            except queue.Empty:
                pass
            if self.logged_in and not self.client.connected:
                set_state("disconnected")
                if self._relogin():
                    self._send_games()
                else:
                    self.gevent.sleep(5)
            self.gevent.sleep(0.25)
        try:
            self.client.logout()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--creds", default="")
    ap.add_argument("--log", default="")
    a = ap.parse_args()
    if a.check:
        check()
        return
    if a.log:
        logging.basicConfig(filename=a.log, level=logging.INFO,
                            format="%(asctime)s %(levelname)s %(message)s")
    try:
        import gevent.event  # noqa: F401
        Engine(a.creds).run()
    except Exception as e:
        log.exception("motor çöktü")
        set_state("error", f"{type(e).__name__}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
