FROM rust:1-slim-trixie AS build
# Empty means latest. CI passes exact versions so the labels match the contents.
ARG FIRECRAWL_LOCAL_VERSION
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
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
# It pulls in the matching chromium-common. Only Chromium is pinned, so every
# rebuild picks up Debian's security fixes.
# curl is for the health check; tini reaps Chromium's orphaned processes.
# The fonts let screenshots show non-Latin scripts, CJK and emoji instead of
# empty boxes (about 70 MB); page text doesn't depend on them.
# Skip what a headless container never loads (about 220 MB): Mesa's GPU driver
# with LLVM and Z3 (libgbm only loads it when a GPU device exists), Vulkan's
# debug and mock layers, and the desktop browser's resources and locales.
# hadolint ignore=DL3008
RUN printf 'path-exclude=%s\n' '/usr/lib/*/libLLVM*' '/usr/lib/*/libgallium*' '/usr/lib/*/libz3.so*' \
      '/usr/lib/chromium/libVk*' '/usr/lib/chromium/resources.pak' '/usr/lib/chromium/chrome_*_percent.pak' \
      '/usr/lib/chromium/locales/*' > /etc/dpkg/dpkg.cfg.d/headless \
 && apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      "chromium-headless-shell${CHROMIUM_VERSION:+=$CHROMIUM_VERSION}" \
      ca-certificates curl tini \
      fonts-liberation fonts-noto-core fonts-noto-color-emoji fonts-wqy-zenhei \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 firecrawl \
 && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin firecrawl

COPY --from=build /out/bin/firecrawl-local /usr/local/bin/firecrawl-local
COPY --from=build /out/share/doc/firecrawl-local/ /usr/share/doc/firecrawl-local/
COPY licenses/AGPL-3.0.txt /usr/share/doc/firecrawl-local/LICENSE

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
HEALTHCHECK --timeout=5s --start-period=15s \
  CMD ["sh", "-c", "curl -fsS -o /dev/null -H \"Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN\" http://127.0.0.1:3002/health"]
ENTRYPOINT ["/usr/bin/tini", "--", "firecrawl-local"]
CMD ["serve", "--host", "0.0.0.0"]
