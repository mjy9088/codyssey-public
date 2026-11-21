"""Read the disposable guest credential from a host-private file."""

import os
import re
import stat
import sys


def guest_password():
    path = os.environ.get("CODYSSEY_FUSION_GUEST_PASSWORD_FILE")
    if not path:
        return None
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), encoding="ascii") as secret:
        info = os.fstat(secret.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("the guest password file must be private and owned by the host user")
        password = secret.read(257)
    if password.endswith("\n"):
        password = password[:-1]
    if not re.fullmatch(r"[ -~]{1,128}", password):
        raise ValueError("expected one line of printable ASCII in the guest password file")
    return password


if __name__ == "__main__":
    try:
        value = guest_password()
        if value is None:
            sys.exit("No disposable guest credential file is configured.")
        print(value)
    except (OSError, ValueError) as error:
        sys.exit(f"Cannot read the disposable guest credential: {error}")
