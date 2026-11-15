"""LinkMeter LAN speed server.

Run this on a PC that is wired to your router. The LinkMeter app on your iPhone
downloads from and uploads to it over Wi-Fi, so the speed it shows is the Wi-Fi
link, not your internet connection.

    python lan_speed_server.py

Uses only the Python standard library. Port 8765.
"""
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8765
CHUNK = b"\0" * 262144


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _empty(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/ping":
            return self._empty()
        if url.path == "/down":
            try:
                n = int(parse_qs(url.query).get("bytes", ["0"])[0])
            except ValueError:
                n = 0
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(n))
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                sent = 0
                while sent < n:
                    piece = CHUNK if n - sent >= len(CHUNK) else CHUNK[: n - sent]
                    self.wfile.write(piece)
                    sent += len(piece)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                pass
            return
        self.send_error(404)

    def do_POST(self):
        if urlparse(self.path).path != "/up":
            return self.send_error(404)
        remaining = int(self.headers.get("Content-Length", "0"))
        try:
            while remaining > 0:
                data = self.rfile.read(min(262144, remaining))
                if not data:
                    break
                remaining -= len(data)
            self._empty()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # no packet is sent
        return s.getsockname()[0]
    except OSError:
        return "unknown"
    finally:
        s.close()


if __name__ == "__main__":
    ip = local_ip()
    print("LinkMeter LAN speed server")
    print(f"  Enter this address in the app:  {ip}")
    print(f"  Port {PORT}. Leave this window open. Ctrl+C to stop.")
    print("  If Windows asks, allow access on Private networks.")
    try:
        ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
