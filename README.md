# Firecrawl Local in Docker

[![build](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml/badge.svg)](https://github.com/jordanstrobing/firecrawl-local-docker/actions/workflows/build.yml)

Private web scraping for AI agents like Claude Code and Codex, on your own hardware.

[Firecrawl Local](https://docs.firecrawl.dev/quickstarts/firecrawl-local) is Firecrawl's open-source scraper: it turns web pages, PDFs and documents into clean markdown with the same code as Firecrawl's cloud service. This project packages it with a headless Chromium for JavaScript pages, as a locked-down Docker image for `amd64` and `arm64`. Thanks to the Firecrawl team for open-sourcing it.

## How it works

1. Your agent finds pages with its own web search.
2. It sends the URLs it wants to read to your Firecrawl Local server.
3. The server fetches and cleans them on your hardware and returns markdown.

By default nothing goes to Firecrawl, and there's no account, no credits and no rate limit.

## Setup

### 1. Run the server

On the machine that will host it, such as your computer, a home server or a Raspberry Pi. You need Docker with Compose, git, openssl and curl, in a Linux, macOS or WSL2 shell. It's tested on Linux with Docker Engine; Docker Desktop should work but isn't tested yet.

```bash
git clone https://github.com/jordanstrobing/firecrawl-local-docker && cd firecrawl-local-docker
(umask 077; echo "FIRECRAWL_LOCAL_TOKEN=$(openssl rand -hex 32)" > .env)
docker compose up -d
```

The second line generates the server's password into `.env`. Check that it's running:

```bash
curl -H "Authorization: Bearer $(sed -n 's/^FIRECRAWL_LOCAL_TOKEN=//p' .env)" http://127.0.0.1:3002/health
```

It should answer `{"status":"ok",…}`.

### 2. Reach it from your other devices

Skip this if your agents run on the same machine as the server.

The server only listens on `127.0.0.1`. With [Tailscale](https://tailscale.com) on the server and your devices, in the same tailnet, forward the port to the tailnet and tell the server its name, which `tailscale status` shows:

```bash
tailscale serve --bg --tcp 3002 tcp://127.0.0.1:3002
echo "FIRECRAWL_HOSTNAME=myserver" >> .env   # this machine's Tailscale name
docker compose up -d
```

Only devices your tailnet allows can connect, and it keeps working after a reboot. To check, run the health check above from another device, with `http://myserver:3002` instead of `http://127.0.0.1:3002`. Without Tailscale, see `FIRECRAWL_BIND_ADDRESS` under [Configuration](#configuration).

### 3. Connect your agents

On the machine where your agents run, with Node.js 22 or newer and your agents (such as Claude Code or Codex) already installed:

```bash
npx add-mcp firecrawl-mcp@3.40.0 --name firecrawl-local -g --env 'FIRECRAWL_API_URL=${FIRECRAWL_API_URL}' --env 'FIRECRAWL_API_KEY=${FIRECRAWL_API_KEY}'
npx skills add jordanstrobing/firecrawl-local-docker -g
```

Both commands ask which agents to set up: Claude Code, Codex, OpenCode, Cursor and [more](https://github.com/neon-solutions/add-mcp#supported-agents). They use two open standards, [MCP](https://modelcontextprotocol.io) and [Agent Skills](https://agentskills.io), both governed by the Linux Foundation's [Agentic AI Foundation](https://aaif.io).

- The first connects your agents to the server. The `${…}` placeholders make it ask for the values: enter the URL (`http://127.0.0.1:3002`, or `http://myserver:3002` from step 2) and the token from the server's `.env`.
- The second installs a [skill](skills/firecrawl-local/SKILL.md) that tells agents when to use Firecrawl rather than their built-in fetch tool, and how to keep its output small.

Start a new agent session and ask, for example, *Read https://example.com with Firecrawl and summarize it.*

**Optional:**

- To stop agents asking for approval each time they read a page, add `--auto-approve --approve-tool firecrawl_scrape --approve-tool firecrawl_map --approve-tool firecrawl_crawl --approve-tool firecrawl_check_crawl_status` to the first command (Claude Code and Codex). Agents can then open any URL without asking, so a page with hidden instructions could get one to send data out in a URL. Leave it off if your agents handle secrets.
- Claude Code can save long pages to a file and read only the part it needs, if `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY` are in the `env` section of `~/.claude/settings.json`.
- Firecrawl's SDKs take the same URL and token, for example `Firecrawl(api_url="http://myserver:3002", api_key="<token>")` in Python.

## What it can do

| | |
| --- | --- |
| Read web pages, PDFs and Office documents | On your server |
| Crawl a site, map its links, read a batch of URLs | On your server |
| Render JavaScript and take screenshots | On your server, in Chromium |
| Web search, Alexandria data, retrying pages that block you | Firecrawl Cloud, only if you turn it on with `FIRECRAWL_CLOUD` |
| AI extraction (`json`, `summary`) and browser actions | Firecrawl Cloud only |

## Configuration

Set these in the server's `.env`, then run `docker compose up -d` again.

| Variable | Default | |
| --- | --- | --- |
| `FIRECRAWL_LOCAL_TOKEN` | required | The password every request must send. |
| `FIRECRAWL_HOSTNAME` | `localhost` | The name your devices use for the server. Requests to any other name are refused; `localhost` and `127.0.0.1` always work. |
| `FIRECRAWL_BIND_ADDRESS` | `127.0.0.1` | The address to listen on, if you don't use `tailscale serve`. Traffic to it, including the token, isn't encrypted, so use it only on a network you trust. It must exist when Docker starts, so after a reboot its network has to come up before Docker. |
| `FIRECRAWL_CLOUD` | `off` | `search` sends web searches to Firecrawl Cloud. `auto` sends every request the server can't handle itself, such as Alexandria, agent and file uploads, and pages that block it. |
| `FIRECRAWL_API_KEY` | | Your Firecrawl key, for those cloud features. Not the same as the `FIRECRAWL_API_KEY` your agents use, which is this server's token. |

For [other Firecrawl Local settings](https://docs.firecrawl.dev/quickstarts/firecrawl-local#configuration), create `compose.override.yaml` next to `compose.yaml`. Compose merges it in automatically:

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

To update automatically, use an updater such as [Dockhand](https://dockhand.pro) or [What's Up Docker](https://github.com/getwud/wud), and prune old images now and then.

A new image is published within a day of a new Chromium or a Debian update to anything inside it, and three days after a new Firecrawl Local release, so a bad release can be pulled before it reaches you. `latest` is the newest build, `0.1.0` the newest build of that version, and tags like `0.1.0-202611182337` name a single build. To pin or roll back, set `image:` in `compose.override.yaml` to a digest, such as `ghcr.io/jordanstrobing/firecrawl-local-docker@sha256:…`, which no one can change.

Chromium fixes reach Debian, and this image, usually within a few days of Google's release. The [Debian security tracker](https://security-tracker.debian.org/tracker/source-package/chromium) shows the current status.

## Troubleshooting

| You see | Fix |
| --- | --- |
| `401` `UNAUTHORIZED` | The token is missing or doesn't match the server's `.env`. |
| `403` `HOST_NOT_ALLOWED` | The URL uses a name other than `localhost` or `FIRECRAWL_HOSTNAME`. Use that name, or change `FIRECRAWL_HOSTNAME`. |
| Agents try Firecrawl search or ask for credits | Another Firecrawl MCP server or skill is installed alongside this one. Remove it, or tell the agent to use `firecrawl-local`. |
| JavaScript pages fail with `No usable sandbox!` | The container is running without `seccomp_profile.json`. Start it with this repository's `compose.yaml`. In a UI such as Portainer or Unraid, deploy from this Git repository, or put `seccomp_profile.json` next to the compose file. |

## Resources

On a Raspberry Pi 5, the server idles at about 5 MB of memory and stays under 10 MB for ordinary pages. JavaScript pages and screenshots start Chromium: about 110 MB for one page and 140 MB for two at once. The image is about 240 MB to download and 520 MB on disk. Compose caps the server at 2 GiB of memory with no swap.

## Security

- **Keep it private.** Never publish the port to the internet; use `tailscale serve` or another private network.
- **Chromium keeps its sandbox.** [`seccomp_profile.json`](seccomp_profile.json) is Playwright's profile plus `chroot` inside Chromium's sandbox, without `io_uring`. The container runs read-only, as a non-root user, with no capabilities, and the tests check that nothing in it can `chroot` outside the sandbox. Chromium starts without the server's token in its environment.
- **Your network is off limits.** The server refuses to fetch localhost and private-network addresses, and always refuses link-local and cloud-metadata addresses, including after redirects. `FIRECRAWL_LOCAL_ALLOW_PRIVATE: "true"` in `compose.override.yaml` lifts the first rule; a page with hidden instructions could then steer an agent to your router or other services on your network.

Report vulnerabilities in the image privately, with **Report a vulnerability** on this repository's Security tab. Report vulnerabilities in Firecrawl Local itself to Firecrawl at help@firecrawl.com.

## How it's built

A [daily workflow](.github/workflows/build.yml) checks crates.io and Debian for updates. When something changed, it builds both architectures on native runners and runs the [smoke tests](test/smoke.sh) against the real `compose.yaml`. Only images that pass are published, after checking they're identical to the ones tested, and each comes with a build attestation. To check that an image was built by this repository's workflow from `main`:

```bash
gh attestation verify oci://ghcr.io/jordanstrobing/firecrawl-local-docker:latest --repo jordanstrobing/firecrawl-local-docker \
  --signer-workflow jordanstrobing/firecrawl-local-docker/.github/workflows/build.yml --source-ref refs/heads/main
```

To build and test it yourself on Linux, with Docker Compose 2.24.4 or newer, curl and jq:

```bash
docker build -t firecrawl-local .
test/smoke.sh firecrawl-local
```

## License

The packaging in this repository is [MIT](LICENSE), and `seccomp_profile.json` is Playwright's, under the [Apache-2.0](licenses/Apache-2.0.txt) license. The image contains Firecrawl Local under the [AGPL-3.0](licenses/AGPL-3.0.txt), with the exact source and every Rust dependency's license at `/usr/share/doc/firecrawl-local/`, and Chromium and Debian packages under their own licenses at `/usr/share/doc/<package>/copyright`. See [NOTICE](licenses/NOTICE).

This project is unofficial and not affiliated with Firecrawl. Report problems with Firecrawl Local itself [upstream](https://github.com/firecrawl/firecrawl/issues).
