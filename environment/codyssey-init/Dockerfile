FROM tailscale/tailscale:v1.88.3@sha256:b2a19f6b6402adc26a2aa8cb90da66afe3061e718ac67ed3f21ec3d4b366439f

RUN apk add --no-cache \
      bash=5.2.21-r0 \
      bind-tools=9.18.44-r0 \
      curl=8.14.1-r2 \
      git=2.43.7-r0 \
      openssh-client-default=9.6_p1-r2 \
  && mkdir -p /host

WORKDIR /host
