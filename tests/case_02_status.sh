#!/bin/sh
# Case 02: команда status — JSON-контракт
. "$(dirname "$0")/common.sh"

TRACE_URL="https://www.cloudflare.com/cdn-cgi/trace"

# (a) конфига нет -> conf_exists:false, enabled:true
wac_setup; wac_put_config 1 6 warp 2
wac_clock 1700000000
OUT=$(wac_run status)
echo "$OUT" | grep -q '"conf_exists":false' && ok "status: conf_exists=false" || fail "status: conf_exists=false ($OUT)"
wac_teardown

# (b) конфиг есть + amneziawg-интерфейс есть
wac_setup
wac_put_config 1 6 warp 2 /root/WARP.conf
# конфиг «есть»: бэкенд проверяет путь из UCI, в тестах — через WAC_CONF_OVERRIDE
{ : > "$WAC_TEST_ROOT/WARP.conf"; echo "[Interface]"; } > "$WAC_TEST_ROOT/WARP.conf"
export WAC_CONF_OVERRIDE="$WAC_TEST_ROOT/WARP.conf"
wac_put_network warp amneziawg 162.159.192.1 2408
echo 1699999700 > "$WAC_TEST_ROOT/awg/warp.handshakes"   # hs 300 сек назад
wac_clock 1700000000
OUT=$(wac_run status)
echo "$OUT" | grep -q '"conf_exists":true' && ok "status: conf_exists=true" || fail "status: conf_exists=true ($OUT)"
echo "$OUT" | grep -q '"iface_exists":true' && ok "status: iface_exists=true" || fail "status: iface_exists=true ($OUT)"
echo "$OUT" | grep -q '"endpoint":"162.159.192.1:2408"' && ok "status: endpoint собран" || fail "status: endpoint собран ($OUT)"
echo "$OUT" | grep -q '"hs_age":300' && ok "status: hs_age=300" || fail "status: hs_age=300 ($OUT)"
echo "$OUT" | grep -q '"enabled":true' && ok "status: enabled=true" || fail "status: enabled=true ($OUT)"
wac_teardown

# (c) интерфейс не amneziawg -> iface_exists:false
wac_setup; wac_put_config 0 6 warp 2
: > "$WAC_TEST_ROOT/WARP.conf"
wac_put_network warp pppoe
wac_clock 1700000000
OUT=$(wac_run status)
echo "$OUT" | grep -q '"iface_exists":false' && ok "status: iface_exists=false (не awg)" || fail "status: iface_exists=false ($OUT)"
wac_teardown

# (d) JSON валиден
wac_setup; wac_put_config 1 6 warp 2
{ : > "$WAC_TEST_ROOT/WARP.conf"; echo "[Interface]"; } > "$WAC_TEST_ROOT/WARP.conf"
export WAC_CONF_OVERRIDE="$WAC_TEST_ROOT/WARP.conf"
wac_put_network warp amneziawg
wac_clock 1700000000
wac_run status | python3 -c 'import json,sys; json.load(sys.stdin)' && ok "status: JSON валиден" || fail "status: JSON валиден"
wac_teardown

summary
