# luci-app-warp-autocheck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Автономный LuCI-пакет для OpenWrt, который периодически проверяет работоспособность WARP-конфига (интерфейс AmneziaWG) и при его смерти автоматически перегенерирует конфиг «с проверкой» (как кнопка Zapret Manager) и переприменяет его.

**Architecture:** sh-бэкенд `/usr/bin/warp-autocheck` (проверка/генерация/замена + state-машина), вызываемый по cron (init-скрипт ставит часовую cron-строку) и через rpcd-плагин (`/usr/libexec/rpcd/warp-autocheck`) для страницы LuCI (JS view + ACL + menu.d). Логика проверки и генерации — собственная копия паттернов Zapret-Manager (source: `study/ZapretManager_LuCI.sh`).

**Tech Stack:** POSIX sh (ash/busybox), rpcd + jshn, cron, UCI, LuCI JS views, ipk-упаковка (opkg-формат).

**Spec:** `docs/superpowers/specs/2026-10-20-luci-app-warp-autocheck-design.md`

## Global Constraints

- **Git-операции запрещены** — в этом окружении git write-команды заблокированы; никаких `git init/commit/add`. Все шаги заканчиваются проверками, а не коммитами.
- Целевая среда: OpenWrt 24.10+ (opkg) и 25.12+ (apk); busybox ash; НЕ использовать bash-измы (никаких `local` в одну строку с присвоением массивов, `${var//}`, `+=`).
- Константы копировать из ZM дословно (значения в Task 3): `AWG_WARP_PEER="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="`, RU_COLOS="DME SVX LED KJA REN OVB KZN AER VVO", `AWG_CF_VER="a-6.11-2223"`, внешний генератор `MIXOMO_WARP_PRIMARY="https://santa-atmo.ru/warp/warp.php"`, boot-ключ/маски/порты/пулы — из `study/ZapretManager_LuCI.sh` строки 14762–14947, 6739–6749, 9651.
- Файл конфига по умолчанию `/root/WARP.conf`, права 600; запись — всегда через temp+`mv` (атомарно).
- Имя ubus-объекта: `luci.warp-autocheck`; пакет: `luci-app-warp-autocheck`; путь LuCI: `admin/services/warp-autocheck`; заголовок страницы: «WARP AutoCheck».
- Весь текст UI и логов — на русском.
- Все sh-скрипты проверяются `sh -n`, JSON — `python3 -m json.tool`, JS — `node --check`.

## Review Focus

1. **Упал WAN, а не WARP** — при недоступности интернета мимо туннеля проверка не должна считать конфиг мёртвым и regen не должен запускаться. Тест: Task 4, сценарий T2.
2. **Однократный сбой** — одна неудачная проверка (моргнула сеть) не приводит к замене: счётчик неудач растёт только по подтверждённым провалам и сбрасывается при ok. Тест: Task 4, сценарий T3.
3. **Интерфейс выключен вручную** (`network.<iface>.auto=0` и интерфейса нет в /sys) — статус «выключен вручную», замены нет. Тест: Task 4, сценарий T4.
4. **Атомарность записи** — обрыв посреди записи не оставляет битый `/root/WARP.conf`: запись только в temp-файл + `mv`, бэкап старого перед заменой. Тест: Task 3 (`case_04_regen.sh`, сценарий (c) — после отката WARP.conf побайтово равен бэкапу; плюс case_08 проверяет структуру).
5. **Гонка двух операций** — повторный `regen`/`run` при живом lock-файле молча выходит (не дёргает сеть повторно). Тест: Task 4, сценарий T6.

---

### Task 1: Скелет репозитория + UCI-конфиг + init-скрипт

**Files:**
- Create: `luci-app-warp-autocheck/Makefile`
- Create: `luci-app-warp-autocheck/files/etc/config/warp-autocheck`
- Create: `luci-app-warp-autocheck/files/etc/init.d/warp-autocheck`
- Create: `tests/run_tests.sh` (пустой каркас: запускает все `tests/case_*.sh`, печатает PASS/FAIL, exit 1 при провале)

