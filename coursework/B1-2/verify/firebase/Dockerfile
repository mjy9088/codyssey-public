FROM node:22.19.0-bookworm-slim@sha256:4a4884e8a44826194dff92ba316264f392056cbe243dcc9fd3551e71cea02b90
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless=17.0.20.1+1-1~deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN npm install --global firebase-tools@14.15.2 --ignore-scripts --no-audit --no-fund
COPY firebase.json firestore.rules ./
RUN chmod a+r firebase.json firestore.rules
RUN HOME=/home/node firebase setup:emulators:firestore && chown -R node:node /home/node/.cache
ENV FIREBASE_CLI_DISABLE_UPDATE_CHECK=true
USER node
WORKDIR /tmp
EXPOSE 8080 9099
CMD ["firebase", "emulators:start", "--config", "/app/firebase.json", "--only", "auth,firestore", "--project", "benchbook-local"]
