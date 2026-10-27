FROM mcr.microsoft.com/playwright:v1.58.2-noble@sha256:6446946a1d9fd62d9ae501312a2d76a43ee688542b21622056a372959b65d63d
WORKDIR /work
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund && mkdir -p artifacts && chown -R pwuser:pwuser artifacts
COPY index.html biome.json playwright.config.ts vite.config.ts tsconfig.json tsconfig.app.json tsconfig.node.json tsconfig.tests.json ./
COPY firestore.rules ./
COPY tests/ tests/
COPY src/ src/
RUN chmod -R a+rX /work && chown -R pwuser:pwuser /work/artifacts && chown pwuser:pwuser /work
USER pwuser
ENV HOME=/tmp
CMD ["sh", "-c", "npm run check && npm test && sh tests/deployment-build.sh && npx playwright test"]
