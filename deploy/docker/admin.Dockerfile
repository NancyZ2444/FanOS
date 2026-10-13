FROM node:22-alpine AS build
WORKDIR /srv/admin
COPY apps/admin/package*.json ./
RUN npm ci
COPY apps/admin/ ./
RUN npm run build

FROM nginx:alpine
COPY deploy/nginx/admin.conf /etc/nginx/conf.d/default.conf
COPY --from=build /srv/admin/dist /usr/share/nginx/html
EXPOSE 80
