FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
COPY scripts/check-repository.sh /opt/check-repository.sh
COPY tests/repository-integrity-test.sh /opt/repository-integrity-test.sh
RUN chmod 0755 /opt/check-repository.sh /opt/repository-integrity-test.sh
ENTRYPOINT ["/bin/sh", "/opt/repository-integrity-test.sh"]
