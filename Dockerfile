# Firecrawl Local (https://github.com/firecrawl/firecrawl/tree/main/apps/local)
# packaged with Chromium so JavaScript pages render inside the container.
#
# Both versions are pinned so each image says exactly what it contains.
# The build workflow fills them in from crates.io and Debian's security repo.

ARG FIRECRAWL_LOCAL_VERSION=0.1.0
ARG CHROMIUM_VERSION=

FROM rust:1-slim-trixie AS build
ARG FIRECRAWL_LOCAL_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN cargo install firecrawl-local --version "${FIRECRAWL_LOCAL_VERSION}" --locked --root /out

FROM debian:trixie-slim AS runtime
ARG FIRECRAWL_LOCAL_VERSION
ARG CHROMIUM_VERSION
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      "chromium${CHROMIUM_VERSION:+=$CHROMIUM_VERSION}" \
      fonts-liberation fonts-noto-color-emoji ca-certificates curl tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 firecrawl
COPY --from=build /out/bin/firecrawl-local /usr/local/bin/firecrawl-local
LABEL org.opencontainers.image.title="firecrawl-local" \
      org.opencontainers.image.description="Firecrawl Local with Chromium, built from crates.io" \
      org.opencontainers.image.version="${FIRECRAWL_LOCAL_VERSION}" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      dev.firecrawl-local.chromium-version="${CHROMIUM_VERSION}"

USER firecrawl
ENV FIRECRAWL_CHROME_PATH=/usr/bin/chromium \
    FIRECRAWL_LOCAL_HOME=/home/firecrawl/.firecrawl-local
EXPOSE 3002
HEALTHCHECK --interval=60s --timeout=5s --start-period=20s \
  CMD curl -fsS http://127.0.0.1:3002/health || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "firecrawl-local"]
# serve needs FIRECRAWL_LOCAL_TOKEN when it listens on 0.0.0.0
CMD ["serve", "--host", "0.0.0.0", "--port", "3002"]
