# Start the interactive mode selector.
run:
    python3 -B main.py

# Analyze the bundled JSON data without interactive input.
analyze:
    printf '2\n' | python3 -B main.py

# Run the standard-library unit test suite.
test:
    python3 -B -m unittest discover -s tests -v

# Run the standard-library checks without writing bytecode.
check: test

# Feed the assignment's 3x3 Cross/X example to manual mode.
demo:
    printf '1\n0 1 0\n1 1 1\n0 1 0\n1 0 1\n0 1 0\n1 0 1\n1 0 1\n0 1 0\n1 0 1\n' | python3 -B main.py
