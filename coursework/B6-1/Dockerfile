FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

RUN apk add --no-cache sqlite=3.49.2-r1 \
    && addgroup -S library && adduser -S -G library library
WORKDIR /app
COPY sql/ sql/
COPY results/ results/
COPY scripts/ scripts/
RUN chmod 0755 scripts/*.sh && chown -R library:library /app
USER library
ENTRYPOINT ["sh", "scripts/check.sh"]
