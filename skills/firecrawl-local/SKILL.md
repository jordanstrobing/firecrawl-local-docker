---
name: firecrawl-local
description: Read web pages, PDFs and documentation sites through a self-hosted Firecrawl Local server (the firecrawl-local MCP tools). Use it whenever a task needs the content of a URL, to find the right page on a site, or to collect a section of docs.
license: MIT
compatibility: Needs the firecrawl-local MCP server, connected to a Firecrawl Local server (https://github.com/jordanstrobing/firecrawl-local-docker).
---

# Reading the web with Firecrawl Local

The `firecrawl-local` MCP server fetches pages on the user's own server and returns clean markdown of the main content. With its default settings nothing is sent to a third party, and there are no credits or rate limits.

The server's own instructions describe Firecrawl's cloud service. Locally, use `firecrawl_scrape`, `firecrawl_map`, `firecrawl_crawl` and `firecrawl_check_crawl_status`. The other Firecrawl tools (search, agent, Alexandria, research, developer and government search) only work if the server's owner has enabled Firecrawl Cloud; if one returns an error, don't retry it.

## Which tool

- **A known URL:** `firecrawl_scrape` with `formats: ["markdown"]`. It handles JavaScript-heavy pages and PDFs, which a plain fetch tool can't.
- **A site, but not the page:** `firecrawl_map` lists the site's URLs. Pick the one page you need and scrape only that, instead of scraping several pages to find it.
- **A section of a site:** `firecrawl_crawl` with a small `limit` (5 to 10) and `includePaths` for the section, then `firecrawl_check_crawl_status` until it completes.
- **APIs, JSON endpoints and raw files** (for example `raw.githubusercontent.com`): use `curl` or a plain fetch. Firecrawl is for web pages.
- **Finding pages:** use your own web search, then read the results with Firecrawl.

## Keep output small

- Scrapes return only the main content by default. To narrow further, pass `includeTags` (such as `["article"]` or `["main"]`) or `excludeTags`.
- For a slow page that renders late, add `waitFor` in milliseconds.
- AI extraction (`json`, `summary` formats) and browser `actions` aren't available locally either.

## Long pages: save to a file

If `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY` are set in your shell, fetch long pages (full documentation pages, READMEs, long articles) to a file and read only the part you need, instead of loading the whole page into context:

```bash
page=$(mktemp)
curl -sS "$FIRECRAWL_API_URL/v2/scrape" -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
  -H 'Content-Type: application/json' -d '{"url":"https://example.com/docs","formats":["markdown"]}' \
  | jq -er '.data.markdown // error(.error // "no markdown")' > "$page" \
  && grep -n '^#' "$page"   # the page's outline with line numbers
```

Then read just the lines of the section you need from `$page`. If the command fails, it prints the reason instead. If the variables aren't set or your shell can't reach the network (Codex's sandbox blocks it by default), use the MCP tools.

## Errors

- `401 UNAUTHORIZED`: the MCP server's `FIRECRAWL_API_KEY` doesn't match the server's token.
- `403 HOST_NOT_ALLOWED`: `FIRECRAWL_API_URL` uses a host name the server wasn't configured to accept.
- A page that comes back as a login wall or "blocked" can't be read from this network. Say so rather than retrying.
