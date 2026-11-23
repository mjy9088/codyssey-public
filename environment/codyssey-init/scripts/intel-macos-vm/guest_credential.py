"""Supply the preset password for Codyssey's disposable Fusion guest."""

import os
import sys

LAB_GUEST_PASSWORD = "vm user password"


def guest_password():
    if os.environ.get("CODYSSEY_FUSION_USE_LAB_PASSWORD") == "1":
        return LAB_GUEST_PASSWORD
    return None


if __name__ == "__main__":
    password = guest_password()
    if password is None:
        sys.exit("The preset password is reserved for the unattended vmuser account.")
    print(password)
