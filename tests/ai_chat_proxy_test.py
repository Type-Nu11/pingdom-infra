"""실제 OpenResty에서 AI 경로·헤더·본문·응답 전달을 검증한다.

외부 provider와 운영 비밀값은 사용하지 않는다. Rust FFI만 임시 fixture로
대체하며 실제 JWT 서명·만료 검증과 운영 TLS/배포는 이 검증에 포함하지 않는다.
"""

import http.server
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid


class Backend(http.server.BaseHTTPRequestHandler):
    requests = []

    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.requests.append((self.path, dict(self.headers), body))
        if self.path.endswith("?invalid"):
            status, response = 400, {"code": "CHAT_REQUEST_INVALID"}
        elif self.path.endswith("?provider-failure"):
            status, response = 502, {"code": "PROVIDER_UNAVAILABLE"}
        elif json.loads(body).get("tools"):
            status, response = 200, {"content": None, "tool_calls": [{
                "id": "call_fixture", "type": "function", "function": {
                    "name": "searchNearbyPlaces", "arguments": {"keyword": "갈비탕"}
                }
            }]}
        else:
            status, response = 200, {"content": "Hello", "tool_calls": []}
        encoded = json.dumps(response).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("X-Request-Id", self.headers.get("X-Request-Id", ""))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *_):
        pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


def command(*args, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check, timeout=30)


