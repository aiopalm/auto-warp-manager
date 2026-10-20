#!/bin/sh
# Case 04: cmd_regen — генерация с подбором, замена, откат
. "$(dirname "$0")/common.sh"

TRACE="https://www.cloudflare.com/cdn-cgi/trace"
TRACE2="https://1.1.1.1/cdn-cgi/trace"
META="https://speed.cloudflare.com/meta"
CF_API="https://api.cloudflareclient.com/v0a4005/reg"
EXT_GEN="https://santa-atmo.ru/warp/warp.php"

CONF_OK_TRACE="ip=1.2.3.4
warp=on
colo=AMS"
META_FX='{"colo":{"iata":"AMS"},"country":"NL"}'
META_RU='{"colo":{"iata":"DME"},"country":"RU"}'
CF_REG_OK='{"result":{"id":"reg123","token":"tok456","config":{"peers":[{"public_key":"SRVPUBKEY="}],"interface":{"addresses":{"v4":"172.16.0.2","v6":"fd42::2"}}}}}'

setup_regen() {
	wac_setup
	wac_put_config 1 6 warp 2 /root/WARP.conf
	export WAC_CONF_OVERRIDE="$WAC_TEST_ROOT/WARP.conf"
	wac_put_network warp amneziawg 162.159.192.1 2408
	wac_clock 1700000000
	: > "$WAC_TEST_ROOT/actions.log"
	wac_ping_set "10 packets transmitted, 10 packets received, 0% packet loss
round-trip min/avg/max = 20/20/20 ms"
	# WAN жив
	wac_curl_set "http://1.1.1.1/cdn-cgi/trace" "ip=10.0.0.1"
	# CF API отвечает и регистрирует
	wac_curl_set "$CF_API" "$CF_REG_OK"
	wac_curl_set "$CF_API/reg123" "ok"
	# trace через тестовый/реальный интерфейс — работает
	wac_curl_set "$TRACE" "$CONF_OK_TRACE"
	wac_curl_set "$TRACE2" "$CONF_OK_TRACE"
	# colo зарубежный по умолчанию
	wac_curl_set "$META" "$META_FX"
	# ping ok по умолчанию (уже стоит)
	# рукопожатие тестового/реального интерфейса появляется сразу
	wac_hs_set warp 1700000000
	wac_hs_set wac-test 1700000000
	# маскировка awg_опций в network (чтобы apply_iface было куда писать)
	true
}

OLD_CONF='[Interface]
PrivateKey = OLDCONFPRIVKEY=
Address = 172.16.0.99
[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
Endpoint = 162.159.192.1:2408'

# (a) успех: replaced, uci обновлен, ifup вызван
setup_regen
printf '%s\n' "$OLD_CONF" > "$WAC_TEST_ROOT/WARP.conf"
OUT=$(wac_run regen)
echo "$OUT" | grep -q '"result":"replaced"' && ok "regen: replaced" || fail "regen: replaced ($OUT)"
echo "--- DEBUG LOG:"; cat "$WAC_LOG_FILE"
grep -q "TESTPRIVKEY" "$WAC_TEST_ROOT/WARP.conf" && ok "regen: WARP.conf заменен" || fail "regen: WARP.conf заменен"
grep -q "SRVPUBKEY" "$WAC_TEST_ROOT/WARP.conf" && ok "regen: ключ сервера в конфиге" || fail "regen: ключ сервера в конфиге"
wac_actions | grep -q "ifup" && ok "regen: ifup вызван" || fail "regen: ifup вызван ($(wac_actions))"
wac_run status | grep -q '"fails":0' && ok "regen: fails=0" || fail "regen: fails=0"
[ -f "$WAC_TEST_ROOT/WARP.conf.bak" ] && ok "regen: бэкап создан" || fail "regen: бэкап создан"
wac_teardown

# (b) работают только RU-точки -> теперь это приемлемо: replaced с RU-узлом
setup_regen
printf '%s\n' "$OLD_CONF" > "$WAC_TEST_ROOT/WARP.conf"
wac_curl_set "$META" "$META_RU"
wac_curl_set "$TRACE" "ip=1.2.3.4
warp=on
colo=DME"
OUT=$(wac_run regen)
echo "$OUT" | grep -q '"result":"replaced"' && ok "regen: RU-точка принимается как рабочая" || fail "regen: RU-точка ($OUT)"
grep -q "TESTPRIVKEY" "$WAC_TEST_ROOT/WARP.conf" && ok "regen: конфиг заменен на RU-точку" || fail "regen: конфиг заменен"
wac_teardown

# (c) пост-проверка провалилась -> rolled-back, конфиг = бэкап
setup_regen
printf '%s\n' "$OLD_CONF" > "$WAC_TEST_ROOT/WARP.conf"
# trace: 1-й вызов ок (подбор), последующие — пусто (пост-проверка провалится)
wac_curl_seq "$TRACE" "$CONF_OK_TRACE" "" ""
wac_curl_seq "$TRACE2" "" ""
OUT=$(wac_run regen)
echo "$OUT" | grep -q '"result":"rolled-back"' && ok "regen: rolled-back" || fail "regen: rolled-back ($OUT)"
grep -q "OLDCONFPRIVKEY" "$WAC_TEST_ROOT/WARP.conf" && ok "regen: старый конфиг восстановлен" || fail "regen: старый конфиг восстановлен"
wac_teardown

# (d) ключи недоступны вообще -> regen-failed, конфиг не тронут
setup_regen
printf '%s\n' "$OLD_CONF" > "$WAC_TEST_ROOT/WARP.conf"
wac_curl_unset "$CF_API"
wac_curl_unset "$EXT_GEN"
wac_curl_unset "$TRACE"   # через туннели тоже нельзя
wac_curl_unset "$TRACE2"
wac_curl_unset "http://1.1.1.1/cdn-cgi/trace"
wac_hs_unset_all=1
rm -f "$WAC_TEST_ROOT/awg/"*.handshakes
OUT=$(wac_run regen)
echo "$OUT" | grep -q '"result":"regen-failed"' && ok "regen: regen-failed" || fail "regen: regen-failed ($OUT)"
grep -q "OLDCONFPRIVKEY" "$WAC_TEST_ROOT/WARP.conf" && ok "regen: конфиг не тронут при провале" || fail "regen: конфиг не тронут"
wac_teardown

# (e) API закрыт напрямую, но доступен через живой туннель -> ключи через туннель, replaced
setup_regen
printf '%s\n' "$OLD_CONF" > "$WAC_TEST_ROOT/WARP.conf"
wac_curl_unset "$CF_API"
# вызовы API: 1) прямой POST — нет связи; 2) api_ok через туннель — есть; 3) POST через туннель — рег; 4) PATCH — ok
wac_curl_seq "$CF_API" "" "ok" "$CF_REG_OK" "ok"
OUT=$(wac_run regen)
echo "$OUT" | grep -q '"result":"replaced"' && ok "regen: ключи через живой туннель" || fail "regen: ключи через живой туннель ($OUT)"
grep -q "регистрируем через него" "$WAC_LOG_FILE" && ok "regen: лог туннельного пути" || fail "regen: лог туннельного пути"
wac_teardown

summary
