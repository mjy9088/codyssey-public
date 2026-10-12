FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412 AS terraform-provider

ARG TERRAFORM_VERSION=1.16.5
ARG TERRAFORM_LINUX_AMD64_SHA256=2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4
ARG TERRAFORM_LINUX_ARM64_SHA256=61a50b00485ee4810cf20581ef080fc54d34d666e175c58d9a10501c65c1ccde

WORKDIR /download
RUN case "$(uname -m)" in \
      x86_64) terraform_arch=amd64; terraform_sha256="${TERRAFORM_LINUX_AMD64_SHA256}" ;; \
      aarch64) terraform_arch=arm64; terraform_sha256="${TERRAFORM_LINUX_ARM64_SHA256}" ;; \
      *) printf 'Unsupported verifier architecture: %s\n' "$(uname -m)" >&2; exit 1 ;; \
    esac \
    && terraform_zip="terraform_${TERRAFORM_VERSION}_linux_${terraform_arch}.zip" \
    && wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${terraform_zip}" \
    && echo "${terraform_sha256}  ${terraform_zip}" | sha256sum -c - \
    && unzip "${terraform_zip}" \
    && install -m 0755 terraform /usr/local/bin/terraform \
    && printf '%s' "${terraform_arch}" > /tmp/terraform-arch

WORKDIR /work
COPY infrastructure/ ./infrastructure/
RUN terraform -chdir=infrastructure/deployment init -backend=false -lockfile=readonly \
    && terraform -chdir=infrastructure/access-bootstrap init -backend=false -lockfile=readonly \
    && mkdir -p /opt/terraform/providers \
    && terraform_arch="$(cat /tmp/terraform-arch)" \
    && terraform -chdir=infrastructure/deployment providers mirror -platform="linux_${terraform_arch}" /opt/terraform/providers

FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
COPY --from=terraform-provider /usr/local/bin/terraform /usr/local/bin/terraform
COPY --from=terraform-provider /opt/terraform/providers /opt/terraform/providers
COPY --from=terraform-provider /work/infrastructure /work/infrastructure
COPY verify/check.sh /work/verify/check.sh
COPY verify/terraform.rc /etc/terraform.rc
ENV TF_CLI_CONFIG_FILE=/etc/terraform.rc
WORKDIR /work
ENTRYPOINT ["sh", "/work/verify/check.sh"]