**Interfaces:**
- Produces: UCI `/etc/config/warp-autocheck`, единственная секция `config main 'main'` с опциями: `enabled '0'`, `interval '6'`, `interface 'warp'`, `retries '2'`, `conf '/root/WARP.conf'`. Все задачи читают их через `uci -q get warp-autocheck.main.<opt>`.
- Produces: init-скрипт с командами start/stop/restart: управляет cron-строкой `* 0 * * * /usr/bin/warp-autocheck run # warp-autocheck` в `/etc/crontabs/root` (добавляет при enabled=1, убирает при stop), затем `/etc/init.d/cron restart`. Формат строки cron — ровно такой (метка в комментарии для идемпотентного sed).

- [ ] **Step 1: Создать структуру каталогов** `luci-app-warp-autocheck/files/...` по списку Files + `tests/`.
- [ ] **Step 2: Написать UCI-файл и init-скрипт** (шаблон init-скрипта — стандартный `/etc/rc.common`, функции `start/stop/restart`, idempotent через `grep -F 'warp-autocheck run'`).
- [ ] **Step 3: Проверки.** `sh -n` на init-скрипт; `python3 -m json.tool` — n/a; вручную: init-скрипт, исполненный с `PATH`-заглушкой (см. Task 2 Step 1), корректно добавляет/убирает cron-строку в фиктивном `/etc/crontabs/root` — минимальный тест `tests/case_01_cron.sh` со стабом cron.
- [ ] **Step 4: Написать Makefile** (стандартный OpenWrt: `Package/luci-app-warp-autocheck`, SECTION=luci, CATEGORY=LuCI, DEPENDS=+curl +amneziawg-tools, `Package/*/files` в INSTALL).

### Task 2: Каркас бэкенда + команда `status`

**Files:**
- Create: `luci-app-warp-autocheck/files/usr/bin/warp-autocheck` (далее — «бэкенд»)
- Create: `tests/stubs/` — стабы: `uci`, `awg`, `ip`, `curl`, `logger`, `jsonfilter`, `ifup`, `date` (обёртка с фейковым временем через `WAC_NOW`), управляются state-каталогом `WAC_TEST_ROOT` с файлами `/etc/config/*`, ответами curl и т.п.
- Create: `tests/case_02_status.sh`

**Interfaces:**
- Consumes: UCI-опции из Task 1.
- Produces: команды бэкенда `status`, `check`, `run`, `regen`, `log`. Общие функции: `log "<msg>"` (в лог и `logger -t warp-autocheck`), `cfg_get <opt>`, `state_get <key>`, `state_set <k> <v>` (файл `/tmp/warp-autocheck.state`, формат `key=value`), `with_lock <cmd>` (lock-файл `/tmp/warp-autocheck.lock`, flock-подобная проверка через `set -o noclobber` или проверку PID — busybox-совместимо).
- Produces: JSON `status`: `{"conf_exists":bool,"iface":"warp","iface_exists":bool,"iface_manual_off":bool,"endpoint":"...","hs_age":int|null,"enabled":bool,"interval":6,"retries":2,"last_check":int,"last_result":"none","last_detail":"","last_replace":0,"fails":0,"running":bool,"uptime":int}` — этот контракт используют rpcd-плагин (Task 5) и LuCI view (Task 6).

- [ ] **Step 1: Каркас стаб-харнесса.** `tests/stubs/*` — исполняемые стабы, подменяющие системные команды; `tests/common.sh` с функцией `wac_run <backend-args>` (запускает бэкенд с `PATH=tests/stubs:$PATH`, `WAC_TEST_ROOT`, `WAC_NOW`). Стаб `awg` читает команды (`show ... latest-handshakes`) и возвращает значение из `WAC_TEST_ROOT/awg_out`; стаб `curl` по URL отдаёт содержимое файлов из `WAC_TEST_ROOT/curl/<slug>` или пусто; стаб `uci` — mini-реализация get/show/set/delete/commit над `WAC_TEST_ROOT/etc/config/` в формате `sections` (это самый объёмный стаб, ~80 строк).
- [ ] **Step 2: Каркас бэкенда**: shebang `#!/bin/sh`, константы, `cfg_get`, state-функции, lock, log, разбор команд (`case "$1" in ...`).
- [ ] **Step 3: `cmd_status`** — собирает JSON из: существование `$CONF`; наличие amneziawg-интерфейса с именем `$IFACE` (`uci -q get network.$IFACE.proto = amneziawg`); `iface_manual_off` = auto=0 и нет `/sys/class/net/$IFACE`; endpoint из peer-секции (`uci -q get network.$IFACE_peer.endpoint_host/port` — peer-секцию искать как в ZM `_awg_peer_sec`: секция `network.<sec>=amneziawg_<IFACE>`); hs_age через `awg show $IFACE latest-handshakes`.
- [ ] **Step 4: Тест `case_02_status.sh`**: 3 сценария — (a) конфига нет → `conf_exists:false`; (b) конфиг есть, интерфейс есть → `iface_exists:true`, endpoint собран; (c) интерфейс proto!=amneziawg → `iface_exists:false`.

