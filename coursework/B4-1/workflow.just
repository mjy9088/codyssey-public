# Monitor and report on a synthetic process; Linux only, never the supplied target.
demo: check

# Exercise the Linux monitoring fixture, thresholds, rotation, and report parser.
check:
    bash tests/run.sh
