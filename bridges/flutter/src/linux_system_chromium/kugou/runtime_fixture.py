"""Offline official-site surrogate, not live KuGou or account evidence.

Only loopback is bound. Stdout is a private readiness/counts control protocol;
requests, headers, credentials, TLS errors and OpenSSL output are never logged.
"""

import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import threading
import urllib.parse


HASH = "11111111111111111111111111111111"
QUERY = urllib.parse.urlencode({
    "hash": HASH,
    "album_id": "7",
    "album_audio_id": "9",
    "mid": "synthetic-mid",
    "dfid": "synthetic-dfid",
    "userid": "42",
    "token": "synthetic-token",
    "signature": "00000000000000000000000000000000",
})
API_PATH = "/play/songinfo?" + QUERY
API_URL = "https://wwwapi.kugou.com" + API_PATH
PAGE = ("<!doctype html><meta charset=utf-8>"
        "<title>Synthetic offline capture surrogate</title>"
        "<link rel=icon href=data:,>"
        "<script>fetch(" + json.dumps(API_URL)
        + ", {credentials: 'include'}).catch(() => {});</script>").encode()
RESPONSE = json.dumps({"status": 1, "data": {
    "hash": HASH, "album_audio_id": 9, "album_id": 7,
    "privilege": 0, "is_free_part": 0,
    "play_url": "https://offline-media.example.org/synthetic.mp3",
    "bitrate": 128000, "timelength": 180000, "filesize": 2880000,
    "extname": "mp3", "quality": "standard",
}}).encode()


def openssl(*args, data=None):
    return subprocess.run(
        ["openssl", *map(str, args)], input=b"" if data is None else data, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, timeout=10, check=True,
    ).stdout


def certificate(directory):
    root = directory / "root.pem"
    root_key = directory / "root.key"
    leaf = directory / "leaf.pem"
    key = directory / "leaf.key"
    csr = directory / "leaf.csr"
    extensions = directory / "leaf.ext"
    openssl("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
            "-nodes", "-days", "1", "-subj", "/CN=Synthetic Offline Root",
            "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            "-keyout", root_key, "-out", root)
    openssl("req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
            "-nodes", "-subj", "/CN=www.kugou.com", "-keyout", key, "-out", csr)
    extensions.write_text(
        "basicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature\n"
        "extendedKeyUsage=serverAuth\n"
        "subjectAltName=DNS:www.kugou.com,DNS:wwwapi.kugou.com\n", encoding="ascii")
    openssl("x509", "-req", "-in", csr, "-CA", root, "-CAkey", root_key,
            "-set_serial", "2", "-days", "1", "-extfile", extensions, "-out", leaf)
    public = openssl("x509", "-in", leaf, "-pubkey", "-noout")
    der = openssl("pkey", "-pubin", "-outform", "DER", data=public)
    return root, leaf, key, base64.b64encode(hashlib.sha256(der).digest()).decode("ascii")


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def __init__(self, context):
        self.context = context
        self.counts = dict(page=0, api=0, rust=0, browser=0, range=0, rejected=0)
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), Handler)

    def get_request(self):
        socket, address = super().get_request()
        socket.settimeout(2)
        return self.context.wrap_socket(
            socket, server_side=True, do_handshake_on_connect=False), address

    def handle_error(self, *_args):
        pass


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        host = self.headers.get("Host")
        with self.server.lock:
            if self.headers.get("Range") is not None:
                self.server.counts["range"] += 1
                self.server.counts["rejected"] += 1
                status, content, kind = 403, b"", "text/plain"
            elif host == "www.kugou.com" and self.path == "/":
                self.server.counts["page"] += 1
                status, content, kind = 200, PAGE, "text/html"
            elif host == "wwwapi.kugou.com" and self.path.startswith("/play/songinfo"):
                self.server.counts["api"] += 1
                rust = self.headers.get("X-Synthetic-Owner") == "Rust"
                self.server.counts["rust" if rust else "browser"] += 1
                valid = (self.path == API_PATH
                         and self.headers.get("Cookie") == "KugooID=42; t=synthetic-token"
                         and self.headers.get("Origin") == "https://www.kugou.com"
                         and self.headers.get("Referer") == "https://www.kugou.com/"
                         and bool(self.headers.get("User-Agent")))
                if not valid:
                    self.server.counts["rejected"] += 1
                status, content, kind = (200 if valid else 403), RESPONSE, "application/json"
            else:
                self.server.counts["rejected"] += 1
                status, content, kind = 404, b"", "text/plain"
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Connection", "close")
        self.send_header("Cache-Control", "no-store")
        if host == "www.kugou.com" and status == 200:
            self.send_header("Set-Cookie", "KugooID=42; Domain=.kugou.com; Path=/; Secure; HttpOnly; SameSite=Lax")
            self.send_header("Set-Cookie", "t=synthetic-token; Domain=.kugou.com; Path=/; Secure; HttpOnly; SameSite=Lax")
        self.end_headers()
        try:
            self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


def emit(value):
    print(json.dumps(value, separators=(",", ":")), flush=True)


def main():
    os.umask(0o077)
    root, leaf, key, spki = certificate(Path(sys.argv[1]))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(leaf, key)
    server = Server(context)
    thread = threading.Thread(target=server.serve_forever,
                              kwargs={"poll_interval": 0.05}, daemon=True)
    thread.start()
    try:
        emit({"port": server.server_port, "spki": spki, "root_pem": root.read_text("ascii")})
        for command in sys.stdin:
            if command.strip() == "COUNTS":
                with server.lock:
                    emit(server.counts)
            elif command.strip() == "STOP":
                break
            else:
                raise ValueError("FIXTURE_CONTROL_INVALID")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(1)
