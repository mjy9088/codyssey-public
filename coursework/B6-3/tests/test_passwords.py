from book_catalog.auth.passwords import hash_password, verify_password


def test_scrypt_hash_uses_salt_and_verifies_password() -> None:
    encoded = hash_password("correct-horse-battery-staple", salt=b"0123456789abcdef")

    assert encoded.startswith("scrypt$16384$")
    assert verify_password("correct-horse-battery-staple", encoded)
    assert not verify_password("wrong", encoded)


def test_malformed_hash_is_rejected() -> None:
    assert not verify_password("secret", "not-a-password-hash")
