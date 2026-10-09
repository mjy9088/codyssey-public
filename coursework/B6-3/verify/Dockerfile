FROM mcr.microsoft.com/playwright@sha256:6446946a1d9fd62d9ae501312a2d76a43ee688542b21622056a372959b65d63d
WORKDIR /work
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY playwright.config.ts tsconfig.json biome.json ./
COPY tests-browser/ tests-browser/
RUN chown -R pwuser:pwuser /work
USER pwuser
ENTRYPOINT ["/work/node_modules/.bin/playwright", "test"]
