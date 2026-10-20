#!/bin/sh
# Case 01: init-скрипт управляет cron-строкой идемпотентно
. "$(dirname "$0")/common.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$ROOT/luci-app-warp-autocheck/files/etc/init.d/warp-autocheck"

CRON_LINE='* 0 * * * /usr/bin/warp-autocheck run # warp-autocheck'

setup_root() {
	CRONTABS_FILE="$WAC_TMP/crontabs/root"
	mkdir -p "$WAC_TMP/crontabs"
	: > "$CRONTABS_FILE"
}

WAC_TMP="$(mktemp -d)"
setup_root

# (a) старт на пустом crontab: строка добавлена один раз
( . "$INIT"; cron_ensure ) >/dev/null 2>&1
N=$(grep -cF 'warp-autocheck run' "$CRONTABS_FILE")
assert_eq "$N" "1" "cron_ensure добавляет строку один раз"
assert_grep "$CRON_LINE" "$CRONTABS_FILE" "строка в точности как в плане"

# (b) повторный запуск идемпотентен
( . "$INIT"; cron_ensure ) >/dev/null 2>&1
N=$(grep -cF 'warp-autocheck run' "$CRONTABS_FILE")
assert_eq "$N" "1" "повторный cron_ensure не дублирует"

# (c) сторонняя строка cron не трогается
echo '0 4 * * * /usr/bin/something-else' >> "$CRONTABS_FILE"
( . "$INIT"; cron_remove ) >/dev/null 2>&1
assert_no_grep 'warp-autocheck run' "$CRONTABS_FILE" "cron_remove убирает строку"
assert_grep 'something-else' "$CRONTABS_FILE" "чужие строки не тронуты"

# (d) cron_remove на пустом файле — молча ok
( . "$INIT"; cron_remove ) >/dev/null 2>&1
assert_eq "$?" "0" "cron_remove на пустом файле не падает"

# (e) синтаксис
sh -n "$INIT" && ok "sh -n init-скрипта" || fail "sh -n init-скрипта"

# (f) UCI-конфиг содержит все опции с дефолтами из плана
UCI_CFG="$ROOT/luci-app-warp-autocheck/files/etc/config/warp-autocheck"
for opt in "enabled '0'" "interval '6'" "interface 'warp'" "retries '2'" "conf '/root/WARP.conf'"; do
	assert_grep "$opt" "$UCI_CFG" "UCI: option $opt"
done

rm -rf "$WAC_TMP"
summary
