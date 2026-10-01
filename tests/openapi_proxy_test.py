"""원본 Nginx 설정의 문서 경로·헤더를 임시 OpenResty에서 검증한다.

기본 실행은 HTTP fixture, --backend-url은 실행 중인 Spring 서버를 사용한다.
Lua 인증은 401 fixture로 대체한다. 실제 JWT/TLS/운영 upstream 검증은 포함하지 않는다.
"""

import argparse
import http.server
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


DOCUMENTS = ["/v3/api-docs", "/v3/api-docs/admin", "/v3/api-docs/merchant",
             "/v3/api-docs/app", "/v3/api-docs/common", "/v3/api-docs/consulting"]
DOC_PATHS = DOCUMENTS + ["/v3/api-docs/swagger-config", "/swagger-ui/index.html"]


class Backend(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        status = 404 if self.path == "/v3/api-docs/" else 200
        body = json.dumps({
            "path": self.path,
            "headers": dict(self.headers),
            "servers": [{"url": self.headers.get("X-Forwarded-Proto", "http") + "://"
                         + self.headers.get("X-Forwarded-Host", "internal.example")}],
        }).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


def command(*args, timeout=30, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True, timeout=timeout)


def stop_test(*_):
    # Java 검증기가 시간 초과로 종료 요청해도 finally에서 컨테이너를 정리한다.
    raise SystemExit("검증 종료 요청")


def run(backend_url=None, expected_status=200):
    repo = Path(__file__).resolve().parents[1]
    backend = None
    if backend_url is None:
        backend = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Backend)
        threading.Thread(target=backend.serve_forever, daemon=True).start()
        backend_url = "http://host.docker.internal:" + str(backend.server_port)
    upstream = urllib.parse.urlsplit(backend_url)
    if (upstream.scheme != "http" or upstream.hostname != "host.docker.internal"
            or upstream.port is None or upstream.path or upstream.query or upstream.fragment
            or upstream.username or upstream.password):
        raise ValueError("backend URL은 http://host.docker.internal:<port> 형식이어야 합니다.")
    container = "pingdom-openapi-test-" + uuid.uuid4().hex[:8]
    try:
        with tempfile.TemporaryDirectory(prefix="pingdom-openapi-") as temp:
            root = Path(temp)
            shutil.copytree(repo / "configs", root / "configs")
            # 원본 include 체계를 유지한다. fixture 치환은 임시 복사본에만 적용한다.
            shutil.copy2(repo / "nginx.conf", root / "nginx.conf")
            (root / "logs").mkdir()
            for config in (root / "configs").rglob("*.conf"):
                source = config.read_text().replace("BACKEND_HOST:BACKEND_PORT", upstream.netloc)
                source = re.sub(r"access_by_lua_file [^;]+;",
                                "access_by_lua_block { return ngx.exit(401) }", source)
                # 원본 AI location도 구문 검사하되 외부 provider의 DNS/통신은 사용하지 않는다.
                source = source.replace("https://api.groq.com/openai/v1/chat/completions", backend_url)
                config.write_text(source)
            command("docker", "run", "--detach", "--name", container,
                    "--publish", "127.0.0.1::8081", "--add-host", "host.docker.internal:host-gateway",
                    "--volume", str(root) + ":/etc/nginx", "openresty/openresty:alpine",
                    "openresty", "-p", "/etc/nginx/", "-e", "/dev/stderr",
                    "-c", "nginx.conf", "-g", "daemon off;")
            command("docker", "exec", container, "openresty", "-p", "/etc/nginx/",
                    "-e", "/dev/stderr", "-c", "nginx.conf", "-t")
            print("PASS original nginx.conf includes and syntax", flush=True)
            base = "http://" + command("docker", "port", container, "8081/tcp").stdout.strip()
            opener = urllib.request.build_opener(NoRedirect())

            def external(path, extra=None):
                headers = {"Host": "www.typenull.xyz", **(extra or {})}
                try:
                    response = opener.open(urllib.request.Request(base + path, headers=headers), timeout=5)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    return response.code, dict(response.headers), response.read()

            def trusted(path, scheme="https"):
                response = command("docker", "exec", container, "wget", "-T", "5", "-S", "-qO-",
                                   "--header", "Host: www.typenull.xyz",
                                   "--header", "X-Forwarded-Proto: " + scheme,
                                   "--header", "X-Forwarded-For: 203.0.113.250",
                                   "--header", "X-Forwarded-Host: attacker.example",
                                   "--header", "X-Forwarded-Port: 8081",
                                   "http://127.0.0.1:8081" + path, check=False)
                statuses = re.findall(r"^\s*HTTP/\S+ (\d{3})", response.stderr, re.MULTILINE)
                assert statuses == [str(expected_status)], (path, response.stderr)
                assert "Location:" not in response.stderr, (path, response.stderr)
                return response.stdout

            for attempt in range(30):
                try:
                    external("/v3/api-docs")
                    break
                except urllib.error.URLError:
                    if attempt == 29:
                        raise
                    time.sleep(0.1)

            for path in DOC_PATHS:
                status, headers, body = external(path)
                assert status == expected_status, (path, status, body[:200])
                assert "Location" not in headers, (path, headers)
                if backend is not None:
                    assert json.loads(body)["path"] == path
                elif expected_status == 200 and path in DOCUMENTS:
                    assert json.loads(body)["servers"][0]["url"] == "http://www.typenull.xyz", (path, body[:200])
                print("PASS document without redirect:", path, status, flush=True)

            if backend is None:
                for path in DOC_PATHS:
                    body = trusted(path)
                    if expected_status == 200 and path in DOCUMENTS:
                        assert json.loads(body)["servers"][0]["url"] == "https://www.typenull.xyz", (path, body[:200])
                    print("PASS Spring policy via trusted proxy:", path, expected_status, flush=True)
                if expected_status == 401:
                    return

            status, _, body = external("/v3/api-docs?group=app&value=a%2Fb")
            assert status == 200
            if backend is not None:
                assert json.loads(body)["path"] == "/v3/api-docs?group=app&value=a%2Fb"
            print("PASS root query request", flush=True)

            status, headers, _ = external("/swagger-ui")
            assert status == 301 and headers["Location"] == "/swagger-ui/"
            print("PASS relative Swagger redirect", flush=True)

            status, _, body = external("/v3/api-docs/app", {
                "X-Forwarded-Proto": "https", "X-Forwarded-Host": "attacker.example",
                "X-Forwarded-Port": "8443", "X-Forwarded-For": "203.0.113.250",
                "Forwarded": "proto=https;host=attacker.example",
            })
            assert status == 200
            if backend is not None:
                headers = json.loads(body)["headers"]
                assert headers["X-Forwarded-Proto"] == "http", headers
                assert headers["X-Forwarded-Host"] == "www.typenull.xyz", headers
                assert headers["X-Forwarded-Port"] == "80", headers
                assert headers["X-Forwarded-For"] != "203.0.113.250", headers
                assert "Forwarded" not in headers, headers
            else:
                assert json.loads(body)["servers"][0]["url"] == "http://www.typenull.xyz"
            print("PASS untrusted forwarded headers ignored", flush=True)

            for scheme, expected_scheme, expected_port in [("https", "https", "443"),
                                                           ("https,http", "http", "80")]:
                body = json.loads(trusted("/v3/api-docs", scheme))
                if backend is not None:
                    headers = body["headers"]
                    assert headers["X-Forwarded-Proto"] == expected_scheme, headers
                    assert headers["X-Forwarded-Host"] == "www.typenull.xyz", headers
                    assert headers["X-Forwarded-Port"] == expected_port, headers
                    assert headers["X-Forwarded-For"].startswith("203.0.113.250"), headers
                else:
                    assert body["servers"][0]["url"] == expected_scheme + "://www.typenull.xyz", body["servers"]
                print("PASS trusted proxy scheme:", scheme, flush=True)

            assert external("/private/resource")[0] == 401
            print("PASS general path retains authentication fixture", flush=True)
    except BaseException as error:
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr)
        try:
            logs = command("docker", "logs", container, timeout=5, check=False)
            print(logs.stdout, logs.stderr)
        except (OSError, subprocess.TimeoutExpired):
            print("컨테이너 로그 수집 실패")
        raise
    finally:
        try:
            command("docker", "rm", "--force", container, timeout=10)
        finally:
            if backend is not None:
                backend.shutdown()
                backend.server_close()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop_test)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend-url")
    parser.add_argument("--expect-docs-status", type=int, choices=[200, 401], default=200)
    args = parser.parse_args()
    run(args.backend_url, args.expect_docs_status)
