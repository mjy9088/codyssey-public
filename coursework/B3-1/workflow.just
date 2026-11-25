# Preview the network candidate's static health page at http://127.0.0.1:8000.
demo:
    python -m http.server 8000 --bind "${COURSEWORK_LISTEN:-127.0.0.1}" --directory web

# Validate the infrastructure and run mock-provider tests without Azure credentials.
check:
    sh scripts/terraform-local.sh check
    sh verify/test-source-contract.sh .

# Regenerate the architecture diagram using the pinned renderer.
diagram:
    sh scripts/render-diagram.sh
