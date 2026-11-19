#!/usr/bin/env bash
# Saves Firecrawl Local results to files and prints only a short summary.
#   fc.sh map URL [SEARCH]      a site's URLs, or those matching SEARCH; prints the first 30
#   fc.sh page URL [OPTIONS]    a page's markdown; prints its status and up to 40 headings
#   fc.sh shot URL              a screenshot; prints the PNG's path
#   fc.sh batch URL URL...      several pages into one file; prints each page's status and line
#   fc.sh crawl URL [OPTIONS]   part of a site into one file, like batch (10 pages unless OPTIONS say)
# OPTIONS is JSON added to the request, such as '{"waitFor":3000}' or '{"includePaths":["^/docs/"]}'.
# Exits 1 when nothing usable came back: an error, a blocked or empty page, or an unfinished job.
set -euo pipefail

case "${1:-} $#" in
  "map 2" | "map 3" | "page 2" | "page 3" | "shot 2" | "crawl 2" | "crawl 3" | batch\ [2-9] | batch\ [1-9][0-9]) ;;
  *) sed -n '2,9s/^# //p' "$0" >&2; exit 2 ;;
esac
: "${FIRECRAWL_API_URL:?set it to the server, such as http://127.0.0.1:3002}" "${FIRECRAWL_API_KEY:?set it to the server token}"
if [[ $1 == page || $1 == crawl ]] && [[ -n ${3:-} ]] && ! jq -e 'type == "object"' <<< "$3" > /dev/null 2>&1; then
  echo "OPTIONS must be a JSON object, such as '{\"waitFor\":3000}'" >&2
  exit 2
fi
tmp=${TMPDIR:-/tmp}
out=$(mktemp -d "${tmp%/}/fc.XXXXXX")
trap 'rm -f "$out/response.json"' EXIT

api() { # api ROUTE [JSON]: POST with JSON, else GET. Prints the response; fails on any error.
  # A slow JavaScript page or a large PDF takes up to about a minute. Only GETs are
  # retried: resending a POST could start a second job.
  local args=(-sS --max-time 120 -o "$out/response.json" -w '%{http_code}' -H @- "${FIRECRAWL_API_URL%/}/v2/$1")
  if (($# > 1)); then args+=(-H 'Content-Type: application/json' -d "$2"); else args+=(--retry 2); fi
  local code
  code=$(printf 'Authorization: Bearer %s\n' "$FIRECRAWL_API_KEY" | curl "${args[@]}")
  if [[ $code != 2* ]] || ! jq -e 'type == "object"' "$out/response.json" > /dev/null 2>&1; then
    echo "Firecrawl Local answered HTTP $code: $(jq -r '.error // empty' "$out/response.json" 2> /dev/null || head -c 300 "$out/response.json")" >&2
    exit 1
  fi
  cat "$out/response.json"
}

# A page is usable when the site answered without an error, didn't block it,
# and it has content. Its status line also marks a short page, which may be a
# bot check or login wall, and adds any warning, such as a page that needed
# JavaScript but wasn't rendered.
problems='def text: .markdown // .html // .rawHtml // "";
def problems: [(.metadata.statusCode // 0 | select(. >= 400) | "HTTP \(.)"), (select(.blocked) | "blocked"),
  (select((text | test("\\S") | not) and (.links // []) == []) | "empty")];
def usable: problems == [];
def status: ["HTTP \(.metadata.statusCode // "?")"] + [problems[] | select(startswith("HTTP") | not)]
  + [select(text | test("\\S") and length < 300) | "short"] + [.warning // empty] | join(", ");'

case $1 in
  map)
    api map "$(jq -n --arg url "$2" --arg search "${3:-}" '{url: $url} + if $search == "" then {} else {search: $search} end')" \
      | jq -r '(.links // error("no links"))[] | .url' > "$out/urls.txt"
    echo "$out/urls.txt: $(wc -l < "$out/urls.txt" | tr -d ' ') URLs"
    head -30 "$out/urls.txt"
    ;;
  page)
    doc=$(api scrape "$(jq -n --arg url "$2" --argjson opts "${3:-null}" '{url: $url, formats: ["markdown"]} + ($opts // {})')" | jq -c '.data')
    jq -r '.markdown // .html // .rawHtml // ""' <<< "$doc" > "$out/page.md"
    jq -r --arg file "$out/page.md" --argjson lines "$(wc -l < "$out/page.md")" "$problems"'
      "\($file): \($lines) lines, \(status)"
      + if .metadata.url and .metadata.url != .metadata.sourceURL then ", redirected to \(.metadata.url)" else "" end' <<< "$doc"
    if jq -e '.links' <<< "$doc" > /dev/null; then
      jq -r '.links[] | .url? // .' <<< "$doc" > "$out/links.txt"
      echo "$out/links.txt: $(wc -l < "$out/links.txt" | tr -d ' ') links"
    fi
    # Headings outside code blocks, without link targets, so the outline stays
    # short on very long pages.
    awk '/^(```|~~~)/ { code = !code; next }
      !code && /^#/ && ++n <= 40 { gsub(/\]\([^)]*\)/, "]"); print NR ":" substr($0, 1, 120) }
      END { if (n > 40) print "(" n - 40 " more headings)" }' "$out/page.md"
    jq -e "$problems"' usable' <<< "$doc" > /dev/null
    ;;
  shot)
    api scrape "$(jq -n --arg url "$2" '{url: $url, formats: ["screenshot"]}')" \
      | jq -r '.data.screenshot // ""' | sed 's|^data:image/png;base64,||' | base64 -d > "$out/page.png"
    if [[ $(head -c 4 "$out/page.png" | tail -c 3) != PNG ]]; then
      echo "No screenshot came back for $2" >&2
      exit 1
    fi
    echo "$out/page.png"
    ;;
  batch | crawl)
    # Four pages at a time: a JavaScript page can take about 110 MB in Chromium,
    # and the server is capped at 2 GB.
    if [[ $1 == batch ]]; then
      route=batch/scrape
      body=$(jq -n '{urls: $ARGS.positional, formats: ["markdown"], maxConcurrency: 4}' --args "${@:2}")
    else
      route=crawl
      body=$(jq -n --arg url "$2" --argjson opts "${3:-null}" '{url: $url, limit: 10, maxConcurrency: 4} + ($opts // {})')
    fi
    id=$(api "$route" "$body" | jq -er '.id')
    deadline=$((SECONDS + 300)) # a 10-page crawl usually takes under a minute
    while :; do
      api "$route/$id" > "$out/job.json"
      if [[ $(jq -r .status "$out/job.json") != scraping ]] || ((SECONDS >= deadline)); then break; fi
      sleep 2
    done
    jq -r "$problems"'(.data // [])[] | "\n=== \(.metadata.sourceURL) (\(status))\n\(.markdown // "")"' \
      "$out/job.json" > "$out/pages.md"
    jq -r --arg file "$out/pages.md" --arg id "$id" "$problems"'
      "\($file): job \($id) \(.status), \([(.data // [])[] | select(usable)] | length) of \(.total) pages usable",
      ((.errors // [])[:10][] | "failed: \(.url // "?"): \(.error)")' "$out/job.json"
    grep -n '^=== ' "$out/pages.md" | head -50
    ok=$(jq "$problems"'.status == "completed" and any((.data // [])[]; usable)' "$out/job.json")
    rm "$out/job.json"
    [[ $ok == true ]]
    ;;
esac
