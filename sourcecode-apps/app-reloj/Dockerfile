FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production --ignore-scripts && npm cache clean --force
COPY server.js ./
USER node
EXPOSE 3000
ENV NODE_ENV=production PORT=3000
CMD ["node","server.js"]
