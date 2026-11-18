# firecrawl-local-docker

An arm64 Docker image of [Firecrawl Local](https://github.com/firecrawl/firecrawl/tree/main/apps/local), with Chromium for JavaScript pages. Firecrawl publishes no image, so this repo builds one.

```
ghcr.io/jordanstrobing/firecrawl-local-docker:latest
ghcr.io/jordanstrobing/firecrawl-local-docker:<version>
```

## How it updates

A GitHub Actions workflow runs daily on a native arm64 runner:

- It rebuilds when crates.io has a new `firecrawl-local` version **or** Debian 13 has a new Chromium. Both versions are pinned in the image's labels, which is how it tells.
- Every Monday it rebuilds anyway, so the rest of the Debian packages stay patched.
- A build is pushed (`:<version>` and `:latest`) only after it scrapes a static page and a JavaScript-only page inside the container.

Run it by hand from the Actions tab (`force` rebuilds the current version).

## Running it

`serve` requires a token when it listens on anything but loopback. Chromium keeps its sandbox, which needs a seccomp profile that allows `clone`, `setns` and `unshare` ([Playwright's](https://github.com/microsoft/playwright/blob/main/utils/docker/seccomp_profile.json)); don't use `seccomp=unconfined`.

```yaml
services:
  firecrawl-local:
    image: ghcr.io/jordanstrobing/firecrawl-local-docker:latest
    restart: unless-stopped
    ports: ["3002:3002"]
    environment:
      FIRECRAWL_LOCAL_TOKEN: ${FIRECRAWL_LOCAL_TOKEN}
    security_opt:
      - seccomp=./seccomp_profile.json
```
