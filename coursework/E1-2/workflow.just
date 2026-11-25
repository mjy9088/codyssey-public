# Play the quiz and retain state in the course directory.
run:
    PYTHONPATH=quiz_game/src python3 -B main.py

# Add, list and play a quiz, then read its persisted score in a fresh process.
demo:
    #!/bin/sh
    set -eu
    root=$PWD
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    export PYTHONPATH="$root/quiz_game/src"
    cd "$work"
    printf '%s\n' 2 'Which language is this quiz written in?' Bash Python Rust Java 2 \
      3 1 2 3 4 3 1 2 5 | python3 -B "$root/main.py"
    printf '%s\n' 4 5 | python3 -B "$root/main.py"

# Run the quiz tests and the offline public-origin argument guards.
check:
    PYTHONPATH=quiz_game/src python3 -B -m unittest discover -s quiz_game/tests -v
    sh scripts/tests/verify_public_origin_test.sh
