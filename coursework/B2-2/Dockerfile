FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
RUN apk add --no-cache 'git~2' 'bash~5' 'nodejs~22'
WORKDIR /app
COPY src/ src/
COPY tests/ tests/
COPY verify/check.sh verify/check.sh
RUN chmod -R a+rX /app
USER 1000:1000
ENTRYPOINT ["bash", "/app/verify/check.sh"]
