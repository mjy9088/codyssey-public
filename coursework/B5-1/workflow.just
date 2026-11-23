# Open the Mini Redis REPL.
repl:
    PYTHONPATH=src python -m mini_redis.cli

# Demonstrate key lookup, expiration, and max-memory/LRU operations.
demo:
    printf '%s\n' 'SET name codyssey' 'GET name' 'EXPIRE name 60' 'TTL name' 'CONFIG SET maxmemory 12' 'SET other example' 'GET name' 'INFO MEMORY' 'DEL other' 'EXIT' | PYTHONPATH=src python -m mini_redis.cli

# Exercise the standard-library cache and CLI suite.
check:
    PYTHONPATH=src python -m tests.run
