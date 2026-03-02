# === builder: 依存関係生成用 ===
# ベースを AWS 公式の Amazon Linux 2023 に変更
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder
WORKDIR /app

# Node.js 22 をインストールするための準備
RUN dnf update -y && dnf install -y \
    python3 \
    make \
    gcc-c++ \
    procps \
    tar \
    gzip \
    && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - \
    && dnf install -y nodejs \
    && dnf clean all

# pnpm のインストール
RUN npm install -g pnpm@10.12.4
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# === prod-deps: 本番用依存関係のみ抽出 ===
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS prod-deps
WORKDIR /app
# Node.js 22 インストール
RUN dnf update -y && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs && dnf clean all
RUN npm install -g pnpm@10.12.4
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

# === runner: 最終イメージ===
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS runner
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app

# 【最重要】OSを最新状態に更新（これで OpenSSL のパッチが当たります）
RUN dnf update -y && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs && dnf clean all

# nodeユーザーの作成（Amazon Linuxにはデフォルトでnodeユーザーがいないため）
RUN useradd -m node
COPY --chown=node:node package.json pnpm-lock.yaml /app/
COPY --from=prod-deps --chown=node:node /app/node_modules /app/node_modules
COPY --from=builder  --chown=node:node /app/build        /app/build

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthcheck').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

USER node
# start スクリプトを実行（start スクリプト内で react-router-serve が呼ばれる想定）
CMD ["npm", "run", "start"]
