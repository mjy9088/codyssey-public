FROM mcr.microsoft.com/playwright:v1.58.2-noble@sha256:6446946a1d9fd62d9ae501312a2d76a43ee688542b21622056a372959b65d63d
WORKDIR /work
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund && mkdir -p artifacts && chown -R pwuser:pwuser artifacts
COPY playwright.config.ts vite.config.ts tsconfig.json tsconfig.app.json tsconfig.node.json ./
COPY tests/ tests/
COPY src/ src/
RUN chmod -R a+rX /work && chown -R pwuser:pwuser /work/artifacts && chown pwuser:pwuser /work
USER pwuser
ENV HOME=/tmp
CMD ["sh", "-c", "npm test && npx playwright test"]
