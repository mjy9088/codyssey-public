FROM nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10

LABEL org.opencontainers.image.title="codyssey-workstation-web"
LABEL org.opencontainers.image.description="Static site for the Docker workstation lab"

COPY index.html /usr/share/nginx/html/index.html

HEALTHCHECK --interval=5s --timeout=2s --retries=5 \
  CMD wget -qO- http://127.0.0.1:80/ >/dev/null || exit 1
