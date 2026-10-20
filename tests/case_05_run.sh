#!/bin/sh
# Case 05: cmd_run — state-машина автопроверки
. "$(dirname "$0")/common.sh"

TRACE="https://www.cloudflare.com/cdn-cgi/trace"
META="https://speed.cloudflare.com/meta"
CF_API="https://api.cloudflareclient.com/v0a4005/reg"

setup_run() {
	wac_setup
	wac_put_config 1 6 warp 2 /root/WARP.conf
	export WAC_CONF_OVERRIDE="$WAC_TEST_ROOT/WARP.conf"
	{ echo "[Interface]"; echo "PrivateKey = X"; } > "$WAC_TEST_ROOT/WARP.conf"
	wac_put_network warp amneziawg 162.159.192.1 2408
	wac_clock 1700000000
	echo 100000 > "$WAC_TEST_ROOT/uptime"    # uptime 27ч — грейс пройден
	: > "$WAC_TEST_ROOT/actions.log"
	wac_ping_set "10 packets transmitted, 10 packets received, 0% packet loss
round-trip min/avg/max = 20/20/20 ms"
	wac_curl_set "http://1.1.1.1/cdn-cgi/trace" "ip=10.0.0.1"
	wac_hs_set warp 1700000000
	wac_hs_set wac-test 1700000000
	# интервал прошёл: last_check = now - 8.3ч (больше 6ч - 5мин)
	: > "$WAC_STATE_FILE"; echo "last_check=1699970000" >> "$WAC_STATE_FILE"
}

# (T1) интервал не прошёл -> check не запускается (last_check не меняется)
setup_run
echo "last_check=1699997600" > "$WAC_STATE_FILE"   # 40 минут назад
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS"},"country":"NL"}'
wac_run run >/dev/null
wac_run status | grep -q '"last_check":1699997600' && ok "run: T1 интервал не прошёл — проверка пропущена" || fail "run: T1 ($?)"
wac_teardown

# (T7) грейс после ребута: uptime < 900 -> пропуск
setup_run
echo 100 > "$WAC_TEST_ROOT/uptime"
wac_run run >/dev/null
wac_run status | grep -q '"last_check":1699970000' && ok "run: T7 грейс после ребута" || fail "run: T7"
wac_teardown

# (T8) выключено -> пропуск
setup_run
wac_put_config 0 6 warp 2 /root/WARP.conf
wac_run run >/dev/null
wac_run status | grep -q '"last_check":1699970000' && ok "run: T8 выключено — пропуск" || fail "run: T8"
wac_teardown

# (T2) WAN down -> wan-down, fails не растёт, без regen
setup_run
wac_curl_unset "http://1.1.1.1/cdn-cgi/trace"
wac_run run >/dev/null
echo "--- DEBUG T2 state: $(cat "$WAC_STATE_FILE" 2>/dev/null | tr '\n' ' ')"
echo "--- DEBUG T2 log: $(tail -3 "$WAC_LOG_FILE" 2>/dev/null | tr '\n' '|')"
wac_run status | grep -q '"last_result":"wan-down"' && ok "run: T2 wan-down" || fail "run: T2 wan-down"
F=$(wac_run status | grep -o '"fails":[0-9]*' | cut -d: -f2)
assert_eq "$F" "0" "run: T2 fails не растёт"
grep -q "regen" "$WAC_LOG_FILE" && fail "run: T2 без regen" || ok "run: T2 без regen"
wac_teardown

# (T3) сбой затем восстановление -> без regen
setup_run
wac_curl_seq "$TRACE" "" "ip=1.2.3.4
warp=on
colo=AMS" "ip=1.2.3.4
warp=on
colo=AMS"
wac_curl_set "$META" '{"colo":{"iata":"AMS"},"country":"NL"}'
wac_run run >/dev/null
R=$(wac_run status | grep -o '"last_result":"[a-z-]*"' | cut -d'"' -f4)
echo "--- DEBUG T3 log:"; cat "$WAC_LOG_FILE" 2>/dev/null | tail -6
assert_eq "$R" "ok" "run: T3 восстановилось (last_result=ok)"
grep -q "regen" "$WAC_LOG_FILE" && fail "run: T3 без regen" || ok "run: T3 без regen"
wac_teardown

# (T4) manual-off -> без regen
setup_run
wac_curl_unset "$TRACE"
sed -i '' 's/^warp.proto=amneziawg$/warp.proto=pppoe/' "$WAC_TEST_ROOT/etc/config/network" 2>/dev/null || \
	grep -v "^warp.proto=" "$WAC_TEST_ROOT/etc/config/network" > "$WAC_TEST_ROOT/etc/config/network.t" && echo "warp.proto=pppoe" >> "$WAC_TEST_ROOT/etc/config/network.t" && mv "$WAC_TEST_ROOT/etc/config/network.t" "$WAC_TEST_ROOT/etc/config/network"
wac_run run >/dev/null
R=$(wac_run status | grep -o '"last_result":"[a-z-]*"' | cut -d'"' -f4)
assert_eq "$R" "no-iface" "run: T4 нет интерфейса -> no-iface"
grep -q "regen" "$WAC_LOG_FILE" && fail "run: T4 без regen" || ok "run: T4 без regen"
wac_teardown

# (T6) чужой живой lock -> выход без действий
setup_run
echo $$ > "$WAC_LOCK_FILE"
wac_curl_unset "$TRACE"
wac_run run >/dev/null
wac_run status | grep -q '"last_result":"none"' && ok "run: T6 lock busy — выход" || fail "run: T6"
rm -f "$WAC_LOCK_FILE"
wac_teardown

# (T5) все проверки провалены -> regen запускается
setup_run
wac_curl_unset "$TRACE"      # trace пуст -> no-link стабильно
wac_curl_unset "$CF_API"     # ключи не получить -> regen-failed, но regen ЗАПУСКАЕТСЯ
wac_run run >/dev/null
grep -q "regen: получаем ключи" "$WAC_LOG_FILE" && ok "run: T5 regen запущен" || fail "run: T5 regen запущен"
grep -q "WARP.conf заменен" "$WAC_LOG_FILE" && fail "run: T5 конфиг не должен замениться (regen-failed)" || ok "run: T5 конфиг не тронут"
wac_teardown

summary
