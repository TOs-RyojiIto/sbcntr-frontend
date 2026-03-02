# === builder: 依存関係生成用 ===
# al2023 (Amazon Linux 2023) ベースに変更
FROM public.ecr.aws/docker/library/node:22-al2023 AS builder
WORKDIR /app

# Amazon Linux なので apt ではなく dnf を使います
RUN dnf update -y && dnf install -y \
    python3 \
    make \
    gcc-c++ \
    procps \
    && dnf clean all

RUN corepack enable && corepack prepare pnpm@10.12.4 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# === prod-deps: 本番用依存関係のみ抽出 ===
FROM public.ecr.aws/docker/library/node:22-al2023 AS prod-deps
WORKDIR /app
RUN dnf update -y && dnf clean all
RUN corepack enable && corepack prepare pnpm@10.12.4 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

# === runner: 最終イメージ===
FROM public.ecr.aws/docker/library/node:22-al2023 AS runner
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app

# 【最重要】AWS公式イメージに対して dnf update を実行
RUN dnf update -y && dnf clean all

COPY --chown=node:node package.json pnpm-lock.yaml /app/
COPY --from=prod-deps --chown=node:node /app/node_modules /app/node_modules
COPY --from=builder  --chown=node:node /app/build        /app/build

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthcheck').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

USER node
CMD ["npm", "run", "start"]
