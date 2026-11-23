# Open the Mini Git REPL.
repl:
    uv run --locked python main.py

# Demonstrate branches, merge, history, indexed search, and graph traversal.
demo:
    printf '%s\n' 'INIT Ada' 'COMMIT Initial' 'BRANCH feature' 'SWITCH feature' 'COMMIT Feature' 'SWITCH main' 'MERGE feature' 'LOG --sort-by=date' 'SEARCH Feature' 'ANCESTORS 0000000003' 'PATH 0000000001 0000000003' 'quit' | uv run --locked python main.py

# Check style, types, and the unit and CLI suite.
check: _python-check
