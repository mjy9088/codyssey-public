FROM tailscale/tailscale:v1.88.3@sha256:b2a19f6b6402adc26a2aa8cb90da66afe3061e718ac67ed3f21ec3d4b366439f

RUN apk add --no-cache \
      bash=5.2.21-r0 \
      bind-tools=9.18.44-r0 \
      curl=8.14.1-r2 \
      git=2.43.7-r0 \
      jq=1.7.1-r0 \
      openssh-client-default=9.6_p1-r2 \
  && mkdir -p /host

ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_CACHE_DIR=/var/cache/mise \
    PATH=/opt/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
COPY scripts/install-tailnet-tools.sh /usr/local/lib/codyssey/install-tailnet-tools.sh
RUN bash /usr/local/lib/codyssey/install-tailnet-tools.sh \
  && printf 'eval "$(mise activate bash)"\n' >> /root/.bashrc
COPY scripts/tailnet-dns.sh /usr/local/bin/codyssey-tailnet-dns

WORKDIR /host
COPY tailscale-entrypoint.sh /usr/local/bin/codyssey-tailscale
ENTRYPOINT ["bash", "/usr/local/bin/codyssey-tailscale"]
