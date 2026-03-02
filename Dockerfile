# === builder: 依存関係生成用 ===
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder
WORKDIR /app

# --allowerasing を追加して curl の衝突を回避
RUN dnf update -y && dnf install -y --allowerasing \
    shadow-utils \
    curl \
    python3 \
    make \
    gcc-c++ \
    procps \
    tar \
    gzip \
    && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - \
    && dnf install -y nodejs \
    && dnf clean all

RUN npm install -g pnpm@10.12.4
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# === prod-deps: 本番用依存関係のみ抽出 ===
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS prod-deps
WORKDIR /app
# ここでも --allowerasing を使用
RUN dnf update -y && dnf install -y --allowerasing curl shadow-utils && \
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && \
    dnf install -y nodejs && dnf clean all
RUN npm install -g pnpm@10.12.4
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

# === runner: 最終イメージ===
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS runner
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app

# 最終ステージも最新化
RUN dnf update -y && dnf install -y --allowerasing shadow-utils curl && \
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && \
    dnf install -y nodejs && dnf clean all

# ユーザー作成
RUN /usr/sbin/useradd -m node
COPY --chown=node:node package.json pnpm-lock.yaml /app/
COPY --from=prod-deps --chown=node:node /app/node_modules /app/node_modules
COPY --from=builder  --chown=node:node /app/build        /app/build

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthcheck').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

USER node
CMD ["npm", "run", "start"]
