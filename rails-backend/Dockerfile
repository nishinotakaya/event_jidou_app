ARG RUBY_VERSION=3.1.2
FROM ruby:$RUBY_VERSION-slim

WORKDIR /rails

# システムパッケージ（Ruby + Node.js + Playwright deps）
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential \
    libsqlite3-dev \
    libyaml-dev \
    pkg-config \
    curl \
    git \
    # Chromium (Playwright) 依存ライブラリ
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libdbus-1-3 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libpangocairo-1.0-0 \
    libx11-xcb1 libxcb-dri3-0 libxshmfence1 libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 インストール
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install --no-install-recommends -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# アプリ全体
COPY . .

# Node.js 投稿ブリッジ用パッケージ（/workspace にマウントされる親ディレクトリ）
# docker-compose の volumes で /workspace をマウント

# Playwright Chromium
RUN npx --yes playwright install chromium --with-deps 2>/dev/null || true

# DB 作成 & マイグレーション
RUN rails db:create db:migrate RAILS_ENV=development 2>/dev/null || true

EXPOSE 3001
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
