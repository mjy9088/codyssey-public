set dotenv-load := false

default:
    @just --list

# Start the interactive mode selector.
run:
    python3 main.py

# Analyze the bundled JSON data without interactive input.
analyze:
    printf '2\n' | python3 main.py

# Run the standard-library unit test suite.
test:
    python3 -m unittest discover -s tests -v

# Check syntax and run all tests.
check:
    python3 -m py_compile main.py tests/test_main.py
    python3 -m unittest discover -s tests -v

# Feed the assignment's 3x3 Cross/X example to manual mode.
demo:
    printf '1\n0 1 0\n1 1 1\n0 1 0\n1 0 1\n0 1 0\n1 0 1\n1 0 1\n0 1 0\n1 0 1\n' | python3 main.py
