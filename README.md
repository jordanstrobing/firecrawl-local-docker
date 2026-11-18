# firecrawl-local-docker

[![build](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml/badge.svg)](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml)

[Firecrawl Local](https://docs.firecrawl.dev/quickstarts/firecrawl-local) with Debian Chromium Headless Shell for `linux/amd64` and `linux/arm64`.

```
ghcr.io/jordanstrobing/firecrawl-local-docker:latest
```

> **Unofficial image.** Report packaging problems here and Firecrawl Local bugs [upstream](https://github.com/firecrawl/firecrawl/issues).

Scrape pages and documents, map links, and crawl a site through the Firecrawl
v2 API. Ordinary scrapes use HTTP. JavaScript rendering and screenshots use
Chromium with its sandbox enabled.

## Run it

```bash
curl -fsSLO https://raw.githubusercontent.com/jordanstrobing/firecrawl-local-docker/main/compose.yaml
curl -fsSLO https://raw.githubusercontent.com/jordanstrobing/firecrawl-local-docker/main/seccomp_profile.json
(
  umask 077
  set -C
  printf 'FIRECRAWL_LOCAL_TOKEN=%s\n' "$(openssl rand -hex 32)" > .env
)
docker compose up -d --wait

source .env
curl -fsS http://127.0.0.1:3002/v2/scrape \
  -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}'
```

Compose binds to loopback by default. For another machine on your tailnet, set
`FIRECRAWL_BIND_ADDRESS` to the Docker host's Tailscale IP in `.env`. Set
`FIRECRAWL_LOCAL_ALLOWED_HOSTS` to the address or DNS name the clients will use,
then run `docker compose up -d` again.

## Connect Codex or Claude Code

Run these commands on the machine running the agent with Node.js 22 or newer.
Use the server's tailnet URL when it runs on a different machine. Paste the
bearer token from the server's `.env` into the hidden prompt.

```bash
FIRECRAWL_URL=http://127.0.0.1:3002
printf 'Firecrawl token: ' >&2
read -rs FIRECRAWL_LOCAL_TOKEN
printf '\n'
```

Codex:

```bash
codex mcp add firecrawl-local \
  --env "FIRECRAWL_API_URL=$FIRECRAWL_URL" \
  --env "FIRECRAWL_API_KEY=$FIRECRAWL_LOCAL_TOKEN" \
  -- npx -y firecrawl-mcp
```

Claude Code:

```bash
claude mcp add --scope user firecrawl-local \
  -e "FIRECRAWL_API_URL=$FIRECRAWL_URL" \
  -e "FIRECRAWL_API_KEY=$FIRECRAWL_LOCAL_TOKEN" \
  -- npx -y firecrawl-mcp
```

Use your normal web search to discover sources. Ask for `firecrawl-local` to
read documents, scrape selected URLs, or crawl a section of a site. Start
with a small page limit and narrow the path for documentation crawls.

Any Firecrawl SDK takes the same two values:

```python
from firecrawl import Firecrawl

app = Firecrawl(api_url="http://myserver:3002", api_key="<FIRECRAWL_LOCAL_TOKEN>")
print(app.scrape("https://example.com").markdown)
```

## What runs where

| Feature | Runs on | Notes |
| --- | --- | --- |
| Scrape, crawl, map, batch scrape | Container | Local requests use no Firecrawl credits |
| JavaScript pages, screenshots | Container (Chromium) | |
| PDFs, Office documents | Container | |
| Search | Firecrawl Cloud | Enable with `FIRECRAWL_CLOUD=search` or `auto` |
| Alexandria data providers | Firecrawl Cloud | Set `FIRECRAWL_CLOUD=auto` and `FIRECRAWL_API_KEY` |
| Fallback for blocked pages | Firecrawl Cloud | With `FIRECRAWL_CLOUD=auto`, a cloud result carries `"source": "firecrawl-cloud"` |
| `json` and `summary` formats, browser `actions` | Not available locally | |

Requests sent on to Firecrawl Cloud use the container's own `FIRECRAWL_API_KEY`, never the caller's token.

## Configuration

| Variable | Default | Effect |
| --- | --- | --- |
| `FIRECRAWL_BIND_ADDRESS` | `127.0.0.1` | Host address where Compose publishes port 3002. |
| `FIRECRAWL_LOCAL_TOKEN` | required | Bearer token for every request, including `/health`. |
| `FIRECRAWL_LOCAL_ALLOWED_HOSTS` | | Comma-separated host names clients may address, for example `myserver,192.168.1.10`. `localhost` and `127.0.0.1` always work. Added by this image: Firecrawl Local only takes `--allowed-host` flags. |
| `FIRECRAWL_API_KEY` | | Firecrawl key for search, Alexandria and the blocked-page fallback. |
| `FIRECRAWL_CLOUD` | `off` in Compose | `search` enables hosted search. `auto` also enables the blocked-page fallback and Alexandria. |
| `FIRECRAWL_LOCAL_BROWSER` | `auto` | Launch Chromium when needed. Use `never` for HTTP-only or `always` to render every scrape. |
| `FIRECRAWL_LOCAL_SCROLL` | off | `1` scrolls pages before reading them, for lazy-loaded content. Firecrawl Local treats any value, even `0`, as on; this image treats empty, `0`, `false`, `no` and `off` as off. |
| `FIRECRAWL_LOCAL_ALLOW_PRIVATE` | off | Lets callers scrape localhost and private addresses. Leave off unless every caller is trusted. |

To pass other upstream settings to the container, add them under the service’s `environment` in Compose. See the [Firecrawl Local docs](https://docs.firecrawl.dev/quickstarts/firecrawl-local#configuration). Keep the container's port at 3002 (the health check uses it) and remap it with `ports:` instead.

The image starts `serve` by default. For a one-off scrape, pass
`scrape https://example.com --markdown` to `docker run` and apply the same
seccomp profile if the scrape uses Chromium.

## Security

- Keep the token private and bind to loopback or a trusted VPN interface such as Tailscale.
- Compose uses [a seccomp profile](seccomp_profile.json) based on Playwright's
  profile. It permits Chromium to create its user namespace and call `chroot`
  inside it. The container drops all Docker capabilities, so the process cannot
  chroot in the container's parent namespace.
- `serve` refuses localhost and private-network targets unless `FIRECRAWL_LOCAL_ALLOW_PRIVATE` is set, and always refuses link-local and cloud-metadata addresses, including after redirects.
- The compose file runs the container read-only, as a non-root user, with no capabilities and `no-new-privileges`.

## Tags and updates

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build. |
| `<version>`, such as `0.1.1` | Newest build of that Firecrawl Local version. |
| `<version>-<YYYYMMDD>-<run>-<attempt>` | One build, never reused. Pin this or its digest to stay on a known image. |

The [daily workflow](.github/workflows/build.yml) checks for new Firecrawl
Local and Chromium versions. Each architecture uses matching versions of
`chromium-headless-shell` and `chromium-common` from Debian. Check the
[Debian security tracker](https://security-tracker.debian.org/tracker/source-package/chromium)
for patch status. Monday builds also refresh other Debian packages. Native runners test the actual Compose service, and
the release verifies the tested image config digests before updating the
floating tags.

To update automatically, follow `latest` with a tool such as [Dockhand](https://dockhand.pro) or [What's Up Docker](https://github.com/getwud/wud).

## Verify an image

```bash
gh attestation verify oci://ghcr.io/jordanstrobing/firecrawl-local-docker:latest \
  --repo jordanstrobing/firecrawl-local-docker
docker buildx imagetools inspect ghcr.io/jordanstrobing/firecrawl-local-docker:latest --format '{{json .SBOM}}'
```

## Build it yourself

```bash
docker build -t firecrawl-local .   # newest Firecrawl Local and Chromium
test/smoke.sh firecrawl-local       # Docker Compose 2.24.4+, curl and jq
```

Pass `--build-arg FIRECRAWL_LOCAL_VERSION=0.1.0` or `--build-arg CHROMIUM_VERSION=<Debian version>` to pin either.

## Licenses

The packaging code uses the [MIT License](LICENSE). The image also contains:

- **Firecrawl Local, [AGPL-3.0](licenses/AGPL-3.0.txt).** The exact source each image was built from (the crate, including `Cargo.lock`) and the license of every Rust dependency are inside it at `/usr/share/doc/firecrawl-local/`.
- **Chromium and Debian packages**, under their own licenses at `/usr/share/doc/<package>/copyright`.
- **Playwright's seccomp profile, [Apache-2.0](licenses/Apache-2.0.txt).**

Details in [licenses/NOTICE](licenses/NOTICE). Firecrawl Local identifies itself in its User-Agent and follows `robots.txt` when crawling.
