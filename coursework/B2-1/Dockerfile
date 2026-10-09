FROM python@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY budget_app/ budget_app/
COPY tests/ tests/
RUN addgroup -S ledger && adduser -S -G ledger ledger \
    && mkdir -p /app/data && chown ledger:ledger /app/data \
    && chmod -R a+rX /app/budget_app /app/tests
USER ledger:ledger
ENTRYPOINT ["python", "-m", "budget_app"]
CMD ["--help"]
