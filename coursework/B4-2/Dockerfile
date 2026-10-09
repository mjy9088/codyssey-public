FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412 AS builder
RUN apk add --no-cache gcc=14.2.0-r6 musl-dev=1.2.5-r12
COPY fixture/resource-fixture.c /src/resource-fixture.c
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror -pthread -o /resource-fixture /src/resource-fixture.c

FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
RUN apk add --no-cache bash=5.2.37-r0 procps-ng=4.0.4-r3
WORKDIR /work
COPY --from=builder /resource-fixture /work/bin/resource-fixture
COPY bin/ /work/bin/
COPY tests/ /work/tests/
RUN chmod 0755 /work/bin/* /work/tests/*.sh
ENTRYPOINT ["/work/tests/run.sh"]
