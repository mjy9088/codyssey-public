FROM node:24.13.0-bookworm-slim@sha256:4660b1ca8b28d6d1906fd644abe34b2ed81d15434d26d845ef0aced307cf4b6f AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY index.html tsconfig.json tsconfig.app.json tsconfig.node.json vite.config.ts ./
COPY src/ src/
RUN npm run build

FROM nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284
COPY verify/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/
RUN chmod -R a+rX /usr/share/nginx/html /etc/nginx/nginx.conf
USER 101:101
EXPOSE 8080
ENTRYPOINT ["nginx", "-g", "daemon off;"]
