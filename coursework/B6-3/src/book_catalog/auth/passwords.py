from base64 import urlsafe_b64decode, urlsafe_b64encode
from hashlib import scrypt
from hmac import compare_digest
from os import urandom
from typing import Final

WORK_FACTOR: Final = 2**14
BLOCK_SIZE: Final = 8
PARALLELISM: Final = 1
KEY_LENGTH: Final = 32
FORMAT_PARTS: Final = 6


def hash_password(password: str, salt: bytes | None = None) -> str:
    actual_salt = urandom(16) if salt is None else salt
    derived = scrypt(
        password.encode(),
        salt=actual_salt,
        n=WORK_FACTOR,
        r=BLOCK_SIZE,
        p=PARALLELISM,
        dklen=KEY_LENGTH,
    )
    return "$".join(
        (
            "scrypt",
            str(WORK_FACTOR),
            str(BLOCK_SIZE),
            str(PARALLELISM),
            urlsafe_b64encode(actual_salt).decode(),
            urlsafe_b64encode(derived).decode(),
        )
    )


def verify_password(password: str, encoded: str) -> bool:
    parts = encoded.split("$")
    if len(parts) != FORMAT_PARTS or parts[0] != "scrypt":
        return False
    try:
        work, block, parallel = (int(part) for part in parts[1:4])
        salt = urlsafe_b64decode(parts[4].encode())
        expected = urlsafe_b64decode(parts[5].encode())
        supplied = scrypt(
            password.encode(), salt=salt, n=work, r=block, p=parallel, dklen=len(expected)
        )
    except (ValueError, MemoryError):
        return False
    return compare_digest(expected, supplied)
