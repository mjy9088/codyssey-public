FROM mcr.microsoft.com/playwright:v1.58.2-noble@sha256:6446946a1d9fd62d9ae501312a2d76a43ee688542b21622056a372959b65d63d
WORKDIR /work
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund \
    && mkdir artifacts && chown pwuser:pwuser artifacts
COPY playwright.config.mjs biome.json tsconfig.checkjs.json ./
COPY tests/ tests/
COPY index.html ./
COPY css/ css/
COPY js/ js/
COPY images/ images/
COPY docs/screenshots/ docs/screenshots/
RUN chmod -R a+rX /work && chown -R pwuser:pwuser artifacts docs/screenshots
USER pwuser
CMD ["npm", "test"]
