import base64
import hashlib
import hmac
import json
import time


SECRET_KEY = "local-test-secret"


def encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


header = {
    "alg": "HS256",
    "typ": "JWT",
}

now = int(time.time())

payload = {
    "sub": "local-test-user",
    "iat": now,
    "exp": now + 3600,
}

encoded_header = encode(
    json.dumps(header, separators=(",", ":")).encode()
)

encoded_payload = encode(
    json.dumps(payload, separators=(",", ":")).encode()
)

signing_input = f"{encoded_header}.{encoded_payload}".encode()

signature = hmac.new(
    SECRET_KEY.encode(),
    signing_input,
    hashlib.sha256,
).digest()

token = ".".join(
    (
        encoded_header,
        encoded_payload,
        encode(signature),
    )
)

print(token)