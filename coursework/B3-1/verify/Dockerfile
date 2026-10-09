FROM localstack/localstack:4.11.1@sha256:3071c9c72a1e9dbc23ad33540617ad7825ffeba80a8f421eff798b97850f9de5
WORKDIR /work
COPY verify/ ./verify/
COPY infrastructure/ ./infrastructure/
ENTRYPOINT ["sh", "/work/verify/check.sh"]