### Task 3: Проверка доступности (`check`) + реген (`regen`)

**Files:**
- Modify: `luci-app-warp-autocheck/files/usr/bin/warp-autocheck`
- Create: `tests/case_03_check.sh`
- Create: `tests/case_04_regen.sh`

**Interfaces:**
- Consumes: Task 2 (state, lock, cfg_get, status-контракт).
- Produces: `cmd_check` → печатает JSON `{"result":"ok|no-link|torn|ru-colo|no-iface|manual-off|wan-down","detail":"..."}` и пишет `state last_check/last_result/last_detail`. `cmd_regen` → JSON `{"result":"replaced|not-helped|regen-failed|rolled-back|skipped:<reason>"}`. Функции: `wan_ok`, `iface_check <iface>` (внутренняя, без WAN-предпроверки — переиспользуется пост-проверкой), `keys_register`, `try_conf <priv> <ip> <endpoint> <mask> [peer]` (возврат 0/1/2, где 2 = модуль не загружен), `pick_endpoint` (перебор портов×хостов×масок), `write_warp_conf <priv> <peer> <v4> <v6> <endpoint> <mask>`, `apply_iface <iface>`, `is_ru <colo>`.

- [ ] **Step 1: `wan_ok()`** — `curl -s --connect-timeout 5 --max-time 10 http://1.1.1.1/cdn-cgi/trace` (без `--interface`); пусто → ложь.
- [ ] **Step 2: `iface_check <iface>`** — по образцу ZM-`test` (строки 15757–15782 исходника): hs_age (`awg show`), trace через `curl --interface $iface` (cloudflare.com → 1.1.1.1 → ipinfo.io → api.ipify.org); нет ip → `no-link`; `warp=` не on/plus → `no-link`; ping-зонд как `_st_warp_probe` (10 пинг×0.2с, torn = ≥3 потерянных в хвосте) → `torn`; `_cf_meta` через `speed.cloudflare.com/meta` + `jsonfilter` → colo в `$RU_COLOS` → `ru-colo`; иначе `ok` (+ detail: colo, потери, rtt).
- [ ] **Step 3: `cmd_check`** — guard-цепочка: нет конфига → `no-conf`; нет интерфейса → `no-iface`; manual-off → `manual-off`; WAN мёртв → `wan-down` (счётчик fails НЕ растёт); иначе `iface_check`. При `ok` — fails=0; иначе fails+=1.
- [ ] **Step 4: `cmd_regen`** — lock; повторяет ZM-`do_awg_gen check` в упрощении:
  1. `keys_register`: `awg genkey` → POST `https://api.cloudflareclient.com/v0a4005/reg` (UA `okhttp/3.12.1`, тело как в `gen_WARP.sh` строка 121) → при провале — внешний генератор `$MIXOMO_WARP_PRIMARY` → при провале — через живые туннели (`--interface <живой awg-интерфейс>`) → при провале — временный boot-туннель (boot-ключи ZM, хосты 188.114.96.3/162.159.192.1/188.114.97.1 × порты × маски) — цепочка `_awg_keys_get`/`_awg_try` из ZM (строки 15021–15099, 15108–15136).
  2. `pick_endpoint`: порты `2408 500 4500 1701`, хосты `AWG_TEST_HOSTS` ZM + 2 случайных из `ST_WARP_POOLS`, маски: текущая I1 из WARP.conf → QUIC → iCloud-DNS → QUIC-2 → dns/stun/sip-генераторы (`_i1_dns/_stun/_sip` ZM, строки 14959–14985). Ограничения: ≤80 попыток, ≤7 мин. Победа: handshake + trace + colo не RU + не torn. Фолбэк-порядок: RU-точка / точка с handshake / стандартная — НО см. правило замены ниже.
  3. **Правило замены — ПЕРЕСМОТРЕНО** (см. таблицу «Решения», строка про RU-выход): RU-точка принимается как рабочая, как в ZM. Фолбэки «handshake без трафика» и «стандартная» — только в ручном режиме; в авто-режиме без зарубежной/RU-точки результат `not-helped`, конфиг не трогается.
  4. Запись: новый конфиг → temp-файл → `awg setconf` на тестовом интерфейсе → бэкап старого в `$CONF.bak` → `mv` temp → `$CONF`, `chmod 600`.
  5. `apply_iface`: из нового WARP.conf берёт PrivateKey/PublicKey/Endpoint/маски → `uci set network.$IFACE.private_key`, `network.$IFACE.awg_jc..awg_i1`, peer-секция `public_key/endpoint_host/endpoint_port` → `uci commit network` → `ifup $IFACE`.
  6. Пост-проверка: sleep 15 → `iface_check $IFACE`; ok → `replaced`, fails=0; не ok → **один откат**: восстановить `$CONF.bak` + старые uci-значения (сохранить перед записью), `ifup`, результат `rolled-back`.
