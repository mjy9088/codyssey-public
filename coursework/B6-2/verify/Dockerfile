FROM mcr.microsoft.com/playwright:v1.58.2-noble@sha256:6446946a1d9fd62d9ae501312a2d76a43ee688542b21622056a372959b65d63d
WORKDIR /work
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund && mkdir -p artifacts && chown -R pwuser:pwuser artifacts
COPY playwright.config.js ./
COPY tests-browser/ tests-browser/
RUN chmod -R a+rX /work
USER pwuser
CMD ["npx", "playwright", "test"]
