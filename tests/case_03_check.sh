#!/bin/sh
# Case 03: cmd_check — критерии недоступности
. "$(dirname "$0")/common.sh"

TRACE="https://www.cloudflare.com/cdn-cgi/trace"
META="https://speed.cloudflare.com/meta"

setup_ok_env() {
	wac_setup
	wac_put_config 1 6 warp 2 /root/WARP.conf
	export WAC_CONF_OVERRIDE="$WAC_TEST_ROOT/WARP.conf"
	{ echo "[Interface]"; echo "PrivateKey = X"; } > "$WAC_TEST_ROOT/WARP.conf"
	wac_put_network warp amneziawg 162.159.192.1 2408
	wac_clock 1700000000
	# WAN жив
	wac_curl_set "http://1.1.1.1/cdn-cgi/trace" "warp=off
ip=10.0.0.1"
	# ping по умолчанию — без потерь
	wac_ping_set "10 packets transmitted, 10 packets received, 0% packet loss
round-trip min/avg/max = 20/20/20 ms"
	# журнал рукопожатий свежий
	wac_hs_set warp 1699999990
}

# (a) всё живо -> ok
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS","country":"NL"},"country":"NL"}'
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"ok"' && ok "check: ok" || fail "check: ok ($OUT)"
wac_teardown

# (b) trace пуст везде -> no-link
setup_ok_env
wac_curl_unset "$TRACE"
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"no-link"' && ok "check: no-link" || fail "check: no-link ($OUT)"
wac_teardown

# (c) warp!=on -> no-link
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=off
colo=AMS"
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"no-link"' && ok "check: warp!=on -> no-link" || fail "check: warp!=on -> no-link ($OUT)"
wac_teardown

# (d) российский colo -> ru-colo
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=DME"
wac_curl_set "$META" '{"colo":{"iata":"DME","country":"RU"},"country":"RU"}'
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"ru-colo"' && ok "check: ru-colo" || fail "check: ru-colo ($OUT)"
wac_teardown

# (e) обрыв потока (torn) -> torn
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS"},"country":"NL"}'
wac_ping_set "64 bytes from 1.1.1.1: icmp_seq=1 ttl=58 time=20 ms
64 bytes from 1.1.1.1: icmp_seq=2 ttl=58 time=20 ms
64 bytes from 1.1.1.1: icmp_seq=3 ttl=58 time=21 ms
64 bytes from 1.1.1.1: icmp_seq=4 ttl=58 time=22 ms
10 packets transmitted, 4 packets received, 60% packet loss
round-trip min/avg/max = 20/21/25 ms"
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"torn"' && ok "check: torn" || fail "check: torn ($OUT)"
wac_teardown

# (f) WAN мертв -> wan-down, счётчик fails не растет
setup_ok_env
wac_curl_unset "http://1.1.1.1/cdn-cgi/trace"
wac_run check >/dev/null
F1=$(wac_run status | grep -o '"fails":[0-9]*' | cut -d: -f2)
wac_run check >/dev/null
F2=$(wac_run status | grep -o '"fails":[0-9]*' | cut -d: -f2)
assert_eq "$F1" "0" "check: wan-down не растит fails (первый)"
assert_eq "$F2" "0" "check: wan-down не растит fails (второй)"
OUT=$(wac_run check)
echo "$OUT" | grep -q '"result":"wan-down"' && ok "check: wan-down" || fail "check: wan-down ($OUT)"
wac_teardown

# (g) ok сбрасывает fails, провал растит
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS"},"country":"NL"}'
wac_run check >/dev/null
F=$(wac_run status | grep -o '"fails":[0-9]*' | cut -d: -f2)
assert_eq "$F" "0" "check: ok сбрасывает fails"
wac_teardown

# (h) состояние пишется: last_check/last_result
setup_ok_env
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS"},"country":"NL"}'
wac_run check >/dev/null
wac_run status | grep -q '"last_result":"ok"' && ok "check: last_result пишется" || fail "check: last_result пишется"
wac_run status | grep -q '"last_check":1700000000' && ok "check: last_check пишется" || fail "check: last_check пишется"
wac_teardown

summary
