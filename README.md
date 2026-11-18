# firecrawl-local-docker

[![build](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml/badge.svg)](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml)

[Firecrawl Local](https://docs.firecrawl.dev/quickstarts/firecrawl-local) with Debian Chromium Headless Shell for `linux/amd64` and `linux/arm64`.

```
ghcr.io/jordanstrobing/firecrawl-local-docker:latest
```

> **Unofficial image.** Report packaging problems here and Firecrawl Local bugs [upstream](https://github.com/firecrawl/firecrawl/issues).

Scrape pages and documents, map links, and crawl sites through the Firecrawl v2 API. Ordinary pages are fetched over HTTP; JavaScript pages and screenshots use Chromium with its sandbox on.

## Run it

You need Docker Engine with Compose v2, git and openssl, in a Linux, macOS or WSL2 shell. The image is tested on Linux with Docker Engine on amd64 and arm64; Docker Desktop and Podman are untested.

```bash
git clone https://github.com/jordanstrobing/firecrawl-local-docker && cd firecrawl-local-docker
(umask 077; echo "FIRECRAWL_LOCAL_TOKEN=$(openssl rand -hex 32)" > .env)
docker compose up -d
```

Check that it answers:

```bash
curl -H "Authorization: Bearer $(sed -n 's/^FIRECRAWL_LOCAL_TOKEN=//p' .env)" http://127.0.0.1:3002/health
```

A `401` means the token is missing or wrong. A `403` means the request was addressed to a name other than `localhost` or `FIRECRAWL_HOSTNAME`.

If you deploy through a UI such as Portainer or Unraid, point it at this Git repository, or put `seccomp_profile.json` next to the compose file: Compose reads it from there.

It listens on `127.0.0.1:3002` only.

To use it from your other devices over [Tailscale](https://tailscale.com), keep it on loopback and let Tailscale forward the port. Only your tailnet can reach it, and it keeps working after a reboot whichever of Docker and Tailscale starts first:

```bash
tailscale serve --bg --tcp 3002 tcp://127.0.0.1:3002
echo "FIRECRAWL_HOSTNAME=myserver" >> .env   # this machine's Tailscale name
docker compose up -d
```

On other networks, set `FIRECRAWL_BIND_ADDRESS` in `.env` to the address to listen on, and `FIRECRAWL_HOSTNAME` to the name clients use. Docker can't bind an address that doesn't exist yet when it starts, so after a reboot this needs the interface to come up before Docker.

## Connect Claude Code or Codex

On the agent's machine (Node.js 22 or newer), with the token from `.env`:

```bash
claude mcp add firecrawl-local -e FIRECRAWL_API_URL=http://myserver:3002 -e FIRECRAWL_API_KEY=<token> -- npx -y firecrawl-mcp
codex mcp add firecrawl-local --env FIRECRAWL_API_URL=http://myserver:3002 --env FIRECRAWL_API_KEY=<token> -- npx -y firecrawl-mcp
```

Let the agent's own web search find URLs, and Firecrawl Local fetch them. With `FIRECRAWL_CLOUD=off`, the default, pages are fetched from your machine and nothing is sent to Firecrawl.

Firecrawl SDKs take the same two values, for example `Firecrawl(api_url="http://myserver:3002", api_key="<token>")` in Python.

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

Set these in `.env`:

| Variable | Default | |
| --- | --- | --- |
| `FIRECRAWL_LOCAL_TOKEN` | required | Bearer token for every request, including `/health`. |
| `FIRECRAWL_BIND_ADDRESS` | `127.0.0.1` | Host address the port is published on. Not needed with `tailscale serve`. |
| `FIRECRAWL_HOSTNAME` | `localhost` | Name clients use to reach the server. Requests addressed to any other name are refused. |
| `FIRECRAWL_CLOUD` | `off` | `search` sends search to Firecrawl Cloud; `auto` also sends Alexandria and pages that block you. |
| `FIRECRAWL_API_KEY` | | Firecrawl key for those cloud features. |

Other [Firecrawl Local settings](https://docs.firecrawl.dev/quickstarts/firecrawl-local#configuration) go under `environment:` in `compose.yaml`. Keep the container port at 3002, which the health check uses.

## Security

- Keep the token private, and never publish the port to the internet. Reach it through `tailscale serve` or another private network.
- Compose uses [a seccomp profile](seccomp_profile.json) based on Playwright's. It lets Chromium create its sandbox's user namespace and `chroot` inside it. With every Docker capability dropped, nothing can `chroot` in the container itself; the smoke tests check this.
- `serve` refuses localhost and private-network targets unless `FIRECRAWL_LOCAL_ALLOW_PRIVATE` is set (only do that if every caller is trusted), and always refuses link-local and cloud-metadata addresses, including after redirects.
- The compose file runs the container read-only, as a non-root user, with no capabilities and `no-new-privileges`.

Report vulnerabilities in the image privately, with **Report a vulnerability** on this repository's Security tab. Report vulnerabilities in Firecrawl Local itself to Firecrawl at help@firecrawl.com, not in a public issue.

## Resources

On a Raspberry Pi 5, the service idles at about 5 MB of memory and stays under 10 MB for ordinary pages. The first JavaScript page or screenshot starts Chromium: about 110 MB for one page, about 140 MB for two at once, and about 80 MB once idle again. The image is about 270 MB to download and 1 GB on disk.

Chromium's profiles and temporary files live in a 512 MiB in-memory `/tmp`. The service is capped at 2 GiB of memory with no swap, and keeps three 10 MB log files. The named volume holds only Firecrawl Local's install ID. Crawl and batch results stay in memory for up to an hour, until the next job is created or looked up.

## Tags and updates

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build. |
| `<version>`, such as `0.1.1` | Newest build of that Firecrawl Local version. |
| `<version>-<YYYYMMDDHHMM>` | One build, never reused. Pin this or its digest to stay on a known image. |

A [daily workflow](.github/workflows/build.yml) publishes a new image when crates.io has a new Firecrawl Local, when Debian has a new Chromium for either architecture, or when Debian has updates for any other package in the image. Both architectures are built on native runners and must pass the [smoke tests](test/smoke.sh), which run the real `compose.yaml`. The release checks that the pushed images are the ones tested and attests them before `latest` moves.

Chromium security fixes reach Debian, and so this image, usually within a few days of Google's release. The [Debian security tracker](https://security-tracker.debian.org/tracker/source-package/chromium) shows the current status.

To update, run `docker compose pull && docker compose up -d`, or follow `latest` with a tool such as [Dockhand](https://dockhand.pro) or [What's Up Docker](https://github.com/getwud/wud). Each update leaves the previous image behind, so prune old images now and then. To roll back, set `image:` in `compose.yaml` to a `<version>-<YYYYMMDDHHMM>` tag.

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
