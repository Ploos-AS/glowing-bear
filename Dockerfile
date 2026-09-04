# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:22-alpine
ARG NGINX_IMAGE=nginx:1.27-alpine

FROM ${NODE_IMAGE} AS build
ARG GLOWING_BEAR_REF=master
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch "${GLOWING_BEAR_REF}" https://github.com/glowing-bear/glowing-bear.git .
RUN npm ci && npm run build

FROM ${NGINX_IMAGE} AS runtime
LABEL org.opencontainers.image.title="Glowing Bear" \
      org.opencontainers.image.description="Minimal container image for the Glowing Bear WeeChat web client" \
      org.opencontainers.image.source="https://github.com/Ploos-AS/glowing-bear" \
      org.opencontainers.image.licenses="GPL-3.0-only"

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /src/build/ /usr/share/nginx/html/

RUN mkdir -p /tmp/nginx/client_temp /tmp/nginx/proxy_temp /tmp/nginx/fastcgi_temp /tmp/nginx/uwsgi_temp /tmp/nginx/scgi_temp \
    && chown -R nginx:nginx /tmp/nginx /usr/share/nginx/html

USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
