"""Synthetic loopback-only TLS fixture. Never logs requests or header values."""
import http.server
import ssl
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        mode = sys.argv[3]
        media = mode.startswith("range")
        cookie_ok = (self.headers.get("Cookie") is None if media else
                     self.headers.get("Cookie") == "KugooID=42; t=synthetic-token")
        if not cookie_ok or (media and self.headers.get("Range") != "bytes=0-4095"):
            self.send_response(403)
            self.end_headers()
            return
        prefix = bytearray(4096)
        prefix[0:4] = prefix[417:421] = b"\xff\xfb\x90\x64"
        body = bytes(prefix) if media else b'{"status":0,"error_code":30020}'
        if mode == "oversize-body":
            body = bytes(262145)
        if mode == "range-oversize":
            body += b"x"
        if mode == "range-id3-only":
            body = b"ID3\x04\0\0\0\0\0\0" + bytes(4086)
        self.send_response(206 if media else {"redirect": 302, "risk": 403, "limit": 429}.get(mode, 200))
        if mode == "redirect":
            self.send_header("Location", "http://127.0.0.1:1/forbidden")
        if mode == "ssa":
            self.send_header("ssa-code", "synthetic-challenge")
        if media:
            self.send_header("Content-Range", "bytes 0-4095/" + ("10000" if mode == "range-bad" else "2880000"))
        self.send_header("Content-Type", "audio/mpeg" if media else "application/json")
        if mode != "oversize-body":
            self.send_header("Content-Length", str(262145 if mode == "oversize" else len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[1], sys.argv[2])
server.socket = context.wrap_socket(server.socket, server_side=True)
print(server.server_port, flush=True)
server.serve_forever()
