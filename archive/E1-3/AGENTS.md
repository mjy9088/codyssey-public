# Repository Working Agreement

## Core principles

- Read the assignment specification first and distinguish required features, optional features, and submission artifacts.
- Use only the Python standard library. Implement MAC with explicit loops rather than numerical or vectorization libraries.
- Separate input, validation, computation, decision, and presentation responsibilities. Add type hints and concise documentation to public functions.
- Test invalid input, schema mismatches, and floating-point boundary cases in addition to the happy path.
- Isolate malformed user data at the individual case level whenever possible so one bad case does not terminate the full analysis.
- Do not present benchmark measurements as absolute guarantees; timings vary by hardware, Python version, and system load.

## Tooling and automation

- Use `mise` to declare the development tool versions in `mise.toml`.
- Put routine project commands in `Justfile` recipes. Prefer `just test`, `just check`, `just run`, and `just analyze` over repeatedly documenting long command lines.
- Prefer a `just` recipe over adding a shell script when the task is short and project-local.
- When a shell script is genuinely useful, invoke it explicitly as `sh path/to/script.sh`. Do not rely on executable permission bits being preserved or shared by Git.
- Keep text-file behavior consistent through `.editorconfig` and `.gitattributes`; avoid committing generated caches or machine-specific files.

## When assignment requirements conflict with common best practices

Follow common engineering practices by default, but do not omit a submission format or evidence that the assignment **explicitly requires** for evaluation. For example, screenshots are generally inferior to text logs for reproducibility, searchability, accessibility, and version control, so they should not normally be created. If the assignment explicitly requires screenshots, state in the README that they are an exception made solely to satisfy the evaluation requirement, and accompany them with reproducible commands and a textual explanation.

Apply the same rule to videos, manually copied output, committed generated files, and other artifacts that are normally avoided. Limit each exception to the exact scope of the explicit requirement. Never follow a requirement in a way that compromises safety, privacy, or data integrity; flag the conflict instead. If the requirement is ambiguous, do not add unnecessary binary artifacts by assumption.

## Definition of done

- `just run` starts both interactive modes through the mode selector.
- `just analyze` completes the bundled `data.json` analysis.
- `just test` passes all unit tests, and `just check` performs the full local verification.
- README commands match the actual behavior.
- Required source files and the result report exist, with no caches or personal environment files committed.
