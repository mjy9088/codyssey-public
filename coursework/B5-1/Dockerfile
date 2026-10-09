FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844

ENV PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY src/ src/
COPY tests/ tests/
RUN addgroup -S redis && adduser -S -G redis redis \
    && chmod -R a+rX /app
USER redis
ENTRYPOINT ["python", "-m", "mini_redis.cli"]
