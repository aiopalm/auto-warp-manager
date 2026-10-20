#!/usr/bin/env python3
# Case 07: LuCI view — контракт страницы
import re, subprocess, sys, os

VIEW = os.path.join(os.path.dirname(__file__), "..", "luci-app-warp-autocheck",
                    "files", "www", "luci-static", "resources", "view", "warp-autocheck", "main.js")

checks = []
def ok(msg): checks.append(("ok", msg))
def fail(msg): checks.append(("FAIL", msg))

try:
    src = open(VIEW).read()
except FileNotFoundError:
    print("FAIL: view не существует")
    sys.exit(1)

# (a) все 6 ubus-методов объявлены
for m in ["status", "check", "regen", "log", "get_settings", "set_settings"]:
    if re.search(r"method:\s*'%s'" % m, src):
        ok("view: метод %s объявлен" % m)
    else:
        fail("view: метод %s объявлен" % m)

# (a2) set_settings объявлен с именованными параметрами (иначе rpcd получает массив)
if re.search(r"method:\s*'set_settings',\s*params:\s*\[", src):
    ok("view: set_settings с params")
else:
    fail("view: set_settings с params (rpcd получит безымянный массив)")

# (b) ошибка при отсутствии WARP.conf
if "Сгенерируйте WARP-конфиг в Zapret Manager" in src:
    ok("view: ошибка отсутствия конфига")
else:
    fail("view: ошибка отсутствия конфига")

# (c) confirm перед regen (ui.showModal с кнопкой «Заменить» или ui.confirm)
if ("showModal" in src or "confirm" in src) and "Заменить" in src:
    ok("view: confirm замены")
else:
    fail("view: confirm замены")

# (d) опрос статуса + собственные стили (не зависят от темы)
if re.search(r"poll|setTimeout|requestAnimationFrame", src):
    ok("view: polling статуса")
else:
    fail("view: polling статуса")
if "ensureStyles" in src and "wac-styles" in src and ".wac-badge" in src:
    ok("view: собственные стили внедряются")
else:
    fail("view: собственные стили внедряются")

# (e) node --check
r = subprocess.run(["node", "--check", VIEW], capture_output=True, text=True)
if r.returncode == 0:
    ok("view: node --check")
else:
    fail("view: node --check: %s" % r.stderr[:200])

failed = [c for c in checks if c[0] == "FAIL"]
for st, msg in checks:
    print("  %s - %s" % (st, msg))
print("PASS=%d FAIL=%d" % (len(checks) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
