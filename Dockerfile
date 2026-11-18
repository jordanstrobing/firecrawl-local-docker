# syntax=docker/dockerfile:1

# Empty means latest: the newest firecrawl-local on crates.io and the newest
# Chromium in Debian. CI passes exact versions so the labels match the contents.
ARG FIRECRAWL_LOCAL_VERSION=
ARG CHROMIUM_VERSION=

FROM rust:1-slim-trixie AS build
ARG FIRECRAWL_LOCAL_VERSION
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
# hadolint ignore=SC2086
RUN cargo install firecrawl-local ${FIRECRAWL_LOCAL_VERSION:+--version =$FIRECRAWL_LOCAL_VERSION} --locked --root /out

# AGPL-3.0 §6: ship the binary's exact source (the .crate, with its Cargo.lock),
# plus the license files of every crate used to build it.
RUN doc=/out/share/doc/firecrawl-local; \
    mkdir -p "$doc/third-party"; \
    cp "$CARGO_HOME"/registry/cache/*/firecrawl-local-*.crate "$doc/"; \
    for dir in "$CARGO_HOME"/registry/src/*/*/; do \
      name=$(basename "$dir"); \
      license=$(sed -n '/^license *= *"/{s/^license *= *"\(.*\)"/\1/p;q;}' "$dir/Cargo.toml"); \
      printf '%s\t%s\n' "$name" "${license:-see files}" >> "$doc/third-party/CRATES.tsv"; \
      find "$dir" -maxdepth 1 -type f \( -iname 'licen[cs]e*' -o -iname 'copying*' -o -iname 'notice*' -o -iname 'copyright*' \) \
        -exec sh -c 'mkdir -p "$1" && cp "$2" "$1/"' _ "$doc/third-party/$name" {} \; ; \
    done; \
    sort -o "$doc/third-party/CRATES.tsv" "$doc/third-party/CRATES.tsv"

FROM debian:trixie-slim AS runtime
ARG FIRECRAWL_LOCAL_VERSION
ARG CHROMIUM_VERSION
# Chromium's headless shell: Debian's full chromium package drags in GTK and,
# through it, systemd (about 155 MB more) and uses twice the memory per page.
# Only Chromium is pinned, so every rebuild picks up Debian's security fixes.
# curl is for the health check; tini reaps Chromium's orphaned processes.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      "chromium-headless-shell${CHROMIUM_VERSION:+=$CHROMIUM_VERSION}" \
      "chromium-common${CHROMIUM_VERSION:+=$CHROMIUM_VERSION}" \
      ca-certificates curl fonts-liberation tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 firecrawl \
 && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin firecrawl

COPY --from=build /out/bin/firecrawl-local /usr/local/bin/firecrawl-local
COPY --from=build /out/share/doc/firecrawl-local/ /usr/share/doc/firecrawl-local/
COPY licenses/AGPL-3.0.txt /usr/share/doc/firecrawl-local/LICENSE
COPY licenses/NOTICE /usr/share/doc/firecrawl-local/NOTICE
COPY LICENSE /usr/share/doc/firecrawl-local/packaging-LICENSE

LABEL org.opencontainers.image.title="Firecrawl Local (unofficial image)" \
      org.opencontainers.image.description="Firecrawl Local with Chromium. Not affiliated with Firecrawl." \
      org.opencontainers.image.source="https://github.com/jordanstrobing/firecrawl-local-docker" \
      org.opencontainers.image.version="${FIRECRAWL_LOCAL_VERSION}" \
      io.github.jordanstrobing.firecrawl-local-docker.chromium="${CHROMIUM_VERSION}"

# Firecrawl Local only looks for chromium/google-chrome. Point it at the real
# binary, not /usr/bin's sh wrapper, so signals reach Chromium directly.
ENV FIRECRAWL_CHROME_PATH=/usr/lib/chromium/chromium-headless-shell
USER 10001:10001
WORKDIR /home/firecrawl
EXPOSE 3002
# /health needs the token like every other route.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD ["sh", "-c", "curl -fsS -o /dev/null -H \"Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN\" http://127.0.0.1:3002/health"]
ENTRYPOINT ["/usr/bin/tini", "--", "firecrawl-local"]
CMD ["serve", "--host", "0.0.0.0"]
