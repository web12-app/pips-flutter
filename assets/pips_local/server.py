#!/usr/bin/env python3
"""Pips local you-get server (runs inside ReTerminal's Alpine session).

Binds 127.0.0.1 ONLY — a local bridge between the Pips app and you-get, so
YouTube downloads happen on THIS phone's network (residential IP, normally
no bot check) instead of a datacenter worker.

Endpoints (all require header X-Pips-Token):
  GET  /health            -> {ok, you_get, python, ffmpeg}
  POST /meta      {url}   -> you-get --json metadata (title, duration, itags)
  POST /download  {url, itag} -> {job}  (starts you-get -F <itag>)
  GET  /job/<id>          -> live JSON {status, percent, mb, mbps, tail, log}
  GET  /file/<id>         -> streams the finished .mp4 (for Pips cloud upload)
  GET  /delete/<id>       -> removes the job + file

Cookies: set PIPS_YG_COOKIES=/path/to/cookies.txt before starting to attach
explicit owner cookies (Netscape format). The server never reads any browser
or app cookie database — that file is the only cookie source.

Stdlib only. Python 3.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = int(os.environ.get("PIPS_YG_PORT", "8787"))
TOKEN = "pips-local-yg-2026"
TMP = os.path.expanduser("~/.pips/downloads")
WORKDIR = os.path.expanduser("~/.pips")
COOKIES = os.environ.get("PIPS_YG_COOKIES") or ""
MAX_JOBS = 2

os.makedirs(TMP, exist_ok=True)
os.makedirs(WORKDIR, exist_ok=True)

LOG = []
LOG_LOCK = threading.Lock()
JOBS = {}
JOBS_LOCK = threading.Lock()


def log(msg):
    with LOG_LOCK:
        LOG.append(msg)
        del LOG[:-120]
    print(msg, flush=True)


def yg_cmd(*args):
    cmd = [sys.executable, "-m", "you_get"] + list(args)
    if COOKIES and os.path.exists(COOKIES):
        cmd += ["--cookies", COOKIES]
    return cmd


_YG_VERSION = None


def you_get_version():
    global _YG_VERSION
    if _YG_VERSION is None:
        try:
            p = subprocess.run([sys.executable, "-m", "you_get", "--version"],
                               capture_output=True, text=True, timeout=30)
            out = (p.stdout or p.stderr or "").strip().splitlines()
            _YG_VERSION = out[-1].strip() if out else ""
        except Exception:
            _YG_VERSION = ""
    return _YG_VERSION


def parse_meta(url):
    p = subprocess.run(yg_cmd("--json", url), capture_output=True, text=True,
                       timeout=300, cwd=WORKDIR)
    out = p.stdout or ""
    i = out.find("{")
    if i < 0:
        raise RuntimeError((p.stderr or out or "you-get failed").strip()[-300:])
    d = json.loads(out[i:])
    st = {str(k): v for k, v in (d.get("streams") or {}).items()}
    for k, v in (d.get("dash_streams") or {}).items():
        st[str(k)] = v
    itags = []
    for itag, s in st.items():
        q = str(s.get("quality") or "")
        m = re.match(r"(\d{2,5})x(\d{2,5})", q)
        itags.append({
            "itag": itag,
            "container": s.get("container"),
            "size": int(s.get("size") or 0),
            "height": int(m.group(2)) if m else 0,
            "label": q,
        })
    itags.sort(key=lambda x: (-x["height"], -x["size"]))
    d["itags"] = itags
    return d


PCT_RE = re.compile(r"(\d{1,3})(?:\.\d+)?%")
SPEED_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(MB/s|KB/s|GB/s|B/s)", re.I)
SIZE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(MB|GB|KB)", re.I)


def start_job(url, itag):
    with JOBS_LOCK:
        active = [j for j in JOBS.values() if j["status"] == "running"]
        if len(active) >= MAX_JOBS:
            raise RuntimeError("another download is running — wait for it to finish")
    job_id = uuid.uuid4().hex[:12]
    out_file = os.path.join(TMP, "pips-%s.mp4" % job_id)
    log_file = os.path.join(TMP, "pips-%s.log" % job_id)
    job = {
        "id": job_id, "url": url, "itag": str(itag), "status": "running",
        "percent": 0, "mb": 0.0, "mbps": 0.0, "file": out_file,
        "size": 0, "tail": "starting you-get …", "log": [],
        "started": time.time(), "proc": None, "logf": open(log_file, "w"),
    }
    with JOBS_LOCK:
        JOBS[job_id] = job
    t = threading.Thread(target=run_job, args=(job,), daemon=True)
    t.start()
    return job_id


def job_json(job, with_log=True):
    d = {
        "id": job["id"], "status": job["status"],
        "percent": round(job["percent"], 1), "mb": round(job["mb"], 1),
        "mbps": round(job["mbps"], 2), "size": job["size"],
        "tail": job["tail"], "seconds": int(time.time() - job["started"]),
        "itag": job["itag"],
    }
    if job.get("bot_check"):
        d["bot_check"] = True
    if with_log:
        d["log"] = job["log"][-40:]
    return d


def run_job(job):
    proc = None
    try:
        proc = subprocess.Popen(
            yg_cmd("-F", job["itag"], "-O", os.path.join(TMP, "pips-%s" % job["id"]),
                   job["url"]),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            bufsize=1, cwd=WORKDIR)
        job["proc"] = proc
        for line in proc.stdout:
            s = line.rstrip("\n")
            if s.strip():
                log("[%s] %s" % (job["id"], s[:200]))
                job["log"].append(s[:200])
                del job["log"][:-120]
                job["tail"] = s[:160]
                m = PCT_RE.search(s)
                if m:
                    job["percent"] = max(job["percent"], min(100, int(m.group(1))))
                m2 = SPEED_RE.search(s)
                if m2:
                    v = float(m2.group(1))
                    unit = m2.group(2).upper()
                    if unit == "KB/S":
                        job["mbps"] = v / 1024
                    elif unit == "GB/S":
                        job["mbps"] = v * 1024
                    elif unit == "B/S":
                        job["mbps"] = v / 1048576
                    else:  # MB/S
                        job["mbps"] = v
                m3 = SIZE_RE.search(s)
                if m3:
                    v = float(m3.group(1))
                    job["mb"] = v if m3.group(2) == "MB" else v * 1024 if m3.group(2) == "GB" else v / 1024
            time.sleep(0)
        rc = proc.wait()
        if os.path.exists(job["file"]) and os.path.getsize(job["file"]) > 0:
            job["size"] = os.path.getsize(job["file"])
            job["percent"] = 100
            job["status"] = "done"
            job["tail"] = "done — %d bytes" % job["size"]
            log("[%s] DONE %d bytes (rc=%s)" % (job["id"], job["size"], rc))
        else:
            job["status"] = "error"
            job["tail"] = (job["tail"] or "download failed") + " (rc=%s)" % rc
            low = "\n".join(job["log"][-25:]).lower()
            if "login_required" in low or "not a bot" in low or "sign in to confirm" in low:
                job["bot_check"] = True
            log("[%s] FAILED rc=%s" % (job["id"], rc))
    except Exception as e:
        job["status"] = "error"
        job["tail"] = str(e)[:160]
        log("[%s] ERROR %s" % (job["id"], e))
    finally:
        if proc and proc.poll() is None:
            proc.kill()
        try:
            job["logf"].close()
        except Exception:
            pass


def job_file(job):
    if job["status"] != "done" or not os.path.exists(job["file"]):
        return None
    return job["file"]


def cleanup_jobs():
    with JOBS_LOCK:
        for jid, j in list(JOBS.items()):
            if j["status"] in ("done", "error") and time.time() - j["started"] > 6 * 3600:
                for f in (j.get("file"), os.path.join(TMP, "pips-%s.log" % jid)):
                    try:
                        if f and os.path.exists(f):
                            os.remove(f)
                    except Exception:
                        pass
                JOBS.pop(jid, None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet
        pass

    def _send(self, code, obj, body=None, ctype="application/json", length=None):
        data = body if body is not None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length if length is not None else len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body is not None:
            self.wfile.write(body)
        else:
            self.wfile.write(data)

    def _authed(self):
        return self.headers.get("X-Pips-Token") == TOKEN

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw or b"{}")
        except Exception:
            return {}

    def do_GET(self):
        path = self.path.split("?")[0]
        if not self._authed():
            return self._send(401, {"ok": False, "error": "bad token"})
        if path == "/health":
            return self._send(200, {
                "ok": True,
                "you_get": you_get_version(),
                "python": sys.version.split()[0],
                "ffmpeg": bool(shutil.which("ffmpeg")),
                "ffmpeg_required_for_dash": True,
                "cookies": bool(COOKIES and os.path.exists(COOKIES)),
                "port": PORT,
            })
        m = re.match(r"^/job/([0-9a-f]{12})$", path)
        if m:
            j = JOBS.get(m.group(1))
            if not j:
                return self._send(404, {"ok": False, "error": "unknown job"})
            return self._send(200, job_json(j))
        m = re.match(r"^/file/([0-9a-f]{12})$", path)
        if m:
            j = JOBS.get(m.group(1))
            f = job_file(j) if j else None
            if not f:
                return self._send(404, {"ok": False, "error": "no finished file"})
            size = os.path.getsize(f)
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(size))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                with open(f, "rb") as fh:
                    while True:
                        chunk = fh.read(1024 * 1024)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        m = re.match(r"^/delete/([0-9a-f]{12})$", path)
        if m:
            j = JOBS.pop(m.group(1), None)
            if not j:
                return self._send(404, {"ok": False, "error": "unknown job"})
            if j.get("status") == "running" and j.get("proc") and j["proc"].poll() is None:
                j["proc"].kill()
            for f in (j.get("file"), os.path.join(TMP, "pips-%s.log" % j["id"])):
                try:
                    if f and os.path.exists(f):
                        os.remove(f)
                except Exception:
                    pass
            return self._send(200, {"ok": True})
        return self._send(404, {"ok": False, "error": "unknown path"})

    def do_POST(self):
        path = self.path.split("?")[0]
        if not self._authed():
            return self._send(401, {"ok": False, "error": "bad token"})
        d = self._body()
        if path == "/meta":
            url = str(d.get("url") or "")
            if not re.match(r"^https?://", url):
                return self._send(400, {"ok": False, "error": "bad url"})
            try:
                meta = parse_meta(url)
                return self._send(200, {"ok": True, "data": meta})
            except Exception as e:
                tail = str(e)[-300:]
                if "bot" in tail.lower() or "login_required" in tail.lower():
                    return self._send(409, {"ok": False, "bot_check": True,
                                            "error": "YouTube bot-check: " + tail})
                return self._send(409, {"ok": False, "error": tail})
        if path == "/download":
            url = str(d.get("url") or "")
            itag = str(d.get("itag") or "")
            if not re.match(r"^https?://", url) or not itag:
                return self._send(400, {"ok": False, "error": "bad url or itag"})
            try:
                jid = start_job(url, itag)
                return self._send(200, {"ok": True, "job": jid})
            except Exception as e:
                return self._send(409, {"ok": False, "error": str(e)[:200]})
        return self._send(404, {"ok": False, "error": "unknown path"})


def main():
    log("Pips local you-get server starting on %s:%d" % (HOST, PORT))
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    srv.daemon_threads = True
    def sweeper():
        while True:
            time.sleep(3600)
            cleanup_jobs()

    threading.Thread(target=sweeper, daemon=True).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
