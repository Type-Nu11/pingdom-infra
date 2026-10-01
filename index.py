"""Generate a local-only HS512 JWT and the required app-proxy headers."""

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import uuid


# Test fixture only. Set JWT_SECRET_KEY to this same value in an isolated
# development environment; never use this key or generated token in production.
TEST_JWT_SECRET = "0123456789abcdef" * 4


def encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(now: int) -> str:
    header = {"alg": "HS512", "typ": "JWT"}
    payload = {
        "sub": "local-test-user",
        "type": "access",
        "role": "USER",
        "iat": now,
        "exp": now + 3600,
    }

    encoded_header = encode(json.dumps(header, separators=(",", ":")).encode())
    encoded_payload = encode(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")
    signature = hmac.new(
        TEST_JWT_SECRET.encode("utf-8"), signing_input, hashlib.sha512
    ).digest()

    return f"{encoded_header}.{encoded_payload}.{encode(signature)}"


def main() -> None:
    now = int(time.time())
    token = make_token(now)
    app_version = os.environ.get("APP_VERSION", "1.0.0")
    device_id = os.environ.get("DEVICE_ID", str(uuid.uuid4()))

    result = {
        "accessToken": token,
        "headers": {
            "Authorization": f"Bearer {token}",
            "X-Timestamp": str(now),
            "X-App-Version": app_version,
            "X-Device-Id": device_id,
        },
    }
    print(json.dumps(result, indent=2))
    print(
        "TEST ONLY: L7 JWT_SECRET_KEY must match the test fixture; "
        "do not use this token/key in production.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
