# tests/common.sh — минимальный харнесс
PASS=0
FAIL=0

ok()   { echo "  ok  - $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL - $1"; FAIL=$((FAIL+1)); }

assert_contains() { # file|stdin-marker, needle
	case "$2" in
		"$(cat "$1" 2>/dev/null)") ok "$3"; fail "$3" ;;
	esac
}

assert_grep() { # needle file msg
	if grep -qF -- "$1" "$2" 2>/dev/null; then ok "$3"; else fail "$3"; fi
}

assert_no_grep() { # needle file msg
	if grep -qF -- "$1" "$2" 2>/dev/null; then fail "$3"; else ok "$3"; fi
}

assert_eq() { # got want msg
	if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (got: $1, want: $2)"; fi
}

summary() {
	echo "PASS=$PASS FAIL=$FAIL"
	[ "$FAIL" -eq 0 ]
}

# --- харнесс для бэкенда ---------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/luci-app-warp-autocheck/files/usr/bin/warp-autocheck"

wac_env() { # пишет переменные окружения в текущий шелл (без переиспользования старых)
	WAC_TEST_ROOT="${WAC_TEST_ROOT:?wac_setup first}"
	export WAC_TEST_ROOT
	WAC_STATE_FILE="$WAC_TEST_ROOT/state"
	WAC_LOG_FILE="$WAC_TEST_ROOT/warp-autocheck.log"
	WAC_LOCK_FILE="$WAC_TEST_ROOT/lock"
	WAC_UPTIME_FILE="$WAC_TEST_ROOT/uptime"
	export WAC_STATE_FILE WAC_LOG_FILE WAC_LOCK_FILE WAC_UPTIME_FILE
	export PATH="$ROOT/tests/stubs:$PATH"
}

wac_setup() {
	WAC_TEST_ROOT=$(mktemp -d)
	wac_env
	mkdir -p "$WAC_TEST_ROOT/etc/config" "$WAC_TEST_ROOT/curl" "$WAC_TEST_ROOT/awg" "$WAC_TEST_ROOT/ping"
	: > "$WAC_TEST_ROOT/curl.log"
}

wac_teardown() { [ -n "$WAC_TEST_ROOT" ] && rm -rf "$WAC_TEST_ROOT"; }

_wac_now() {
	if [ -f "$WAC_TEST_ROOT/clock" ]; then cat "$WAC_TEST_ROOT/clock"; else /bin/date +%s; fi
}

wac_clock() { echo "${1:-$(_wac_now)}" > "$WAC_TEST_ROOT/clock"; }

wac_put_config() { # [enabled] [interval] [iface] [retries] [conf]
	mkdir -p "$WAC_TEST_ROOT/etc/config"
	cat > "$WAC_TEST_ROOT/etc/config/warp-autocheck" <<EOF
@main=main
main.enabled=${1:-1}
main.interval=${2:-6}
main.interface=${3:-warp}
main.retries=${4:-2}
main.conf=${5:-/root/WARP.conf}
EOF
}

wac_put_network() { # iface proto [peer_host] [peer_port]
	i="${1:-warp}"; p="${2:-amneziawg}"
	{
		echo "@$i=$p"
		echo "$i.proto=$p"
		echo "$i.private_key=OLDCONFPRIVKEY="
		echo "@${i}_peer=amneziawg_$i"
		echo "${i}_peer.public_key=bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
		echo "${i}_peer.endpoint_host=162.159.192.1"
		echo "${i}_peer.endpoint_port=2408"
	} > "$WAC_TEST_ROOT/etc/config/network"
}

wac_run() { sh "$BACKEND" "$@"; }

_wac_url_slug() {
	u="$1"
	case "$u" in
		https://*) u="${u#https://}" ;;
		http://*) u="${u#http://}" ;;
	esac
	echo "$u" | sed 's#[/:]#_#g; s#[?#].*$##; s#_*$##'
}

wac_curl_set() { # url content — задаёт ответ стаба curl
	printf '%s\n' "$2" > "$WAC_TEST_ROOT/curl/$(_wac_url_slug "$1")"
}

wac_curl_unset() { rm -f "$WAC_TEST_ROOT/curl/$(_wac_url_slug "$1")"; }

wac_curl_seq() { # url resp1 [resp2 ...] — каждый аргумент = полный ответ одного вызова
	slug=$(_wac_url_slug "$1"); shift
	rm -rf "$WAC_TEST_ROOT/curl/$slug" "$WAC_TEST_ROOT/curl/$slug.count" "$WAC_TEST_ROOT/curl/$slug.seq" "$WAC_TEST_ROOT/curl/$slug.seq.d"
	mkdir -p "$WAC_TEST_ROOT/curl/$slug.seq.d"
	N=0
	for r in "$@"; do
		N=$((N + 1))
		printf '%s\n' "$r" > "$WAC_TEST_ROOT/curl/$slug.seq.d/$(printf '%04d' "$N")"
	done
}

wac_hs_set() { # iface epoch|""  — рукопожатие интерфейса
	if [ -n "$2" ]; then echo "$2" > "$WAC_TEST_ROOT/awg/$1.handshakes"; else rm -f "$WAC_TEST_ROOT/awg/$1.handshakes"; fi
}

wac_ping_set() { printf '%s\n' "$1" > "$WAC_TEST_ROOT/ping/last.out"; }

wac_actions() { cat "$WAC_TEST_ROOT/actions.log" 2>/dev/null; }
