FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
RUN apk add --no-cache git=2.49.1-r0
ENV PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_VALUE_0=*
WORKDIR /app
COPY src/ src/
COPY tests/ tests/
RUN mkdir /demo \
    && git -C /demo init -q \
    && git -C /demo config user.name "Synthetic Reviewer" \
    && git -C /demo config user.email "reviewer@example.invalid" \
    && printf 'before\n' > /demo/example.txt \
    && git -C /demo add example.txt \
    && git -C /demo commit -qm "initial synthetic fixture" \
    && printf 'after\n' > /demo/example.txt \
    && addgroup -S reviewer \
    && adduser -S -G reviewer reviewer \
    && chmod -R a+rX /app /demo
USER reviewer
WORKDIR /demo
ENTRYPOINT ["python", "-m", "ai_git_review.cli"]
