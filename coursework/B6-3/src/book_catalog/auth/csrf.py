from base64 import b64decode, urlsafe_b64encode
from hashlib import sha256
from hmac import compare_digest, digest
from os import environ, urandom
from time import time
from typing import Final

TOKEN_TTL: Final = 60 * 60 * 2
TOKEN_PARTS: Final = 3
_secret_text = environ.get("CATALOG_CSRF_SECRET", "local-demo-csrf-secret-change-me")
_SECRET: Final = _secret_text.encode()


def issue_public_token() -> str:
    payload = f"{int(time())}.{urlsafe_b64encode(urandom(16)).decode()}"
    signature = urlsafe_b64encode(digest(_SECRET, payload.encode(), sha256)).decode()
    return f"{payload}.{signature}"


def verify_public_token(token: str) -> bool:
    parts = token.split(".")
    if len(parts) != TOKEN_PARTS or not parts[0].isdecimal():
        return False
    issued = int(parts[0])
    if issued > int(time()) or int(time()) - issued > TOKEN_TTL:
        return False
    try:
        supplied = b64decode(parts[2].encode(), altchars=b"-_", validate=True)
    except ValueError:
        return False
    return compare_digest(digest(_SECRET, ".".join(parts[:2]).encode(), sha256), supplied)


def session_token(raw_session: str) -> str:
    return urlsafe_b64encode(digest(_SECRET, raw_session.encode(), sha256)).decode()


def verify_session_token(raw_session: str, token: str) -> bool:
    return compare_digest(session_token(raw_session), token)
