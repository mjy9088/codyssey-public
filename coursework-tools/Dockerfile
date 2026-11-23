FROM ghcr.io/jdx/mise:2026.11.4-debian@sha256:7769fb680659f7730db5b9c0d245c00ba517dfec9c720f6679248cb32e124095

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates coreutils gawk gcc git iproute2 libc6-dev netcat-openbsd procps unzip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash coursework

WORKDIR /workspace/course
ENV MISE_DATA_DIR=/opt/coursework/mise \
    MISE_CACHE_DIR=/opt/coursework/cache \
    MISE_TRUSTED_CONFIG_PATHS=/workspace/course/mise.toml \
    PLAYWRIGHT_BROWSERS_PATH=/opt/coursework/browsers \
    COURSEWORK_LISTEN=0.0.0.0
COPY . .
RUN mise install && mise exec -- just install && mise exec -- just _browser-deps \
    && chmod -R a+rX /opt/coursework \
    && chown -R coursework:coursework /workspace/course \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/home/coursework MISE_CACHE_DIR=/home/coursework/.cache/mise PATH=/opt/coursework/mise/shims:$PATH
USER coursework
ENTRYPOINT ["mise", "exec", "--"]
CMD ["bash", "--noprofile", "--norc"]
