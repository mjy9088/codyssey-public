# Serve only the public portfolio files at http://127.0.0.1:8000.
demo:
    python scripts/serve-native.py

# Run static checks, contracts, and the local Chromium suite.
check:
    COURSEWORK_NATIVE_BROWSER=1 npm test
