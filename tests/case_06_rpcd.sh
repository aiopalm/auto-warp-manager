#!/bin/sh
# Case 06: rpcd-плагин (согласованность методов) + get_settings/set_settings
. "$(dirname "$0")/common.sh"

PLUGIN="$ROOT/luci-app-warp-autocheck/files/usr/libexec/rpcd/warp-autocheck"
ACL="$ROOT/luci-app-warp-autocheck/files/usr/share/rpcd/acl.d/luci-app-warp-autocheck.json"
MENU="$ROOT/luci-app-warp-autocheck/files/usr/share/luci/menu.d/luci-app-warp-autocheck.json"

# (a) синтаксис и JSON
sh -n "$PLUGIN" && ok "rpcd: sh -n" || fail "rpcd: sh -n"
python3 -m json.tool "$ACL" >/dev/null && ok "rpcd: ACL JSON валиден" || fail "rpcd: ACL JSON"
python3 -m json.tool "$MENU" >/dev/null && ok "rpcd: menu JSON валиден" || fail "rpcd: menu JSON"

# (b) список методов: list == case == ACL.read+write
METHODS_LIST=$(JSHN_LIB="$ROOT/tests/stubs/jshn.sh" "$PLUGIN" list 2>/dev/null | python3 -c 'import json,sys
s = sys.stdin.read()
d = json.loads(s) if s.strip().startswith("{") else {}
attrs = {"enabled", "interface", "interval", "retries"}  # атрибуты set_settings — артефакт стаба jshn (без вложенности)
print("\n".join(sorted(k for k in d.keys() if k not in attrs)))')
METHODS_CASE=$(grep -oE '^[[:space:]]{2}[a-z_]+\)' "$PLUGIN" | sed 's/^[[:space:]]*//; s/)$//' | sort -u)
METHODS_ACL=$(python3 -c '
import json
a = json.load(open("'"$ACL"'"))["luci-app-warp-autocheck"]
ms = sorted(set(a["read"]["ubus"]["luci.warp-autocheck"] + a["write"]["ubus"]["luci.warp-autocheck"]))
print("\n".join(ms))')
assert_eq "$METHODS_LIST" "$METHODS_CASE" "rpcd: методы list == case"
assert_eq "$METHODS_LIST" "$METHODS_ACL" "rpcd: методы list == ACL"

# (c) get_settings возвращает дефолты
wac_setup; wac_put_config 1 6 warp 2 /root/WARP.conf
OUT=$(wac_run get_settings)
echo "$OUT" | grep -q '"enabled":true' && ok "settings: enabled" || fail "settings: enabled ($OUT)"
echo "$OUT" | grep -q '"interval":6' && ok "settings: interval" || fail "settings: interval ($OUT)"
echo "$OUT" | grep -q '"interface":"warp"' && ok "settings: interface" || fail "settings: interface ($OUT)"
wac_teardown

# (d) set_settings пишет и валидирует
wac_setup; wac_put_config 0 6 warp 2 /root/WARP.conf
OUT=$(wac_run set_settings 1 12 warp2 3)
echo "$OUT" | grep -q '"ok":true' && ok "settings: set ok" || fail "settings: set ok ($OUT)"
assert_eq "$(wac_run get_settings | grep -o '"interval":[0-9]*' | cut -d: -f2)" "12" "settings: interval=12 сохранён"
assert_eq "$(wac_run get_settings | grep -o '"interface":"[a-z0-9]*"' | cut -d'"' -f4)" "warp2" "settings: interface сохранён"
OUT=$(wac_run set_settings 1 999 warp 2)   # невалидный интервал
echo "$OUT" | grep -q '"ok":true' && fail "settings: interval 999 отклонён" || ok "settings: interval 999 отклонён"
OUT=$(wac_run set_settings 1 6 Warp1 2)    # невалидное имя
echo "$OUT" | grep -q '"ok":true' && fail "settings: имя Warp1 отклонено" || ok "settings: имя Warp1 отклонено"
OUT=$(wac_run set_settings 1 6 warp 9)     # невалидные retries
echo "$OUT" | grep -q '"ok":true' && fail "settings: retries 9 отклонён" || ok "settings: retries 9 отклонён"
wac_teardown

summary
