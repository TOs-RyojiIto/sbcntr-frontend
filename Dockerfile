# === builder: 依存関係生成用 ===
FROM public.ecr.aws/docker/library/node:22-slim AS builder
WORKDIR /app
# OSパッケージを最新化し、ビルドに必要なツールをインストール
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    python3 \
    make \
    g++ \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.12.4 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# === prod-deps: 本番用依存関係のみ抽出 ===
FROM public.ecr.aws/docker/library/node:22-slim AS prod-deps
WORKDIR /app
# 念のためここでもアップグレード（一貫性のため）
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
RUN corepack enable && corepack prepare pnpm@10.12.4 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

# === runner: 最終イメージ===
FROM public.ecr.aws/docker/library/node:22-slim AS runner
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app

# 【重要】ここが ECR スキャンでチェックされる最終イメージのベースです。
# OpenSSL の脆弱性を消すために OS パッケージを最新にします。
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --chown=node:node package.json pnpm-lock.yaml /app/
COPY --from=prod-deps --chown=node:node /app/node_modules /app/node_modules
COPY --from=builder  --chown=node:node /app/build        /app/build

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthcheck').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

USER node
CMD ["npm", "run", "start"]
