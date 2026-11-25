# List repository coursework shortcuts.
default:
    @just --list

# Materialize a project's development files from the shared templates.
materialize course:
    sh scripts/coursework.sh materialize {{ quote(course) }}

# Prepare a standalone submission commit locally; never push.
submit course:
    sh scripts/publish-coursework.sh --prepare {{ quote(course) }}
