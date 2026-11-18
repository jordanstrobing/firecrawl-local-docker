#!/usr/bin/env bash
# Usage: test/smoke.sh IMAGE
# Requires Docker Compose 2.24.4+, curl and jq.
set -euo pipefail

export SMOKE_IMAGE=${1:?usage: test/smoke.sh IMAGE}
export SMOKE_PROJECT="firecrawl-smoke-$$-$RANDOM"
export FIRECRAWL_LOCAL_TOKEN=smoke-test-token
export FIRECRAWL_LOCAL_ALLOWED_HOSTS="firecrawl.test, other.test"
export FIRECRAWL_API_KEY=
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
compose=(docker compose -p "$SMOKE_PROJECT" --env-file /dev/null -f "$here/../compose.yaml" -f "$here/compose.yaml")

cleanup() {
  local status=$?
  if (( status != 0 )); then "${compose[@]}" logs --tail 40 >&2 || true; fi
  "${compose[@]}" down --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${compose[@]}" up -d --wait --wait-timeout 60
[[ $("${compose[@]}" exec -T firecrawl-local id -u) == 10001 ]]
"${compose[@]}" exec -T firecrawl-local sh -ec '
  grep -q "^NoNewPrivs:[[:space:]]*1$" /proc/self/status
  grep -q "^CapBnd:[[:space:]]*0000000000000000$" /proc/self/status
  test -x /usr/sbin/chroot
  if /usr/sbin/chroot / /bin/true 2>/dev/null; then
    echo "The service can chroot outside the browser namespace" >&2
    exit 1
  fi
'
api="http://$("${compose[@]}" port firecrawl-local 3002)"
site=http://fixture.test:8000

expect_status() {
  local expected=$1 actual
  shift
  actual=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$@")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected HTTP %s, got %s (%s)\n' "$expected" "$actual" "$*" >&2
    return 1
  fi
}

request() {
  local route=$1
  shift
  local response
  if ! response=$(curl --fail-with-body -sS --max-time 60 "$api/$route" \
      -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" \
      -H 'Content-Type: application/json' "$@"); then
    printf '%s\n' "$response" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

expect_status 401 "$api/health"
expect_status 401 -H 'Authorization: Bearer wrong' "$api/health"
expect_status 403 -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" -H 'Host: unknown.test' "$api/health"
expect_status 200 -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" -H 'Host: firecrawl.test:3002' "$api/health"
expect_status 200 -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" -H 'Host: other.test' "$api/health"
request health | jq -e '.status == "ok" and .engine == "firecrawl-local" and (.version | length > 0)' >/dev/null
expect_status 501 -H "Authorization: Bearer $FIRECRAWL_LOCAL_TOKEN" \
  -H 'Content-Type: application/json' -d '{"query":"example"}' "$api/v2/search"
printf 'Passed authentication, Host allowlist, container health and cloud-off mode\n'

request v2/scrape -d "{\"url\":\"$site/static.html\",\"formats\":[\"markdown\"]}" \
  | jq -e '.success and (.data.markdown | contains("static-marker-7f3a"))' >/dev/null
request v2/scrape -d "{\"url\":\"$site/document.pdf\",\"formats\":[\"markdown\"]}" \
  | jq -e '.success and (.data.markdown | contains("pdf-marker-4b2d"))' >/dev/null
request v2/scrape -d "{\"url\":\"$site/js.html\",\"formats\":[\"markdown\",\"screenshot\"]}" \
  | jq -e '.success and (.data.markdown | contains("js-marker-c91e")) and (.data.screenshot | startswith("data:image/png;base64,iVBORw0KGgo"))' >/dev/null
printf 'Passed static HTML, PDF, JavaScript and PNG screenshot\n'

job=$(request v2/crawl -d "{\"url\":\"$site/static.html\",\"limit\":2,\"maxDiscoveryDepth\":1,\"crawlEntireDomain\":true,\"sitemap\":\"skip\"}" \
  | jq -er 'select(.success).id')
for ((attempt = 0; attempt < 30; attempt++)); do
  result=$(request "v2/crawl/$job")
  status=$(jq -er '.status' <<<"$result")
  if [[ "$status" != scraping ]]; then break; fi
  sleep 1
done
jq -e '.status == "completed" and (.data | length == 2) and any(.data[]; .markdown | contains("static-marker-7f3a")) and any(.data[]; .metadata.sourceURL | endswith("/js.html"))' \
  <<<"$result" >/dev/null
printf 'Passed bounded crawl\n'
