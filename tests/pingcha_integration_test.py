"""Run against the isolated OpenResty fixture on ports 18081/18082."""
import hashlib
from concurrent.futures import ThreadPoolExecutor
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("PINGCHA_TEST_URL", "http://127.0.0.1:18081")
UA = "PingCha-integration-test"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


client = urllib.request.build_opener(NoRedirect())


def request(path, method="GET", data=None, headers=None, base=BASE):
    time.sleep(0.12)  # Respect the real challenge endpoint rate limit.
    merged = {"User-Agent": UA, **(headers or {})}
    if data is not None:
        data = json.dumps(data).encode()
        merged.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(base + path, data=data, method=method, headers=merged)
    try:
        res = client.open(req, timeout=5)
    except urllib.error.HTTPError as error:
        res = error
    return res.status, res.headers, res.read()


def expect(code, path, **kwargs):
    result = request(path, **kwargs)
    assert result[0] == code, (path, code, result)
    return result


if "--disabled" in sys.argv:
    _, _, body = expect(200, "/_pingdom/pingcha/status")
    assert json.loads(body) == {"enabled": False, "verified": False}
    expect(200, "/auth/login", method="POST", data={})
    expect(200, "/v3/api-docs/app")
    _, headers, body = expect(200, "/console/login", headers={"Accept": "text/html"})
    assert b'modal.js' not in body and headers.get("ETag") is not None
    assert "'nonce-" not in headers["Content-Security-Policy"]
    _, _, body = expect(200, "/console/headers", headers={"Accept-Encoding": "gzip", "If-None-Match": '"old"'})
    assert json.loads(body) == {"encoding": "gzip", "etag": '"old"'}
    for path, kwargs in [("challenge", {}), ("verify", {"method": "POST", "data": {}})]:
        _, headers, body = expect(200, "/_pingdom/pingcha/" + path, **kwargs)
        assert json.loads(body) == {"enabled": False, "verified": False}
        assert headers.get("Set-Cookie") is None
    print("PASS PingCha disabled: no gate/injection/CSP or proxy header changes, no clearance issuance")
    sys.exit(0)

status, headers, body = expect(403, "/auth/login", method="POST", data={})
assert json.loads(body)["code"] == "PINGCHA_REQUIRED"
_, headers, body = expect(200, "/console/login?next=%2Fusers", headers={"Accept": "text/html"})
assert headers.get("Location") is None
assert body.count(b'/_pingdom/captcha/modal.js') == 1
assert body.index(b'/_pingdom/captcha/modal.js') < body.index(b'</body>')
assert headers.get("ETag") is None and headers["Cache-Control"] == "no-store"
assert "'nonce-" in headers["Content-Security-Policy"]
assert "object-src 'none'" in headers["Content-Security-Policy"]
_, _, body = expect(200, "/console/headers", headers={"Accept-Encoding": "gzip", "If-None-Match": '"old"'})
assert json.loads(body) == {"encoding": "", "etag": ""}
_, _, body = expect(200, "/console/headers", headers={"Accept-Encoding": "gzip"}, base="http://127.0.0.1:18082")
assert json.loads(body)["encoding"] == "gzip"
_, _, body = expect(200, "/console/fixture.css")
assert b'modal.js' not in body
_, _, body = expect(200, "/_pingdom/pingcha/status")
assert json.loads(body)["verified"] is False
expect(200, "/actuator/health")
expect(200, "/auth/login", method="OPTIONS")
expect(200, "/auth/login", method="POST", data={}, base="http://127.0.0.1:18082")
expect(200, "/auth/refresh", method="POST", data={})
expect(200, "/auth/provider/callback")
expect(200, "/_pingdom/captcha/assets/logo.svg")
expect(403, "/v3/api-docs/app")
expect(403, "/api/auth/login", method="POST", data={})
expect(403, "/_pingdom/pingcha/challenge", headers={"Origin": "https://evil.invalid"})
expect(403, "/_pingdom/pingcha/challenge", headers={"Sec-Fetch-Site": "cross-site"})
expect(405, "/_pingdom/pingcha/verify")
expect(415, "/_pingdom/pingcha/verify", method="POST", data={}, headers={"Content-Type": "text/plain"})
expect(400, "/_pingdom/pingcha/verify", method="POST", data={})
expect(400, "/_pingdom/pingcha/verify", method="POST", data={"id": "a" * 64, "counter": 16384})
expect(403, "/_pingdom/pingcha/verify", method="POST", data={"id": "a" * 64, "counter": 0})
expect(413, "/_pingdom/pingcha/verify", method="POST", data={"padding": "a" * 2048})

