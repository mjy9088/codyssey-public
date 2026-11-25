# Show commit and PR drafts from a synthetic repository; no API or existing diff.
demo:
    #!/bin/sh
    set -eu
    export PYTHONPATH="$PWD/src" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    cd "$scratch"
    git init -q
    printf 'before\n' > example.txt
    git add example.txt
    git -c user.name='Synthetic Reviewer' -c user.email=fixture@example.invalid commit -qm fixture
    printf 'after\n' > example.txt
    python -m ai_git_review.cli commit
    python -m ai_git_review.cli pr

# Run the standard-library tests and source contracts (no API access).
check:
    PYTHONPATH=src python tests/run.py
    sh verify/test-source-contract.sh .