- [ ] **Step 5: Тесты `case_03_check.sh`**: (a) trace отдаёт ip + warp=on + colo=AMS + потери 0 → `ok`; (b) trace пуст на всех URL → `no-link`; (c) colo=DME → `ru-colo`; (d) ping-зонд с потерей хвоста ≥3 → `torn`.
- [ ] **Step 6: Тесты `case_04_regen.sh`**: (a) ключи получены, точка AMS найдена → `replaced`, uci-поля обновлены, `ifup` вызван; (b) все точки RU → `not-helped`, WARP.conf побайтово не изменился; (c) post-check провалился → `rolled-back`, WARP.conf = бэкап; (d) curl стаб на CF API всегда пуст и туннелей нет → `regen-failed`, конфиг не тронут.

### Task 4: State-машина автопроверки (`run`)

**Files:**
- Modify: `luci-app-warp-autocheck/files/usr/bin/warp-autocheck`
- Create: `tests/case_05_run.sh`

**Interfaces:**
- Consumes: `cmd_check`, `cmd_regen` (Task 3), state (Task 2), UCI `enabled/interval/retries` (Task 1).
- Produces: `cmd_run` — вызывается из cron ежечасно. Алгоритм: (1) lock уже занят → выход; (2) `enabled=0` → выход; (3) uptime < 900 сек (грейс после ребута, `/proc/uptime`) → выход; (4) `now - last_check < interval*3600 - 300` → выход; (5) `cmd_check`; (6) если результат `ok` или не «смерть конфига» (ретриггерятся только `no-link`, `torn`, `ru-colo`) → выход; (7) повторные проверки: до `retries` раз с паузой 300 сек; (8) все провалены → `cmd_regen`. Все результаты — в лог.

