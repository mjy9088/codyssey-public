FROM node:24.13.0-bookworm-slim@sha256:4660b1ca8b28d6d1906fd644abe34b2ed81d15434d26d845ef0aced307cf4b6f
WORKDIR /app/ops/firebase
COPY ops/firebase/package.json ops/firebase/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY ops/firebase/request.mjs ops/firebase/provision.mjs ops/firebase/main.mjs ops/firebase/credentials.mjs ./
COPY firestore.rules /app/firestore.rules
RUN chmod -R a+rX /app
ENV HOME=/tmp FIREBASE_CLI_DISABLE_UPDATE_CHECK=true FIREBASE_CLI_DISABLE_USAGE_STATS=true
USER node
WORKDIR /tmp
ENTRYPOINT ["node", "/app/ops/firebase/main.mjs"]
