"""
Local CORS proxy for the FedEx Rate Quote Simulator (fedex-rate-quote-simulator.html).

Why: FedEx APIs don't send CORS headers, so a browser page can't call them
directly (Postman can because it's a desktop app). This proxy runs on YOUR
machine, forwards requests to FedEx, and adds the CORS headers the browser
needs. Nothing is logged or stored.

Cross-platform alternative to fedex_proxy.ps1 (macOS / Linux / Windows with Python).

Usage:
    python fedex_proxy.py          # listens on http://localhost:8765
Then open fedex-rate-quote-simulator.html in your browser.
"""
import gzip
import http.server
import urllib.error
import urllib.request
import zlib

PORT = 8765
FEDEX_HOSTS = {
    "production": "https://apis.fedex.com",
    "sandbox": "https://apis-sandbox.fedex.com",
}
FORWARD_HEADERS = ("Content-Type", "Authorization", "X-locale")


def _decompress(data, encoding):
    if encoding == "gzip":
        return gzip.decompress(data)
    if encoding == "deflate":
        return zlib.decompress(data)
    return data


class FedExProxy(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        env = self.headers.get("X-FedEx-Env", "production")
        target = FEDEX_HOSTS.get(env, FEDEX_HOSTS["production"]) + self.path

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else None

        req = urllib.request.Request(target, data=body, method="POST")
        for h in FORWARD_HEADERS:
            if self.headers.get(h):
                req.add_header(h, self.headers[h])

        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                status, data = r.status, r.read()
                data = _decompress(data, r.headers.get("Content-Encoding"))
                ctype = r.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as e:
            status, data = e.code, e.read()
            data = _decompress(data, e.headers.get("Content-Encoding"))
            ctype = e.headers.get("Content-Type", "application/json")
        except Exception as e:  # network failure, timeout, DNS ...
            status, data, ctype = 502, str(e).encode(), "text/plain"

        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"[proxy] {self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    print(f"FedEx CORS proxy running at http://localhost:{PORT}")
    print("Forwarding to apis.fedex.com / apis-sandbox.fedex.com. Ctrl+C to stop.")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), FedExProxy).serve_forever()
