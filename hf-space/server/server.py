#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Agent 学习监督 · 同步服务（单文件，仅标准库）
=================================================
用途：手机 App 与电脑端共用同一份学习进度。

运行：
    python server.py                 # 默认 http://0.0.0.0:8790
    set PORT=9000 && python server.py

电脑端：浏览器打开 http://127.0.0.1:8790
手机端：App 设置里填 http://<电脑局域网IP>:8790  + 同一个同步码

账号：同步码（6-20 位字母数字）。首次登录自动建号，两端输入同一码即互通。
微信登录：设置环境变量 WECHAT_APP_ID / WECHAT_SECRET / PUBLIC_URL 后自动启用，
        未配置时接口返回 enabled=false，前端隐藏按钮。详见 README。
"""

import hashlib
import json
import os
import secrets
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(ROOT, "web")
DB_PATH = os.path.join(ROOT, "data.db")
PORT = int(os.environ.get("PORT", "8790"))
HOST = os.environ.get("HOST", "0.0.0.0")

WECHAT_APP_ID = os.environ.get("WECHAT_APP_ID", "").strip()
WECHAT_SECRET = os.environ.get("WECHAT_SECRET", "").strip()
PUBLIC_URL = os.environ.get("PUBLIC_URL", "").strip().rstrip("/")

# 云端持久化：Render 这类免费容器的磁盘是临时的，用 GitHub Gist 当存储盘
GIST_ID = os.environ.get("GIST_ID", "").strip()
GH_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
SNAP_DIR = os.environ.get("SNAP_DIR", "").strip()  # 本地测试用：把快照写到文件夹
GIST_FILE = "studydb.json"

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".webmanifest": "application/manifest+json",
}

_lock = __import__("threading").Lock()


# ----------------------------------------------------------------------------
# 数据库
# ----------------------------------------------------------------------------
def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with db() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute(
            """CREATE TABLE IF NOT EXISTS users(
                code TEXT PRIMARY KEY,
                token TEXT UNIQUE,
                created REAL,
                wx_openid TEXT,
                wx_nick TEXT,
                pass_hash TEXT
            )"""
        )
        c.execute(
            """CREATE TABLE IF NOT EXISTS state(
                code TEXT PRIMARY KEY,
                json TEXT,
                rev INTEGER DEFAULT 0,
                updated REAL
            )"""
        )
        # 老库迁移：缺少 pass_hash 列时补上
        cols = [r[1] for r in c.execute("PRAGMA table_info(users)").fetchall()]
        if "pass_hash" not in cols:
            c.execute("ALTER TABLE users ADD COLUMN pass_hash TEXT")


# ----------------------------------------------------------------------------
# 账号（用户名 + 密码）
# ----------------------------------------------------------------------------
SEED_USER = "陈禹竹"
SEED_PASS = "230319"
PWD_ROUNDS = 120000


def hash_pwd(pwd, salt=None):
    if salt is None:
        salt = secrets.token_hex(8)
    dk = hashlib.pbkdf2_hmac("sha256", pwd.encode("utf-8"), salt.encode("utf-8"), PWD_ROUNDS)
    return salt + "$" + dk.hex()


def check_pwd(pwd, stored):
    if not stored:
        return False
    try:
        salt, digest = stored.split("$", 1)
    except ValueError:
        return False
    calc = hash_pwd(pwd, salt).split("$", 1)[1]
    return secrets.compare_digest(calc, digest)


def valid_name(name):
    if not (2 <= len(name) <= 20):
        return False
    for ch in name:
        if ch.isalnum() or ch in "_-·." or "\u4e00" <= ch <= "\u9fff":
            continue
        return False
    return True


def create_user(name, pwd, wx_openid=None):
    token = secrets.token_hex(16)
    with db() as c:
        c.execute(
            "INSERT INTO users(code,token,created,wx_openid,pass_hash) VALUES(?,?,?,?,?)",
            (name, token, time.time(), wx_openid, hash_pwd(pwd) if pwd else None),
        )
        c.execute(
            "INSERT OR IGNORE INTO state(code,json,rev,updated) VALUES(?,?,?,?)",
            (name, "{}", 0, time.time()),
        )
        row = c.execute("SELECT * FROM users WHERE code=?", (name,)).fetchone()
    mark_dirty()
    return row


def ensure_seed():
    with db() as c:
        row = c.execute("SELECT code,pass_hash FROM users WHERE code=?", (SEED_USER,)).fetchone()
    if row is None:
        create_user(SEED_USER, SEED_PASS)
        print("[seed] 已创建账号：%s" % SEED_USER)
    elif not row["pass_hash"]:
        with db() as c:
            c.execute("UPDATE users SET pass_hash=? WHERE code=?", (hash_pwd(SEED_PASS), SEED_USER))


def get_user_by_token(token):
    if not token:
        return None
    with db() as c:
        return c.execute("SELECT * FROM users WHERE token=?", (token,)).fetchone()


def get_or_create_user(code):
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE code=?", (code,)).fetchone()
        if row:
            return row
        token = secrets.token_hex(16)
        c.execute(
            "INSERT INTO users(code,token,created) VALUES(?,?,?)",
            (code, token, time.time()),
        )
        c.execute(
            "INSERT OR IGNORE INTO state(code,json,rev,updated) VALUES(?,?,?,?)",
            (code, "{}", 0, time.time()),
        )
        return c.execute("SELECT * FROM users WHERE code=?", (code,)).fetchone()


def load_state(code):
    with db() as c:
        row = c.execute("SELECT json,rev FROM state WHERE code=?", (code,)).fetchone()
    if not row:
        return {}, 0
    try:
        return json.loads(row["json"] or "{}"), int(row["rev"] or 0)
    except Exception:
        return {}, int(row["rev"] or 0)


def save_state(code, state, rev):
    with db() as c:
        c.execute(
            "UPDATE state SET json=?, rev=?, updated=? WHERE code=?",
            (json.dumps(state, ensure_ascii=False), rev, time.time(), code),
        )
    mark_dirty()


# ----------------------------------------------------------------------------
# 远端快照：把整个库导出成一份 JSON，存到 GitHub Gist（免费容器的磁盘是临时的）
# ----------------------------------------------------------------------------
_dirty = __import__("threading").Event()
_backup_started = False


def remote_enabled():
    return bool(SNAP_DIR) or bool(GIST_ID and GH_TOKEN)


_fail = {}
_fail_lock = __import__("threading").Lock()
FAIL_WINDOW = 600      # 10 分钟
FAIL_MAX = 12          # 同 IP 允许的失败次数


def login_allowed(ip):
    now = time.time()
    with _fail_lock:
        cnt, reset = _fail.get(ip, (0, 0))
        if now > reset:
            _fail[ip] = (0, now + FAIL_WINDOW)
            return True
        return cnt < FAIL_MAX


def login_fail(ip):
    now = time.time()
    with _fail_lock:
        cnt, reset = _fail.get(ip, (0, now + FAIL_WINDOW))
        if now > reset:
            cnt, reset = 0, now + FAIL_WINDOW
        _fail[ip] = (cnt + 1, reset)


def login_ok(ip):
    with _fail_lock:
        _fail.pop(ip, None)


def mark_dirty():
    if remote_enabled():
        _dirty.set()


def snapshot():
    with db() as c:
        users = [
            dict(r)
            for r in c.execute(
                "SELECT code,token,created,wx_openid,wx_nick,pass_hash FROM users"
            ).fetchall()
        ]
        states = [
            dict(r)
            for r in c.execute("SELECT code,json,rev,updated FROM state").fetchall()
        ]
    return {"v": 1, "at": time.time(), "users": users, "state": states}


def restore(data):
    if not data or not isinstance(data, dict):
        return 0
    users = data.get("users") or []
    states = data.get("state") or []
    with db() as c:
        for u in users:
            c.execute(
                "INSERT OR REPLACE INTO users(code,token,created,wx_openid,wx_nick,pass_hash)"
                " VALUES(?,?,?,?,?,?)",
                (
                    u.get("code"),
                    u.get("token"),
                    u.get("created"),
                    u.get("wx_openid"),
                    u.get("wx_nick"),
                    u.get("pass_hash"),
                ),
            )
        for s in states:
            c.execute(
                "INSERT OR REPLACE INTO state(code,json,rev,updated) VALUES(?,?,?,?)",
                (s.get("code"), s.get("json") or "{}", int(s.get("rev") or 0), s.get("updated") or time.time()),
            )
    return len(users)


def _snap_read():
    if SNAP_DIR:
        p = os.path.join(SNAP_DIR, GIST_FILE)
        if not os.path.exists(p):
            return None
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    req = urllib.request.Request(
        "https://api.github.com/gists/" + GIST_ID,
        headers={
            "Authorization": "Bearer " + GH_TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "agent-study",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(r.read().decode("utf-8"))
    files = data.get("files") or {}
    f = files.get(GIST_FILE)
    if not f:
        return None
    content = f.get("content")
    if content is None and f.get("raw_url"):
        with urllib.request.urlopen(f["raw_url"], timeout=15) as r2:
            content = r2.read().decode("utf-8")
    try:
        return json.loads(content or "null")
    except Exception:
        return None


def _snap_write(payload):
    text = json.dumps(payload, ensure_ascii=False)
    if SNAP_DIR:
        os.makedirs(SNAP_DIR, exist_ok=True)
        p = os.path.join(SNAP_DIR, GIST_FILE)
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, p)
        return
    body = json.dumps({"files": {GIST_FILE: {"content": text}}}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.github.com/gists/" + GIST_ID,
        data=body,
        method="PATCH",
        headers={
            "Authorization": "Bearer " + GH_TOKEN,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "agent-study",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        r.read()


def _backup_loop():
    while True:
        _dirty.wait()
        time.sleep(2)          # 攒一下，避免连续写把 API 打满
        _dirty.clear()
        try:
            _snap_write(snapshot())
        except Exception as e:
            print("[backup] 失败：%s，5 秒后重试" % e)
            time.sleep(5)
            _dirty.set()


def start_backup():
    global _backup_started
    if _backup_started or not remote_enabled():
        return
    _backup_started = True
    t = __import__("threading").Thread(target=_backup_loop, daemon=True)
    t.start()
    print("[backup] 已启用远端快照（%s）" % ("本地文件 " + SNAP_DIR if SNAP_DIR else "GitHub Gist"))



# ----------------------------------------------------------------------------
# 合并策略：条目级 last-write-wins（按每条记录的 at 时间戳）
# ----------------------------------------------------------------------------
def _at(rec, default=0):
    if isinstance(rec, dict):
        try:
            return int(rec.get("at") or 0)
        except Exception:
            return 0
    return default


def merge(old, new):
    """返回合并后的 state。old=服务端，new=客户端。"""
    out = {}
    ol = old.get("logs") or {}
    nl = new.get("logs") or {}
    logs = {}
    for k in set(ol) | set(nl):
        a, b = ol.get(k), nl.get(k)
        if a is None:
            logs[k] = b
        elif b is None:
            logs[k] = a
        else:
            logs[k] = b if _at(b) >= _at(a) else a
    out["logs"] = logs

    for field in ("cp", "fin", "quiz"):
        o = old.get(field) or {}
        n = new.get(field) or {}
        m = {}
        for k in set(o) | set(n):
            a, b = o.get(k), n.get(k)
            if a is None:
                m[k] = b
            elif b is None:
                m[k] = a
            elif isinstance(a, dict) and isinstance(b, dict):
                # 嵌套一层（quiz: date -> qid -> rec）
                sub = {}
                for kk in set(a) | set(b):
                    x, y = a.get(kk), b.get(kk)
                    if x is None:
                        sub[kk] = y
                    elif y is None:
                        sub[kk] = x
                    else:
                        sub[kk] = y if _at(y) >= _at(x) else x
                m[k] = sub
            else:
                m[k] = b if _at(b) >= _at(a) else a
        out[field] = m

    # 标量设置
    for field, default in (("startDate", "2026-10-27"), ("goal", 120)):
        a = old.get(field, default)
        b = new.get(field, default)
        oa = int(old.get("setAt") or 0)
        nb = int(new.get("setAt") or 0)
        out[field] = b if nb >= oa else a
    out["setAt"] = max(int(old.get("setAt") or 0), int(new.get("setAt") or 0))
    return out


# ----------------------------------------------------------------------------
# HTTP
# ----------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "StudySync/1.0"
    protocol_version = "HTTP/1.1"

    # ---------- 工具 ----------
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type,Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except Exception:
            n = 0
        if n <= 0:
            return {}
        raw = self.rfile.read(n)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _token(self):
        h = self.headers.get("Authorization") or ""
        if h.startswith("Bearer "):
            return h[7:].strip()
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        return (q.get("token") or [""])[0]

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), fmt % args))



    # ---------- 路由 ----------
    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        # HTTP/1.1 keep-alive 下必须把请求体读干净，否则残留字节会被当成下一个请求行
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n > 0:
                self.rfile.read(n)
        except Exception:
            pass
        u = urllib.parse.urlparse(self.path)
        path = u.path
        q = urllib.parse.parse_qs(u.query)

        if path == "/api/ping":
            return self._json({"ok": True, "t": int(time.time()), "wechat": bool(WECHAT_APP_ID)})

        if path == "/api/state":
            user = get_user_by_token(self._token())
            if not user:
                return self._json({"error": "unauthorized"}, 401)
            state, rev = load_state(user["code"])
            return self._json({"state": state, "rev": rev, "code": user["code"]})

        if path == "/api/wechat/url":
            if not WECHAT_APP_ID or not PUBLIC_URL:
                return self._json({"enabled": False, "reason": "未配置 WECHAT_APP_ID / PUBLIC_URL"})
            redirect = PUBLIC_URL + "/api/wechat/callback"
            url = (
                "https://open.weixin.qq.com/connect/qrconnect?appid=%s&redirect_uri=%s"
                "&response_type=code&scope=snsapi_login&state=%s#wechat_redirect"
                % (WECHAT_APP_ID, urllib.parse.quote(redirect, safe=""), secrets.token_hex(4))
            )
            return self._json({"enabled": True, "url": url})

        if path == "/api/wechat/callback":
            return self._wechat_callback(q)

        return self._static(path)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        # 先无条件读掉请求体：鉴权失败也要读，否则 keep-alive 连接会错位
        data = self._body()

        if path == "/api/login":
            ip = self.client_address[0]
            if not login_allowed(ip):
                return self._json({"error": "尝试次数太多，10 分钟后再试"}, 429)
            name = str(data.get("username") or "").strip()
            pwd = str(data.get("password") or "")
            if not name or not pwd:
                return self._json({"error": "请输入用户名和密码"}, 400)
            with db() as c:
                user = c.execute("SELECT * FROM users WHERE code=?", (name,)).fetchone()
            if user is None:
                login_fail(ip)
                return self._json({"error": "账号不存在，或用户名写错了"}, 401)
            if not check_pwd(pwd, user["pass_hash"]):
                login_fail(ip)
                return self._json({"error": "密码不对"}, 401)
            login_ok(ip)
            state, rev = load_state(user["code"])
            return self._json(
                {"token": user["token"], "username": user["code"], "state": state, "rev": rev}
            )

        if path == "/api/register":
            name = str(data.get("username") or "").strip()
            pwd = str(data.get("password") or "")
            if not valid_name(name):
                return self._json({"error": "用户名 2-20 位，可用中文、字母、数字、_ - · ."}, 400)
            if len(pwd) < 6:
                return self._json({"error": "密码至少 6 位"}, 400)
            with db() as c:
                exists = c.execute("SELECT code FROM users WHERE code=?", (name,)).fetchone()
            if exists:
                return self._json({"error": "这个用户名已被注册"}, 409)
            with _lock:
                user = create_user(name, pwd)
            state, rev = load_state(user["code"])
            return self._json(
                {"token": user["token"], "username": user["code"], "state": state, "rev": rev}
            )

        if path == "/api/password":
            user = get_user_by_token(self._token())
            if not user:
                return self._json({"error": "unauthorized"}, 401)
            old = str(data.get("old") or "")
            new = str(data.get("new") or "")
            if not check_pwd(old, user["pass_hash"]):
                return self._json({"error": "原密码不对"}, 401)
            if len(new) < 6:
                return self._json({"error": "新密码至少 6 位"}, 400)
            with db() as c:
                c.execute("UPDATE users SET pass_hash=? WHERE code=?", (hash_pwd(new), user["code"]))
            mark_dirty()
            return self._json({"ok": True})

        if path == "/api/state":
            user = get_user_by_token(self._token())
            if not user:
                return self._json({"error": "unauthorized"}, 401)
            incoming = data.get("state") or {}
            client_rev = int(data.get("rev") or 0)
            with _lock:
                cur, rev = load_state(user["code"])
                # 客户端版本落后太多时，仍以条目级合并为准，不丢数据
                merged = merge(cur, incoming)
                new_rev = rev + 1 if merged != cur or client_rev != rev else rev
                if new_rev != rev:
                    save_state(user["code"], merged, new_rev)
            return self._json({"state": merged, "rev": new_rev, "changed": new_rev != rev})

        if path == "/api/quiz":
            # 兼容旧调用：quiz 记录统一走 /api/state
            return self._json({"ok": False, "hint": "quiz 已并入 /api/state"}, 200)

        return self._json({"error": "not found"}, 404)

    # ---------- 微信回调 ----------
    def _wechat_callback(self, q):
        code = (q.get("code") or [""])[0]
        if not (WECHAT_APP_ID and WECHAT_SECRET):
            return self._json({"enabled": False})
        if not code:
            return self._json({"error": "missing code"}, 400)
        api = (
            "https://api.weixin.qq.com/sns/oauth2/access_token?appid=%s&secret=%s&code=%s&grant_type=authorization_code"
            % (WECHAT_APP_ID, WECHAT_SECRET, urllib.parse.quote(code))
        )
        try:
            with urllib.request.urlopen(api, timeout=10) as r:
                info = json.loads(r.read().decode("utf-8"))
        except Exception as e:
            return self._json({"error": "exchange failed", "detail": str(e)}, 502)
        openid = info.get("openid")
        if not openid:
            return self._json({"error": "no openid", "detail": info}, 400)
        # 用 openid 派生一个稳定同步码，多端扫码即同一账号
        derived = "wx_" + hashlib.sha256(("yg:" + openid).encode()).hexdigest()[:12]
        with _lock:
            user = get_or_create_user(derived)
            with db() as c:
                c.execute("UPDATE users SET wx_openid=? WHERE code=?", (openid, derived))
        target = "/#me?token=%s&user=%s&wechat=1" % (
            user["token"],
            urllib.parse.quote(derived),
        )
        self.send_response(302)
        self.send_header("Location", target)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ---------- 静态文件 ----------
    def _static(self, path):
        if path in ("/", ""):
            path = "/index.html"
        rel = path.lstrip("/").split("?")[0]
        full = os.path.normpath(os.path.join(WEB_DIR, rel))
        if not full.startswith(WEB_DIR):
            return self._json({"error": "forbidden"}, 403)
        if not os.path.isfile(full):
            body = b"404 not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self._cors()
            self.end_headers()
            self.wfile.write(body)
            return
        ext = os.path.splitext(full)[1].lower()
        with open(full, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)


def lan_ip():
    import socket

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


class Server(ThreadingHTTPServer):
    """浏览器刷新/断网造成的断连是常态，不往日志里刷 traceback。"""

    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, TimeoutError)):
            return
        super().handle_error(request, client_address)


def _prepare_logging():
    """pythonw 无控制台，把输出重定向到 server.log，方便事后查。"""
    if sys.stdout is None or sys.stderr is None:
        try:
            f = open(os.path.join(ROOT, "server.log"), "a", encoding="utf-8", buffering=1)
            sys.stdout = f
            sys.stderr = f
        except Exception:
            pass


def main():
    init_db()
    if remote_enabled():
        try:
            n = restore(_snap_read())
            if n:
                print("[backup] 已从远端恢复 %d 个账号" % n)
        except Exception as e:
            print("[backup] 远端恢复失败（继续用本地库）：%s" % e)
    ensure_seed()
    start_backup()
    try:
        srv = Server((HOST, PORT), Handler)
    except OSError as e:
        # 端口已被占用：说明已经有一个实例在跑，正常退出，避免反复重启
        print("[%s] 端口 %d 已被占用：服务已经在后台运行，直接打开 http://127.0.0.1:%d 即可（%s）" % (time.strftime("%F %T"), PORT, PORT, e))
        return
    ip = lan_ip()
    print("=" * 58)
    print("  Agent 学习监督 · 服务已启动  %s" % time.strftime("%F %T"))
    print("  电脑端： http://127.0.0.1:%d" % PORT)
    print("  局域网： http://%s:%d" % (ip, PORT))
    print("  预置账号：%s" % SEED_USER)
    print("  微信登录： %s" % ("已配置" if WECHAT_APP_ID else "未配置"))
    print("  数据文件： %s" % DB_PATH)
    print("=" * 58)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    _prepare_logging()
    # 自愈：任何未预期异常都在 3 秒后重来，直到用户主动关掉
    while True:
        try:
            main()
            break
        except KeyboardInterrupt:
            print("\n已停止")
            break
        except Exception:
            import traceback
            traceback.print_exc()
            print("[%s] 服务异常，3 秒后自动重启" % time.strftime("%F %T"))
            time.sleep(3)
