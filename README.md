# Firecrawl Local in Docker

[![build](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml/badge.svg)](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml)

Private web scraping for your AI agents, on your own machine.

This is [Firecrawl Local](https://docs.firecrawl.dev/quickstarts/firecrawl-local), Firecrawl's open-source scraper, packaged with a headless Chromium as a ready-to-run image for `amd64` and `arm64`. It rebuilds itself whenever Firecrawl Local, Chromium or Debian publish an update.

```
ghcr.io/jordanstrobing/firecrawl-local-docker:latest
```

## Why

We love Firecrawl. Turning messy web pages into clean markdown is the hard part of giving an agent the web, and Firecrawl does it better than anything else we've used. When Firecrawl open-sourced Firecrawl Local, with the same page-cleaning code their cloud runs, it became possible to do that on a laptop or a Raspberry Pi. This project makes it one `docker compose up`.

It's unofficial: built by fans, not by Firecrawl. Report problems with the image here, and problems with Firecrawl Local [upstream](https://github.com/firecrawl/firecrawl/issues).

## How it works

1. Your agent, such as Claude Code or Codex, finds pages with its own web search.
2. It hands the URLs it wants to read to Firecrawl Local.
3. Firecrawl Local fetches and cleans them on your machine, rendering JavaScript in Chromium when a page needs it, and returns markdown.

Nothing is sent to Firecrawl unless you turn their cloud features on. Scraping locally needs no account and has no credits or rate limits.

## Quick start

You need Docker with Compose v2, git and openssl, in a Linux, macOS or WSL2 shell.

**1. Start it**

```bash
git clone https://github.com/jordanstrobing/firecrawl-local-docker && cd firecrawl-local-docker
(umask 077; echo "FIRECRAWL_LOCAL_TOKEN=$(openssl rand -hex 32)" > .env)
docker compose up -d
```

The second line creates `.env` with a random token: the password for your server.

**2. Check it**

```bash
curl -H "Authorization: Bearer $(sed -n 's/^FIRECRAWL_LOCAL_TOKEN=//p' .env)" http://127.0.0.1:3002/health
```

You should see `{"status":"ok","engine":"firecrawl-local","version":"…"}`.

**3. Connect your agent**

On the machine running the agent (with Node.js 22 or newer), replace `<token>` with the token from `.env`:

```bash
# Claude Code
claude mcp add firecrawl-local -e FIRECRAWL_API_URL=http://127.0.0.1:3002 -e FIRECRAWL_API_KEY=<token> -- npx -y firecrawl-mcp

# Codex
codex mcp add firecrawl-local --env FIRECRAWL_API_URL=http://127.0.0.1:3002 --env FIRECRAWL_API_KEY=<token> -- npx -y firecrawl-mcp
```

Firecrawl's SDKs take the same two values, for example `Firecrawl(api_url="http://127.0.0.1:3002", api_key="<token>")` in Python.

**4. Tell your agent when to use it**

Agents tend to stick with their built-in fetch tool, which can't render JavaScript and often summarizes pages. Add this to your `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex):

```markdown
To read web pages, use the firecrawl-local tools: firecrawl_scrape for a page,
firecrawl_map to find the right page on a site first. Use curl for APIs and raw files.
X posts need a login, so read https://publish.twitter.com/oembed?url=<post URL> instead.
```

In Claude Code, you can also skip the approval prompt for these tools by adding `mcp__firecrawl-local__firecrawl_scrape`, `mcp__firecrawl-local__firecrawl_map`, `mcp__firecrawl-local__firecrawl_crawl` and `mcp__firecrawl-local__firecrawl_check_crawl_status` to `permissions.allow` in your settings.

## Use it from other devices

The server listens on `127.0.0.1` only. To reach it from your other devices with [Tailscale](https://tailscale.com), run this on the server:

```bash
tailscale serve --bg --tcp 3002 tcp://127.0.0.1:3002
echo "FIRECRAWL_HOSTNAME=myserver" >> .env   # the server's Tailscale name
docker compose up -d
```

Then use `http://myserver:3002` as the URL in step 3. Only devices on your tailnet can connect, and it keeps working after a reboot.

Not using Tailscale? Set `FIRECRAWL_BIND_ADDRESS` in `.env` to an address your devices can reach, along with `FIRECRAWL_HOSTNAME`. That address has to exist when Docker starts, so after a reboot its network must come up before Docker.

## What it can do

| | |
| --- | --- |
| Scrape web pages, PDFs and Office documents | On your machine |
| Crawl a site, map its links, scrape a batch of URLs | On your machine |
| Render JavaScript and take screenshots | On your machine, in Chromium |
| Web search, Alexandria data providers, retrying pages that block you | Firecrawl Cloud, off unless you set `FIRECRAWL_CLOUD` |
| AI extraction (`json`, `summary` formats) and browser actions | Firecrawl Cloud only |

## Configuration

Set these in `.env`, then run `docker compose up -d` again.

| Variable | Default | |
| --- | --- | --- |
| `FIRECRAWL_LOCAL_TOKEN` | required | The password every request must send, including `/health`. |
| `FIRECRAWL_HOSTNAME` | `localhost` | The name your devices use for the server. Requests to any other name are refused. |
| `FIRECRAWL_BIND_ADDRESS` | `127.0.0.1` | The address the port is published on. Not needed with `tailscale serve`. |
| `FIRECRAWL_CLOUD` | `off` | `search` sends web search to Firecrawl Cloud. `auto` also sends Alexandria and pages that block you. |
| `FIRECRAWL_API_KEY` | | Your Firecrawl key, for the cloud features. Cloud requests use this key, never your token. |

For [other Firecrawl Local settings](https://docs.firecrawl.dev/quickstarts/firecrawl-local#configuration), create a `compose.override.yaml` next to `compose.yaml`. Compose merges it in automatically:

```yaml
services:
  firecrawl-local:
    environment:
      FIRECRAWL_LOCAL_SCROLL: "1"
```

## Updating

```bash
docker compose pull && docker compose up -d
```

To update automatically, follow `latest` with an updater such as [Dockhand](https://dockhand.pro) or [What's Up Docker](https://github.com/getwud/wud). Each update leaves the previous image behind, so prune old images now and then.

| Tag | |
| --- | --- |
| `latest` | The newest build |
| `0.1.0`, `0.1.1`, … | The newest build of that Firecrawl Local version |
| `0.1.0-202611182337` | One exact build that never changes. Set it as `image:` in `compose.override.yaml` to pin or roll back. |

A new image is published within a day of a new Firecrawl Local, a new Chromium, or a Debian update to anything inside the image. Chromium security fixes usually reach Debian within a few days of Google's release; the [Debian security tracker](https://security-tracker.debian.org/tracker/source-package/chromium) has the current status.

## Troubleshooting

| You see | What to do |
| --- | --- |
| `401` `UNAUTHORIZED` | The token is missing or doesn't match the one in `.env`. |
| `403` `HOST_NOT_ALLOWED` | The URL uses a name other than `localhost` or `FIRECRAWL_HOSTNAME`. Use that name, or set `FIRECRAWL_HOSTNAME` to the one you use. |
| JavaScript pages fail with `No usable sandbox!` | The container is running without `seccomp_profile.json`. Start it with this repository's `compose.yaml`. In a UI such as Portainer or Unraid, deploy from this Git repository, or put `seccomp_profile.json` next to the compose file. |

## Resources

Measured on a Raspberry Pi 5: the service idles at about 5 MB of memory and stays under 10 MB for ordinary pages. The first JavaScript page or screenshot starts Chromium, at about 110 MB for one page, 140 MB for two at once, and 80 MB once idle again. The image is about 200 MB to download and 470 MB unpacked.

Compose caps the service at 2 GiB of memory with no swap, 512 MiB of temporary files and three 10 MB log files.

## Security

- **Keep it private.** Never publish the port to the internet: keep it on `127.0.0.1`, behind `tailscale serve` or another private network.
- **Chromium keeps its sandbox.** [`seccomp_profile.json`](seccomp_profile.json) is Playwright's profile for Chromium, plus `chroot` inside Chromium's sandbox. The container runs read-only, as a non-root user, with no capabilities, and the tests check that nothing in it can `chroot` outside the sandbox.
- **Private addresses are off limits.** Firecrawl Local refuses to fetch localhost and private-network addresses unless you set `FIRECRAWL_LOCAL_ALLOW_PRIVATE`, and always refuses link-local and cloud-metadata addresses, including after redirects.

Report vulnerabilities in the image privately with **Report a vulnerability** on this repository's Security tab. Report vulnerabilities in Firecrawl Local itself to Firecrawl at help@firecrawl.com.

## How it's built

A [daily workflow](.github/workflows/build.yml) checks crates.io and Debian for updates. When something changed, it builds both architectures on native runners and runs the [smoke tests](test/smoke.sh) against the real `compose.yaml`, covering the token, the hostname check, HTML, PDF, JavaScript, screenshots, map and crawl. Only images that pass are published, after checking they are identical to the ones tested, and each one gets a build attestation:

```bash
gh attestation verify oci://ghcr.io/jordanstrobing/firecrawl-local-docker:latest --repo jordanstrobing/firecrawl-local-docker
```

To build and test it yourself on Linux, with Docker Compose 2.24.4 or newer, curl and jq:

```bash
docker build -t firecrawl-local .
test/smoke.sh firecrawl-local
```

## License

This repository's packaging is [MIT](LICENSE). The image also contains:

- **Firecrawl Local**, under the [AGPL-3.0](licenses/AGPL-3.0.txt). The exact source each image was built from, and every Rust dependency's license, are inside it at `/usr/share/doc/firecrawl-local/`.
- **Chromium and Debian packages**, each under its own license at `/usr/share/doc/<package>/copyright`.
- **Playwright's seccomp profile**, under the [Apache-2.0](licenses/Apache-2.0.txt) license.

Details are in [NOTICE](licenses/NOTICE). Firecrawl Local identifies itself in its User-Agent and follows `robots.txt` when crawling.