- [ ] **Step 1: Реализовать `cmd_run`** (порядок guard'ов выше — существенен).
- [ ] **Step 2: Тест `case_05_run.sh`** (время — через стаб `date`/`WAC_NOW`, паузы — стаб `sleep` без ожидания): (T1) interval не прошёл → check не вызывался (счётчик вызовов в стабе); (T2) WAN down → `wan-down`, fails не изменился, regen не звался; (T3) один сбой → до retries повторов, при ok на 2-й → regen не звался, fails=0; (T4) manual-off → без regen; (T5) все проверки провалены → regen вызван 1 раз; (T6) lock-файл существует с живым PID → выход без действий.

### Task 5: rpcd-плагин + ACL + menu.d

**Files:**
- Create: `luci-app-warp-autocheck/files/usr/libexec/rpcd/warp-autocheck`
- Create: `luci-app-warp-autocheck/files/usr/share/rpcd/acl.d/luci-app-warp-autocheck.json`
- Create: `luci-app-warp-autocheck/files/usr/share/luci/menu.d/luci-app-warp-autocheck.json`

**Interfaces:**
- Consumes: бэкенд Task 2–4 (команды status/check/run/regen/log), UCI (Task 1).
- Produces: ubus-объект `luci.warp-autocheck` с методами: `status` (→ бэкенд status), `check` (запуск `cmd_check` в фоне через `nohup ... >/tmp/warp-autocheck.job 2>&1 &` с lock-защитой), `regen` (фоново, с confirm-ключом), `log` (→ `tail -n 100 /tmp/warp-autocheck.log` как `{"content":"..."}`), `get_settings`, `set_settings` (enabled/interval/interface/retries с валидацией: interval 1–168, retries 0–3, interface по маске `^[a-z][a-z0-9_]{0,10}$`). Плагин — копия паттерна ZM (строки 22471–22743): `list` через jshn `list_methods`, `call` с `case` диспетчером.

- [ ] **Step 1: rpcd-плагин** (шаблон ZM дословно, методы — из Produces).
- [ ] **Step 2: ACL**: read: status, log, get_settings; write: check, regen, set_settings; read.uci: `warp-autocheck`; write.uci: `warp-autocheck`.
- [ ] **Step 3: menu.d**: `admin/services/warp-autocheck` → title «WARP AutoCheck», order 65, alias на `admin/services/warp-autocheck/main`; subtree с `"action": {"type":"view","path":"warp-autocheck/main"}`.
- [ ] **Step 4: Проверки**: `sh -n` плагина; `python3 -m json.tool` обоих JSON; `python3`-тест, что список методов в `list` == методы в `call`-case == методы в ACL (минискрипт `tests/case_06_rpcd.py`).

### Task 6: LuCI страница (JS view)

**Files:**
- Create: `luci-app-warp-autocheck/files/www/luci-static/resources/view/warp-autocheck/main.js`

**Interfaces:**
- Consumes: ubus-методы Task 5; JSON-контракт статуса Task 2.
- Produces: страница `warp-autocheck/main`. Поведение (из spec): `conf_exists=false` → карточка-ошибка «WARP-конфиг не найден. Сгенерируйте WARP-конфиг в Zapret Manager (раздел AmneziaWG)» и стоп; иначе карточки «Статус» (конфиг, интерфейс, endpoint, результат последней проверки с цветным бейджем ok/no-link/torn/ru-colo, последняя замена), «Настройки» (checkbox enabled, number interval, text interface, dropdown retries, кнопка Сохранить → set_settings), «Действия» («Проверить сейчас» → check + polling status до завершения, «Заменить сейчас» → confirm-диалог «Это займёт до 10 минут…» → regen + polling), «Лог» (log → `<pre>`).

- [ ] **Step 1: JS view** в стиле ZM-страниц (паттерн `rpc.declare({object:'luci.warp-autocheck',...})`, `view.extend`, render-карточки, polling каждые 5 сек во время операции). Полл: после check/regen — опрос `status` раз в 3 сек, пока `running=true`.
- [ ] **Step 2: Проверка**: `node --check main.js`; минитест `tests/case_07_view.py` — regex на наличие: вызовы всех 6 ubus-методов, текст ошибки отсутствия конфига, confirm-диалога regen.

### Task 7: Упаковка (ipk) + установщик + финальная верификация

**Files:**
- Create: `build-ipk.sh`
- Create: `install.sh`
- Create: `CHANGELOG.md`, `README.md` (кратко: назначение, установка, настройки)
- Create: `tests/case_08_package.sh`

**Interfaces:**
- Consumes: всё дерево `luci-app-warp-autocheck/files/**`.
- Produces: `dist/luci-app-warp-autocheck_<ver>_all.ipk` (opkg-формат: ar с `debian-binary`, `control.tar.gz`, `data.tar.gz`) + `install.sh` для роутера (скачивает/берёт каталог files, раскладывает по путям, `chmod 755`, `/etc/init.d/warp-autocheck enable`, `rpcd reload`, `cron restart`, для apk-систем — те же файлы минус ipk).

- [ ] **Step 1: `build-ipk.sh`**: собирает data.tar.gz из files/** с правильными путями и правами (755 для bin/init/rpcd, 644 для json/js/config), control.tar.gz (Package, Version 0.1.0, Section, Depends: curl, amneziawg-tools), упаковка `ar`. Без SDK.
- [ ] **Step 2: `install.sh`**: POSIX sh, работа по SSH-сценарию «скопировать каталог и запустить на роутере»; повторный запуск — обновляет файлы, настройки UCI сохраняет (`uci -q get` до перезаписи дефолтов; дефолты — только если секции нет).
- [ ] **Step 3: Тест `case_08_package.sh`**: сборка ipk, распаковка (`ar x`, `tar tzf`), проверка: все пути на месте, права, control-поля; `tar -xzf` data и повторный прогон `sh -n` на распакованных скриптах.
- [ ] **Step 4: Финальный прогон**: `tests/run_tests.sh` — все кейсы PASS; `sh -n` на все sh; `python3 -m json.tool` на все json; `node --check` на js. Перечислить результаты проверки в финальном сообщении.
