# Simulate Git conflicts, amend, reset, revert and stash in a disposable repository.
demo:
    bash verify/check.sh

# Check the simulation, utility tests and documented collaboration contracts.
check: demo
    sh verify/test-source-contract.sh .