def run():
    repo = Path(__file__).resolve().parents[1]
    container = "pingdom-ai-chat-test-" + uuid.uuid4().hex[:8]
    backend = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Backend)
    threading.Thread(target=backend.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="pingdom-ai-chat-") as temp:
            root = Path(temp)
            shutil.copytree(repo / "configs", root / "configs")
            shutil.copytree(repo / "src", root / "src")
            shutil.copytree(repo / "tests", root / "tests")
            (root / "logs").mkdir()
            # 배포와 같은 두 변수만 치환하고 Nginx의 $http_* 변수는 보존한다.
            substitutions = {"${BACKEND_HOST}": "host.docker.internal",
                             "${BACKEND_PORT}": str(backend.server_port)}
            for config in (root / "configs").rglob("*.conf"):
                source = config.read_text()
                for variable, value in substitutions.items():
                    source = source.replace(variable, value)
                config.write_text(source)
            (root / "nginx.conf").write_text((repo / "nginx.conf.template").read_text())
            # 실제 app_entry/app_auth/app_request를 실행하고 FFI 경계만 대체한다.
            (root / "src/lua/rust/native.lua").write_text("""
return {
    verify_jwt = function(token)
        return token == "fixture-valid" and 0 or 1
    end,
    validate_app_headers = function(timestamp, _, version, _, minimum, _, device)
        if timestamp == "stale" then return 1 end
        if version == "unsupported" then return 2 end
        if device == "invalid" then return 3 end
        return 0
    end
}
""")
            command("docker", "run", "--detach", "--pull", "never", "--name", container,
                    "--publish", "127.0.0.1::8081", "--publish", "127.0.0.1::8082",
                    "--add-host", "host.docker.internal:host-gateway",
                    "--env", "JWT_SECRET_KEY=fixture-only", "--env", "AI_API_KEY=",
                    "--volume", str(root) + ":/etc/nginx",
                    "--volume", str(root / "src") + ":/src:ro",
                    "openresty/openresty:alpine", "openresty", "-p", "/etc/nginx/",
                    "-c", "nginx.conf", "-g", "daemon off;")
            command("docker", "exec", container, "openresty", "-p", "/etc/nginx/",
                    "-c", "nginx.conf", "-t")
            print("PASS OpenResty template and includes", flush=True)
            print(command("docker", "exec", "--workdir", "/etc/nginx", container,
                          "/usr/local/openresty/luajit/bin/luajit",
                          "tests/app_entry_test.lua").stdout.strip(), flush=True)
            web = "http://" + command("docker", "port", container, "8081/tcp").stdout.strip()
            app = "http://" + command("docker", "port", container, "8082/tcp").stdout.strip()
            for attempt in range(30):
                try:
                    urllib.request.urlopen(web + "/actuator/health", timeout=2).close()
                    break
                except urllib.error.URLError:
                    if attempt == 29:
                        raise
                    time.sleep(0.1)

            headers = {"Host": "www.typenull.xyz", "Content-Type": "application/json",
                       "Authorization": "Bearer fixture-valid", "X-Client-Type": "App",
                       "X-Request-Id": "req_fixture", "X-Timestamp": str(int(time.time())),
                       "X-App-Version": "1.0.0", "X-Device-Id": str(uuid.uuid4())}
            payload = b'{"messages":[{"role":"user","content":"Hello"}],"tools":[]}'
            opener = urllib.request.build_opener(NoRedirect())

            def post(path="/ai/chat", body=payload, changes=None):
                # 실제 2r/s 제한을 유지한 채 사례끼리 충돌하지 않게 한다.
                time.sleep(0.55)
                request_headers = {**headers, **(changes or {})}
                request_headers = {key: value for key, value in request_headers.items() if value is not None}
                request = urllib.request.Request(app + path, data=body, headers=request_headers)
                try:
                    response = opener.open(request, timeout=5)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    assert "Location" not in response.headers
                    return response.status, dict(response.headers), json.loads(response.read())

            status, response_headers, response = post()
            assert status == 200 and response == {"content": "Hello", "tool_calls": []}
            assert response_headers["X-Request-Id"] == "req_fixture"
            path, forwarded, body = Backend.requests[-1]
            assert path == "/ai/chat" and body == payload
            for name, value in headers.items():
                assert forwarded[name] == value, (name, forwarded)
            print("PASS model-free body, app JWT, metadata, trace and response preserved", flush=True)

            tool_payload = json.dumps({"messages": [{"role": "user", "content": "갈비탕집 있어?"}],
                "tools": [{"type": "function", "function": {"name": "searchNearbyPlaces",
                    "description": "주변 장소 검색", "parameters": {"type": "object",
                        "properties": {"keyword": {"type": "string"}}}}}]}).encode()
            status, _, response = post("/ai/chat?fixture=tools", tool_payload)
            assert status == 200 and response["content"] is None
            assert response["tool_calls"][0]["function"]["arguments"] == {"keyword": "갈비탕"}
            assert Backend.requests[-1][0] == "/ai/chat?fixture=tools"
            assert Backend.requests[-1][2] == tool_payload
            print("PASS tools, query and tool_calls object preserved", flush=True)

            for path, expected_status, code in [
                    ("/ai/chat?invalid", 400, "CHAT_REQUEST_INVALID"),
                    ("/ai/chat?provider-failure", 502, "PROVIDER_UNAVAILABLE")]:
                status, _, response = post(path)
                assert status == expected_status and response["code"] == code
                print("PASS backend error preserved:", expected_status, flush=True)

            for changes, expected_status in [
                    ({"Authorization": None}, 401),
                    ({"Authorization": "Bearer fixture-invalid"}, 401),
                    ({"Authorization": "Bearer fixture-expired"}, 401),
                    ({"X-Timestamp": None}, 400),
                    ({"X-Timestamp": "stale"}, 400),
                    ({"X-App-Version": "unsupported"}, 400),
                    ({"X-Device-Id": "invalid"}, 400)]:
                count = len(Backend.requests)
                status, _, _ = post(changes=changes)
                assert status == expected_status and len(Backend.requests) == count
            print("PASS 7 auth/metadata rejection cases never reach backend (FFI fixture)", flush=True)
    except subprocess.CalledProcessError as error:
        print(error.stderr)
        raise
    finally:
        command("docker", "rm", "--force", container, check=False)
        backend.shutdown()
        backend.server_close()


if __name__ == "__main__":
    run()
