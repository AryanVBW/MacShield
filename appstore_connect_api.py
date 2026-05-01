#!/usr/bin/env python3
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_ecdsa_to_raw(signature: bytes) -> bytes:
    index = 2
    if signature[1] & 0x80:
        index = 2 + (signature[1] & 0x7F)
    if signature[index] != 0x02:
        raise ValueError("Invalid ECDSA R marker")
    r_length = signature[index + 1]
    r = signature[index + 2:index + 2 + r_length]
    index = index + 2 + r_length
    if signature[index] != 0x02:
        raise ValueError("Invalid ECDSA S marker")
    s_length = signature[index + 1]
    s = signature[index + 2:index + 2 + s_length]
    return r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")


def token() -> str:
    key_id = os.environ["APPSTORE_KEY_ID"]
    issuer_id = os.environ["APPSTORE_ISSUER_ID"]
    key_path = os.environ["APPSTORE_PRIVATE_KEY_PATH"]
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    unsigned = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", key_path], input=unsigned.encode())
    return f"{unsigned}.{b64url(der_ecdsa_to_raw(der))}"


def request(method: str, path: str, body=None):
    url = "https://api.appstoreconnect.apple.com" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as error:
        print(error.read().decode(), file=sys.stderr)
        raise
    return json.loads(text) if text else None


def main():
    method = sys.argv[1]
    path = sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    print(json.dumps(request(method, path, body), indent=2))


if __name__ == "__main__":
    main()
