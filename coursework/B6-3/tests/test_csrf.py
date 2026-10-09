from book_catalog.auth.csrf import (
    issue_public_token,
    session_token,
    verify_public_token,
    verify_session_token,
)


def test_public_token_is_signed_and_tampering_is_rejected() -> None:
    token = issue_public_token()

    assert verify_public_token(token)
    assert not verify_public_token(f"{token}changed")


def test_session_csrf_token_is_bound_to_session() -> None:
    token = session_token("first-session")

    assert verify_session_token("first-session", token)
    assert not verify_session_token("second-session", token)
