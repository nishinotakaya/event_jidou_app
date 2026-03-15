FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 5173

# Vite は --host でコンテナ外からアクセス可能にする
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
