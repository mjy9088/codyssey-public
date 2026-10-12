FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
WORKDIR /work
COPY init.sh /src/init.sh
COPY tests/init-test.sh /src/tests/init-test.sh
RUN chmod 0755 /src/init.sh /src/tests/init-test.sh
ENTRYPOINT ["/bin/sh", "/src/tests/init-test.sh"]
