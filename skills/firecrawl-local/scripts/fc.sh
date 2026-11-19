#!/usr/bin/env bash
# Saves Firecrawl Local results to files and prints only a short summary.
#   fc.sh map URL [SEARCH]     a site's URLs, or those matching SEARCH; prints the first 30
#   fc.sh page URL             one page's markdown; prints the file and its outline
#   fc.sh shot URL             a screenshot; prints the PNG's path
#   fc.sh batch URL [URL...]   several pages into one file; prints where each page starts
#   fc.sh crawl URL [OPTIONS]  a crawl into one file; OPTIONS is JSON, such as
#                              '{"limit":20,"includePaths":["^/docs/"]}' (limit defaults to 10)
set -euo pipefail
: "${FIRECRAWL_API_URL:?set it to the server, such as http://127.0.0.1:3002}" "${FIRECRAWL_API_KEY:?set it to the server token}"

api() { # api ROUTE [JSON]. The token goes through stdin, out of the process list.
  # A slow JavaScript page or a large PDF takes up to about a minute.
  local args=(-sS --max-time 120 -H @- "$FIRECRAWL_API_URL/v2/$1")
  if (($# > 1)); then args+=(-H 'Content-Type: application/json' -d "$2"); fi
  printf 'Authorization: Bearer %s\n' "$FIRECRAWL_API_KEY" | curl "${args[@]}"
}

out=$(mktemp -d)
case "${1:-} $#" in
  "map 2" | "map 3")
    api map "$(jq -n --arg url "$2" --arg search "${3:-}" '{url: $url} + if $search == "" then {} else {search: $search} end')" \
      | jq -r '(.links // error(.error // "no links"))[] | .url' > "$out/urls.txt"
    echo "$out/urls.txt: $(wc -l < "$out/urls.txt" | tr -d ' ') URLs"
    head -30 "$out/urls.txt"
    ;;
  "page 2")
    api scrape "$(jq -n --arg url "$2" '{url: $url, formats: ["markdown"]}')" > "$out/response.json"
    jq -er '.data.markdown // error(.error // "no markdown")' "$out/response.json" > "$out/page.md"
    jq -r --arg file "$out/page.md" --argjson lines "$(wc -l < "$out/page.md")" \
      '"\($file): \($lines) lines, HTTP \(.data.metadata.statusCode)"' "$out/response.json"
    grep -n '^#' "$out/page.md" || true
    ;;
  "shot 2")
    api scrape "$(jq -n --arg url "$2" '{url: $url, formats: ["screenshot"]}')" \
      | jq -er '.data.screenshot // error(.error // "no screenshot")' \
      | sed 's|^data:image/png;base64,||' | base64 -d > "$out/page.png"
    echo "$out/page.png"
    ;;
  batch\ [2-9] | batch\ [1-9][0-9] | "crawl 2" | "crawl 3")
    if [[ $1 == batch ]]; then
      route=batch/scrape
      body=$(jq -n '{urls: $ARGS.positional, formats: ["markdown"]}' --args "${@:2}")
    else
      route=crawl
      body=$(jq -n --arg url "$2" --argjson opts "${3:-null}" '{url: $url, limit: 10} + ($opts // {})')
    fi
    id=$(api "$route" "$body" | jq -er '.id // error(.error // "no job id")')
    # Poll for up to 5 minutes; a 10-page crawl usually takes under one.
    for _ in $(seq 150); do
      api "$route/$id" > "$out/job.json"
      if jq -e '.status != "scraping"' "$out/job.json" > /dev/null; then break; fi
      sleep 2
    done
    jq -r '(.data // error(.error // "no results"))[] | "\n=== \(.metadata.sourceURL) (HTTP \(.metadata.statusCode))\n\(.markdown)"' \
      "$out/job.json" > "$out/pages.md"
    jq -r --arg file "$out/pages.md" \
      '"\($file): \(.status), \(.data | length) pages, \(.errors // [] | length) errors"' "$out/job.json"
    grep -n '^=== ' "$out/pages.md" || true
    ;;
  *)
    sed -n '2,8s/^# //p' "$0" >&2
    exit 2
    ;;
esac