_, _, body = expect(200, "/_pingdom/pingcha/challenge")
challenge = json.loads(body)
assert challenge["difficulty"] == 10 and challenge["expires_in"] == 120
counter = next(i for i in range(16384)
               if int.from_bytes(hashlib.sha256(f'{challenge["nonce"]}:{i}'.encode()).digest()[:2], "big") < 64)
proof = {"id": challenge["id"], "counter": counter}
wrong = next(i for i in range(16384)
             if int.from_bytes(hashlib.sha256(f'{challenge["nonce"]}:{i}'.encode()).digest()[:2], "big") >= 64)
expect(403, "/_pingdom/pingcha/verify", method="POST", data={**proof, "counter": wrong})
expect(403, "/_pingdom/pingcha/verify", method="POST", data=proof, headers={"User-Agent": "other-agent"})
_, headers, body = expect(200, "/_pingdom/pingcha/verify", method="POST", data=proof)
assert json.loads(body)["verified"] is True
cookie_header = headers["Set-Cookie"]
for flag in ["Secure", "HttpOnly", "SameSite=Lax", "Path=/", "Max-Age=900"]:
    assert flag in cookie_header
cookie = cookie_header.split(";", 1)[0]
expect(403, "/_pingdom/pingcha/verify", method="POST", data=proof)
expect(403, "/auth/login", method="POST", data={}, headers={"Cookie": "__Host-pingcha=" + "0" * 64})
expect(403, "/auth/login", method="POST", data={}, headers={"Cookie": cookie + "z"})
expect(403, "/auth/login", method="POST", data={}, headers={"Cookie": cookie, "User-Agent": "other-agent"})
expect(200, "/auth/login", method="POST", data={}, headers={"Cookie": cookie})
expect(200, "/api/auth/login", method="POST", data={}, headers={"Cookie": cookie})
expect(200, "/console/login", headers={"Cookie": cookie, "Accept": "text/html"})
expect(200, "/v3/api-docs/app", headers={"Cookie": cookie})
_, _, body = expect(200, "/_pingdom/pingcha/challenge", headers={"Cookie": cookie})
assert json.loads(body)["verified"] is True
_, _, body = expect(200, "/_pingdom/pingcha/challenge")
parallel = json.loads(body)
parallel_counter = next(i for i in range(16384)
                        if int.from_bytes(hashlib.sha256(f'{parallel["nonce"]}:{i}'.encode()).digest()[:2], "big") < 64)
with ThreadPoolExecutor(max_workers=2) as pool:
    def submit_proof(_):
        return request("/_pingdom/pingcha/verify", method="POST", data={"id": parallel["id"], "counter": parallel_counter})[0]
    assert sorted(pool.map(submit_proof, range(2))) == [200, 403]
# flush_all uses the dictionary's expiry mechanism, without waiting 15 minutes.
_, _, body = expect(200, "/_pingdom/pingcha/challenge")
expired = json.loads(body)
expect(200, "/auth/__pingcha_test_expire", base="http://127.0.0.1:18082")
expect(403, "/auth/login", method="POST", data={}, headers={"Cookie": cookie})
expect(403, "/_pingdom/pingcha/verify", method="POST", data={"id": expired["id"], "counter": 0})
print("PASS PingCha: challenge proof, replay/forgery/binding, cookie flags, public web gates, app/health/OPTIONS exemptions")
