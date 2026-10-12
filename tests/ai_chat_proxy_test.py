"""실제 OpenResty에서 공개 AI 계약과 Groq 변환을 검증한다.

Groq 대신 임시 로컬 HTTPS fixture를 사용한다. Rust FFI만 대체하므로 실제
JWT 서명·만료, Groq 계정/모델 접근, 운영 TLS/배포는 검증하지 않는다.
"""

import http.server
import json
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid


class Provider(http.server.BaseHTTPRequestHandler):
    requests = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        payload = json.loads(body)
        self.requests.append((self.path, dict(self.headers), payload))
        marker = payload["messages"][-1]["content"]
        status = 200
        message = {"role": "assistant", "content": "Hello"}
        finish = "stop"
        if payload.get("tools") and payload["messages"][-1]["role"] != "tool":
            message = {"role": "assistant", "content": None, "tool_calls": [{
                "id": "call_fixture", "type": "function", "function": {
                    "name": "searchNearbyPlaces",
                    "arguments": json.dumps({"keyword": "갈비탕", "filters": {}, "ids": []})
                }
            }]}
            finish = "tool_calls"
        if marker in ("provider-400", "provider-401", "provider-429", "provider-500"):
            status = int(marker.rsplit("-", 1)[1])
            response = {"error": {"message": "fixture-sensitive-provider-detail"}}
        else:
            response = {"id": "provider-id", "model": "openai/gpt-oss-20b",
                        "choices": [{"finish_reason": finish, "message": message}],
                        "usage": {"total_tokens": 1}}
            if marker == "missing-choices":
                response = {"unexpected": True}
            elif marker == "truncated-choice":
                response["choices"][0]["finish_reason"] = "length"
            elif marker == "empty-answer":
                message["content"] = ""
            elif marker in ("bad-arguments", "array-arguments", "unknown-tool", "duplicate-call", "empty-object"):
                call = message["tool_calls"][0]
                if marker == "unknown-tool":
                    call["function"]["name"] = "notRegistered"
                elif marker == "duplicate-call":
                    message["tool_calls"].append(call)
                else:
                    call["function"]["arguments"] = {
                        "bad-arguments": "{", "array-arguments": "[]", "empty-object": "{}"
                    }[marker]
        encoded = b'{invalid' if marker == "bad-json" else json.dumps(response).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("X-Provider-Secret", "fixture-private")
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
    provider = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Provider)
    started = False
    try:
        with tempfile.TemporaryDirectory(prefix="pingdom-ai-chat-") as temp:
            root = Path(temp)
            shutil.copytree(repo / "configs", root / "configs")
            shutil.copytree(repo / "src", root / "src")
            shutil.copytree(repo / "tests", root / "tests")
            (root / "logs").mkdir()
            (root / "fixture.cnf").write_text("""
[req]
distinguished_name=dn
x509_extensions=extensions
prompt=no
[dn]
CN=localhost
[extensions]
subjectAltName=DNS:localhost
basicConstraints=critical,CA:TRUE
keyUsage=critical,digitalSignature,keyCertSign
""")
            command("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-config", str(root / "fixture.cnf"), "-keyout", str(root / "fixture.key"),
                    "-out", str(root / "fixture.crt"))
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(root / "fixture.crt", root / "fixture.key")
            provider.socket = tls.wrap_socket(provider.socket, server_side=True)
            threading.Thread(target=provider.serve_forever, daemon=True).start()
            started = True
            # Spring은 연결하지 않는다. AI 요청은 Groq fixture에만 도달해야 한다.
            substitutions = {"${BACKEND_HOST}": "host.docker.internal", "${BACKEND_PORT}": "1"}
            for config in (root / "configs").rglob("*.conf"):
                source = config.read_text()
                for variable, value in substitutions.items():
                    source = source.replace(variable, value)
                config.write_text(source)
            ai_config = root / "configs/conf.d/app/ai.conf"
            source = ai_config.read_text()
            assert "proxy_pass https://api.groq.com/openai/v1/chat/completions;" in source
            assert "proxy_ssl_verify on;" in source
            source = source.replace("https://api.groq.com/openai/v1/chat/completions;",
                                    f"https://host.docker.internal:{provider.server_port}/openai/v1/chat/completions;")
            source = source.replace("proxy_ssl_name api.groq.com;", "proxy_ssl_name localhost;")
            source = source.replace("/etc/ssl/certs/ca-certificates.crt;", "/etc/nginx/fixture.crt;")
            ai_config.write_text(source)
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
                    "--env", "JWT_SECRET_KEY=fixture-only", "--env", "AI_API_KEY=fixture-groq-key",
                    "--env", "AI_MODEL=",
                    "--volume", str(root) + ":/etc/nginx",
                    "--volume", str(root / "src") + ":/src:ro",
                    "openresty/openresty:alpine", "openresty", "-p", "/etc/nginx/",
                    "-c", "nginx.conf", "-g", "daemon off;")
            command("docker", "exec", container, "openresty", "-p", "/etc/nginx/", "-c", "nginx.conf", "-t")
            command("docker", "exec", container, "test", "-s", "/etc/ssl/certs/ca-certificates.crt")
            print("PASS OpenResty config and CA bundle", flush=True)
            print(command("docker", "exec", "--workdir", "/etc/nginx", container,
                          "/usr/local/openresty/luajit/bin/luajit", "tests/app_entry_test.lua").stdout.strip(), flush=True)
            app = "http://" + command("docker", "port", container, "8082/tcp").stdout.strip()
            headers = {"Host": "www.typenull.xyz", "Content-Type": "application/json",
                       "Authorization": "Bearer fixture-valid", "X-Client-Type": "App",
                       "X-Request-Id": "req_fixture", "X-Timestamp": str(int(time.time())),
                       "X-App-Version": "1.0.0", "X-Device-Id": str(uuid.uuid4()),
                       "Cookie": "fixture-app-cookie", "X-SignatureBase64": "fixture-legacy"}
            payload = {"messages": [{"role": "user", "content": "Hello"}], "tools": []}
            opener = urllib.request.build_opener(NoRedirect())

            def post(body=payload, path="/ai/chat", changes=None, method="POST"):
                time.sleep(0.55)  # 실제 2r/s 제한을 유지한다.
                request_headers = {**headers, **(changes or {})}
                request_headers = {key: value for key, value in request_headers.items() if value is not None}
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                request = urllib.request.Request(app + path, data=data, headers=request_headers, method=method)
                try:
                    response = opener.open(request, timeout=5)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    raw = response.read()
                    if response.status == 500:
                        print((root / "logs/error.log").read_text()[-3000:], flush=True)
                    assert "Location" not in response.headers
                    assert "X-Provider-Secret" not in response.headers
                    assert b"fixture-sensitive-provider-detail" not in raw
                    return response.status, dict(response.headers), json.loads(raw) if raw.startswith(b"{") else raw

            status, response_headers, response = post({**payload, "model": "untrusted-model", "stream": True},
                                                      path="/ai/chat?model=untrusted")
            assert status == 200 and response == {"content": "Hello", "tool_calls": []}, (status, response)
            assert response_headers["X-Request-Id"] == "req_fixture"
            path, forwarded, sent = Provider.requests[-1]
            assert path == "/openai/v1/chat/completions" and sent["model"] == "openai/gpt-oss-20b"
            assert sent["stream"] is False and sent["messages"] == payload["messages"]
            assert forwarded["Authorization"] == "Bearer fixture-groq-key"
            assert forwarded["Host"] == "api.groq.com" and forwarded["X-Request-Id"] == "req_fixture"
            for name in ("Cookie", "X-Device-Id", "X-Timestamp", "X-App-Version", "X-Client-Type", "X-SignatureBase64"):
                assert name not in forwarded, (name, forwarded)
            print("PASS model injection, query/options isolation, HTTPS provider request and public response", flush=True)

            tools = [{"type": "function", "function": {"name": "searchNearbyPlaces", "description": "주변 장소 검색",
                       "parameters": {"type": "object", "properties": {}, "required": []}}}]
            tool_payload = {"messages": [{"role": "user", "content": "갈비탕집 있어?"}], "tools": tools}
            status, _, response = post(tool_payload)
            assert status == 200 and "content" not in response
            call = response["tool_calls"][0]
            assert call["function"]["arguments"] == {"keyword": "갈비탕", "filters": {}, "ids": []}
            assert Provider.requests[-1][2]["tools"] == tools
            history = {"messages": [*tool_payload["messages"], {"role": "assistant", "tool_calls": [call]},
                        {"role": "tool", "tool_call_id": call["id"], "content": {"places": [], "meta": {}}}], "tools": tools}
            status, _, response = post(history)
            assert status == 200 and response["content"] == "Hello"
            sent = Provider.requests[-1][2]
            assert json.loads(sent["messages"][1]["tool_calls"][0]["function"]["arguments"]) == call["function"]["arguments"]
            assert json.loads(sent["messages"][2]["content"]) == {"places": [], "meta": {}}
            status, _, response = post({**tool_payload, "messages": [{"role": "user", "content": "empty-object"}]})
            assert status == 200 and response["tool_calls"][0]["function"]["arguments"] == {}
            print("PASS tool schemas, object/string conversion, empty arrays/objects and tool follow-up", flush=True)

            for marker, expected, code in [("provider-400", 502, "PROVIDER_UNAVAILABLE"),
                    ("provider-401", 502, "PROVIDER_UNAVAILABLE"), ("provider-500", 502, "PROVIDER_UNAVAILABLE"),
                    ("provider-429", 429, "PROVIDER_RATE_LIMITED")]:
                status, _, response = post({"messages": [{"role": "user", "content": marker}]})
                assert status == expected and response == {"error": code}, (marker, status, response)
            for marker in ("bad-json", "missing-choices", "truncated-choice", "empty-answer",
                           "bad-arguments", "array-arguments", "unknown-tool", "duplicate-call"):
                body = {"messages": [{"role": "user", "content": marker}]}
                if marker in ("bad-arguments", "array-arguments", "unknown-tool", "duplicate-call"):
                    body["tools"] = tools
                status, _, response = post(body)
                assert status == 502 and response == {"error": "PROVIDER_RESPONSE_INVALID"}, (marker, status, response)
            print("PASS provider errors, invalid/truncated answers and unsafe tool calls rejected", flush=True)

            invalid = [b'{broken', {"messages": []}, {"messages": {}}, {"messages": [{}]},
                       {"messages": [{"role": "system", "content": "Hello"}]}, {**payload, "tools": {}},
                       {**payload, "tools": [{"type": "browser_search"}]},
                       {"messages": [{"role": "tool", "tool_call_id": "missing", "content": {}}]},
                       {"messages": [{"role": "assistant", "content": "Hello"}]},
                       {"messages": [{"role": "user", "content": "Hello"}] * 51}]
            for body in invalid:
                count = len(Provider.requests)
                status, _, _ = post(body)
                assert status == 400 and len(Provider.requests) == count, (body, status)
            count = len(Provider.requests)
            assert post(changes={"Content-Type": "application/jsonjunk"})[0] == 415
            assert post(method="GET")[0] == 405
            assert post(path="/_internal/ai/groq-chat")[0] == 404
            assert len(Provider.requests) == count
            print("PASS invalid public input, unsupported method/media and internal-path access blocked", flush=True)

            for changes, expected in [({"Authorization": None}, 401),
                    ({"Authorization": "Bearer fixture-invalid"}, 401), ({"Authorization": "Bearer fixture-expired"}, 401),
                    ({"X-Timestamp": None}, 400), ({"X-Timestamp": "stale"}, 400),
                    ({"X-App-Version": "unsupported"}, 400), ({"X-Device-Id": "invalid"}, 400)]:
                count = len(Provider.requests)
                status, _, _ = post(changes=changes)
                assert status == expected and len(Provider.requests) == count
            logs = (root / "logs/error.log").read_text()
            assert "ai_chat request_id=req_fixture provider=groq model=openai/gpt-oss-20b status=200 outcome=success" in logs
            for secret in ("fixture-groq-key", "fixture-sensitive-provider-detail", "fixture-app-cookie"):
                assert secret not in logs
            print("PASS 7 auth/metadata rejections and safe trace logging (FFI fixture)", flush=True)
    except subprocess.CalledProcessError as error:
        print(error.stderr)
        raise
    finally:
        command("docker", "rm", "--force", container, check=False)
        # shutdown only after serve_forever started, otherwise it waits forever.
        if started:
            provider.shutdown()
        provider.server_close()


if __name__ == "__main__":
    run()
