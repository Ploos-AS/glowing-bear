# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:22-alpine
ARG NGINX_IMAGE=nginx:1.27-alpine

FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS build
ARG GLOWING_BEAR_VERSION=0.10.0
ARG GLOWING_BEAR_REF=b53e42f584bd8165287cee5f680e23ffa05198b7
RUN apk add --no-cache git
WORKDIR /src
RUN git init . \
    && git remote add origin https://github.com/glowing-bear/glowing-bear.git \
    && git fetch --depth 1 origin "${GLOWING_BEAR_REF}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(node -p "require('./package.json').version")" = "${GLOWING_BEAR_VERSION}"
RUN npm ci && npm run build

FROM ${NGINX_IMAGE} AS runtime
ARG GLOWING_BEAR_VERSION=0.10.0
ARG GLOWING_BEAR_REF=b53e42f584bd8165287cee5f680e23ffa05198b7
LABEL org.opencontainers.image.title="Glowing Bear" \
      org.opencontainers.image.description="Minimal container image for the Glowing Bear WeeChat web client" \
      org.opencontainers.image.source="https://github.com/Ploos-AS/glowing-bear" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      io.github.ploos-as.upstream.source="https://github.com/glowing-bear/glowing-bear" \
      io.github.ploos-as.upstream.version="${GLOWING_BEAR_VERSION}" \
      io.github.ploos-as.upstream.revision="${GLOWING_BEAR_REF}"

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /src/build/ /usr/share/nginx/html/

RUN chown -R nginx:nginx /usr/share/nginx/html

USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["sh", "-c", "mkdir -p /tmp/nginx/client_temp /tmp/nginx/proxy_temp /tmp/nginx/fastcgi_temp /tmp/nginx/uwsgi_temp /tmp/nginx/scgi_temp && exec nginx -g 'daemon off;'"]
