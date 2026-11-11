#!/usr/bin/env bash
# Local test environment for headscale-admin against a real headscale.
#
#   ./hs-test.sh up        build + start headscale, headscale-admin and proxy
#   ./hs-test.sh smoke     run API checks against the running environment
#   ./hs-test.sh clients   start two tailscale clients waiting for registration
#   ./hs-test.sh --help    all commands
#
# Environment:
#   HEADSCALE_VERSION  headscale image tag   (default 0.29.7)
#   HS_TEST_PORT       local port            (default 8081)
#
# Compatible with the bash 3.2 shipped with macOS.
set -euo pipefail

cd "$(dirname "$0")"

export HEADSCALE_VERSION="${HEADSCALE_VERSION:-0.29.7}"
export HS_TEST_PORT="${HS_TEST_PORT:-8081}"

STATE=.state
BASE="http://localhost:${HS_TEST_PORT}"
API="${BASE}/api/v1"
CLIENTS="client1 client2"

dc() { docker compose "$@"; }
hs() { dc exec -T headscale headscale "$@"; }

c_green=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
info() { printf '%s==>%s %s\n' "$c_bold" "$c_off" "$*"; }
die()  { printf '%sError:%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

render_config() {
	mkdir -p "$STATE/config"
	sed "s#\${HS_TEST_PORT}#${HS_TEST_PORT}#g" headscale/config.yaml.tmpl > "$STATE/config/config.yaml"
}

wait_healthy() {
	local i
	for i in $(seq 1 60); do
		if curl -sf "${BASE}/health" >/dev/null 2>&1; then return 0; fi
		sleep 1
	done
	dc logs --tail 30 headscale
	die "headscale did not become healthy on ${BASE}"
}

api_key() {
	[ -s "$STATE/apikey" ] || die "no API key yet, run: $0 up"
	cat "$STATE/apikey"
}

ensure_key_and_users() {
	if [ ! -s "$STATE/apikey" ]; then
		hs apikeys create --expiration 90d | tail -n 1 | tr -d '\r' > "$STATE/apikey"
	fi
	local u
	for u in alice bob; do
		hs users create "$u" >/dev/null 2>&1 || true
	done
}

print_access() {
	cat <<EOF

${c_bold}headscale ${HEADSCALE_VERSION} + headscale-admin${c_off}
  Admin UI : ${BASE}/admin/
  API URL  : ${BASE}
  API Key  : $(api_key)
  Users    : alice, bob
EOF
}

# --- commands --------------------------------------------------------------

cmd_up() {
	render_config
	info "Building headscale-admin image and starting environment (headscale ${HEADSCALE_VERSION})"
	dc up -d --build headscale admin proxy
	wait_healthy
	ensure_key_and_users
	print_access
}

cmd_rebuild() {
	info "Rebuilding headscale-admin image"
	dc up -d --build --no-deps admin
	info "Done, reload ${BASE}/admin/ in the browser"
}

# Always leaves nothing behind: containers, network, volumes, the images used
# by this environment (headscale, caddy, tailscale, headscale-admin:local-test)
# and the local state (API key, rendered config).
cmd_down() {
	render_config # compose needs the config path to exist even when tearing down
	dc --profile clients down --volumes --rmi all --remove-orphans
	rm -rf "$STATE"
	info "Containers, volumes, network and images removed"
}

cmd_reset() {
	cmd_down
}

cmd_status() {
	dc --profile clients ps
	[ -s "$STATE/apikey" ] && print_access || true
}

cmd_logs() {
	dc --profile clients logs -f --tail 100 "$@"
}

cmd_key() {
	api_key
}

register_url() {
	dc exec -T "$1" tailscale status --json 2>/dev/null \
		| grep -o '"AuthURL": *"http[^"]*"' | sed 's/.*"\(http[^"]*\)"/\1/' || true
}

cmd_clients() {
	info "Starting tailscale clients: ${CLIENTS}"
	dc --profile clients up -d client1 client2
	sleep 2
	local c
	for c in $CLIENTS; do
		dc exec -d "$c" tailscale up --login-server=http://headscale:8080 \
			--hostname="$c" --accept-dns=false --ssh
	done
	cmd_urls
}

cmd_urls() {
	local c url i
	for c in $CLIENTS; do
		url=""
		for i in $(seq 1 20); do
			url="$(register_url "$c")"
			[ -n "$url" ] && break
			# already registered?
			if dc exec -T "$c" tailscale status >/dev/null 2>&1; then url="(registered)"; break; fi
			sleep 1
		done
		printf '  %-8s %s\n' "$c" "${url:-(no register URL, see: $0 logs $c)}"
	done
	echo "  ${c_dim}Paste a URL into Nodes -> + -> Register (or Approve/Reject) in the admin UI.${c_off}"
}

cmd_hs() {
	hs "$@"
}

# --- smoke test ------------------------------------------------------------

PASS=0; FAIL=0
BODY=""; CODE=""

req() { # req METHOD PATH [curl args...]  -> sets CODE and BODY
	local m="$1" p="$2"; shift 2
	local out
	out="$(curl -s -w $'\n%{http_code}' -X "$m" \
		-H "Authorization: Bearer $(api_key)" -H 'Content-Type: application/json' \
		"${API}${p}" "$@")"
	CODE="${out##*$'\n'}"
	BODY="${out%$'\n'*}"
}

check() { # check NAME EXPECTED_CODE [BODY_SUBSTRING]
	local name="$1" want="$2" substr="${3:-}"
	if [ "$CODE" = "$want" ] && { [ -z "$substr" ] || printf '%s' "$BODY" | grep -qF -- "$substr"; }; then
		PASS=$((PASS + 1)); printf '  %sok%s    %s\n' "$c_green" "$c_off" "$name"
	else
		FAIL=$((FAIL + 1)); printf '  %sFAIL%s  %s  (HTTP %s, want %s%s)\n' "$c_red" "$c_off" "$name" "$CODE" "$want" "${substr:+, body containing \"$substr\"}"
		printf '        %s%s%s\n' "$c_dim" "$(printf '%s' "$BODY" | head -c 300)" "$c_off"
	fi
}

cmd_smoke() {
	api_key >/dev/null
	info "Smoke test against ${BASE} (headscale ${HEADSCALE_VERSION})"

	CODE="$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/admin/")"; BODY=""
	check "admin UI served at /admin/" 200

	req GET /health;     check "GET  /health" 200 databaseConnectivity
	req GET /user;       check "GET  /user" 200 '"alice"'
	req GET /node;       check "GET  /node" 200 nodes
	req GET /apikey;     check "GET  /apikey" 200 apiKeys
	req GET /preauthkey; check "GET  /preauthkey" 200 preAuthKeys

	req POST /preauthkey -d '{"user":"1","reusable":false,"ephemeral":false,"expiration":"2099-01-01T00:00:00Z","aclTags":["tag:server"]}'
	check "POST /preauthkey with aclTags" 200 'tag:server'

	local policy
	policy='{"groups":{"group:admins":["alice@"]},"tagOwners":{"tag:server":["group:admins"]},"hosts":{},"acls":[{"#ha-meta":{"name":"allow all","open":true},"action":"accept","src":["*"],"dst":["*:*"]}],"ssh":[{"action":"check","src":["group:admins"],"dst":["tag:server"],"users":["root"],"checkPeriod":"1h","acceptEnv":["GIT_*"]},{"action":"accept","src":["autogroup:member"],"dst":["autogroup:self"],"users":["autogroup:nonroot","root"]}]}'
	req PUT /policy -d "{\"policy\": $(printf '%s' "$policy" | python3 -I -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}"
	check "PUT  /policy with ssh check/checkPeriod/acceptEnv" 200
	req GET /policy
	check "GET  /policy keeps checkPeriod" 200 'checkPeriod'

	# 0.29 endpoints exist (invalid IDs are rejected by the handler, not 404)
	req POST /auth/register -d '{"user":"alice","authId":"invalid"}'
	check "POST /auth/register exists" 500 'hskey-authreq'
	req POST /auth/approve -d '{"authId":"invalid"}'
	check "POST /auth/approve exists" 400 'hskey-authreq'
	req POST /auth/reject -d '{"authId":"invalid"}'
	check "POST /auth/reject exists" 400 'hskey-authreq'
	# headscale-admin falls back to the legacy endpoint only on this exact response
	req POST /auth/does-not-exist -d '{}'
	check "unknown route -> 404 \"Not Found\"" 404 '"Not Found"'

	# full registration flow if a client is waiting
	local url authid nodeid
	url="$(dc ps --status running --services 2>/dev/null | grep -qx client2 && register_url client2 || true)"
	if [ -n "$url" ]; then
		authid="${url##*/register/}"
		req POST /auth/register -d "{\"user\":\"bob\",\"authId\":\"${authid}\"}"
		check "register client2 via /auth/register" 200 '"client2"'
		nodeid="$(printf '%s' "$BODY" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["node"]["id"])' 2>/dev/null || true)"
		if [ -n "$nodeid" ]; then
			req POST "/node/${nodeid}/expire?disableExpiry=true"
			check "disable expiry -> expiry null" 200 '"expiry":null'
		fi
	else
		printf '  %sskip%s  registration flow (run "%s clients" first, client2 must be waiting)\n' "$c_dim" "$c_off" "$0"
	fi

	echo
	if [ "$FAIL" -eq 0 ]; then
		printf '%s%d passed%s\n' "$c_green" "$PASS" "$c_off"
	else
		printf '%s%d passed, %d failed%s\n' "$c_red" "$PASS" "$FAIL" "$c_off"
		exit 1
	fi
}

usage() {
	cat <<EOF
Usage: $0 <command>

  up         build headscale-admin image, start headscale ${HEADSCALE_VERSION} + proxy,
             create API key and users alice/bob, print URL and key
  rebuild    rebuild only the headscale-admin image after code changes
  smoke      run API checks (overwrites the policy of the test environment)
  clients    start tailscale clients client1/client2 and print register URLs
  urls       print register URLs of waiting clients
  status     show containers, URL and API key
  key        print the API key
  logs [svc] follow logs (headscale, admin, proxy, client1, client2)
  hs <args>  run the headscale CLI, e.g. '$0 hs nodes list'
  down       stop and delete everything: containers, volumes, network,
             images (headscale, caddy, tailscale, headscale-admin) and state
  reset      same as down

Environment: HEADSCALE_VERSION (default 0.29.7), HS_TEST_PORT (default 8081)
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
	up|rebuild|down|reset|status|logs|key|clients|urls|smoke|hs) "cmd_$cmd" "$@" ;;
	-h|--help|help|"") usage ;;
	*) usage; exit 1 ;;
esac
