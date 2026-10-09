from base64 import urlsafe_b64decode, urlsafe_b64encode
from hashlib import sha256
from hmac import compare_digest, digest
from os import environ, urandom
from time import time
from typing import Final

TOKEN_LIFETIME_SECONDS: Final = 60 * 60 * 2
TOKEN_PARTS: Final = 3
_secret_text = environ.get("CATALOG_CSRF_SECRET")
_SECRET: Final = _secret_text.encode() if _secret_text else urandom(32)


def issue_token() -> str:
    payload = f"{int(time())}.{urlsafe_b64encode(urandom(18)).decode()}"
    signature = urlsafe_b64encode(digest(_SECRET, payload.encode(), sha256)).decode()
    return f"{payload}.{signature}"


def verify_token(token: str) -> bool:
    parts = token.split(".")
    if len(parts) != TOKEN_PARTS or not parts[0].isdecimal():
        return False
    issued_at = int(parts[0])
    if issued_at > int(time()) or int(time()) - issued_at > TOKEN_LIFETIME_SECONDS:
        return False
    payload = ".".join(parts[:2])
    expected = digest(_SECRET, payload.encode(), sha256)
    try:
        supplied = urlsafe_b64decode(parts[2].encode())
    except ValueError:
        return False
    return compare_digest(expected, supplied)
