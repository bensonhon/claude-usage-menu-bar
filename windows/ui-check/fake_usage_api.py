import http.server
import json
import ssl
import sys
from datetime import datetime, timedelta, timezone


def reset_time(hours_from_now):
    return (datetime.now(timezone.utc) + timedelta(hours=hours_from_now)).isoformat()


USAGE_BY_TOKEN = {
    "ui-check-main-token": {
        "five_hour": {"utilization": 38.0, "resets_at": reset_time(2.4)},
        "seven_day": {"utilization": 74.0, "resets_at": reset_time(51)},
        "seven_day_opus": {"utilization": 12.0, "resets_at": reset_time(51)},
        "seven_day_sonnet": {"utilization": 45.0, "resets_at": reset_time(51)},
        "extra_usage": {"is_enabled": True, "used_credits": 12.5, "monthly_limit": 50.0},
    },
    "ui-check-work-token": {
        "five_hour": {"utilization": 93.0, "resets_at": reset_time(0.7)},
        "seven_day": {"utilization": 55.0, "resets_at": reset_time(130)},
    },
}


class FakeUsageApiHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        usage = USAGE_BY_TOKEN.get(token)
        if self.path != "/api/oauth/usage" or usage is None:
            self.send_response(401)
            self.end_headers()
            return
        body = json.dumps(usage).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    certificate_path, key_path = sys.argv[1], sys.argv[2]
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 443), FakeUsageApiHandler)
    tls_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls_context.load_cert_chain(certificate_path, key_path)
    server.socket = tls_context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
