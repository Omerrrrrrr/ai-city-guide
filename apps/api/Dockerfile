# Debian-based (not alpine) -- @duckdb/node-api ships prebuilt glibc
# binaries, which fail to load under musl libc.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
# ensureSchema() runs drizzle migrations on every boot (idempotent) from a
# path resolved relative to dist/ -- see src/ensure-schema.ts.
COPY drizzle ./drizzle

EXPOSE 4000
CMD ["node", "dist/index.js"]
