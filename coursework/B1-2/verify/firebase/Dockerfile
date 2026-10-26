FROM node:24.13.0-bookworm-slim@sha256:4660b1ca8b28d6d1906fd644abe34b2ed81d15434d26d845ef0aced307cf4b6f
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless=17.0.21+9-1~deb12u1 && rm -rf /var/lib/apt/lists/*
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
