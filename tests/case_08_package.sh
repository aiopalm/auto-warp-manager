#!/bin/sh
# Case 08: сборка ipk и установщик
. "$(dirname "$0")/common.sh"

PKG_DIR="$ROOT/luci-app-warp-autocheck"
DIST="$ROOT/dist"

# (a) сборка без ошибок
rm -rf "$DIST"
sh "$ROOT/build-ipk.sh" >/dev/null 2>&1 && ok "build: скрипт отработал" || fail "build: скрипт отработал"
[ -f "$DIST"/luci-app-warp-autocheck_*_all.ipk ] && ok "build: ipk создан" || fail "build: ipk создан ($(ls "$DIST" 2>/dev/null))"

IPK=$(ls "$DIST"/luci-app-warp-autocheck_*_all.ipk 2>/dev/null | head -n1)
[ -n "$IPK" ] || { echo "нет ipk — стоп"; summary; exit 1; }

# (b) структура ar-архива (свой экстрактор: macOS ar не понимает GNU-имена с «/»)
python3 - "$IPK" <<'PYEOF' && ok "ipk: структура корректна" || fail "ipk: структура корректна"
import sys, os, tarfile, io

ipk = sys.argv[1]
data = open(ipk, 'rb').read()
assert data.startswith(b'!<arch>\n'), 'не ar-архив'
pos = 8
members = {}
ok = True
while pos < len(data):
    hdr = data[pos:pos+60]
    if len(hdr) < 60: break
    name = hdr[0:16].decode().strip().rstrip('/')
    size = int(hdr[48:58].decode().strip())
    body = data[pos+60:pos+60+size]
    members[name] = body
    pos += 60 + size + (size % 2)

def check(cond, msg):
    print(('  ok  - ' if cond else '  FAIL - ') + msg)
    return cond

failed = []
ok = True
ok &= check('debian-binary' in members and members['debian-binary'] == b'2.0\n', 'ipk: debian-binary')
ok &= check('control.tar.gz' in members, 'ipk: control.tar.gz')
ok &= check('data.tar.gz' in members, 'ipk: data.tar.gz')

control = members.get('control.tar.gz', b'')
tf = tarfile.open(fileobj=io.BytesIO(control))
ctrl = tf.extractfile('./control').read().decode()
ok &= check('Package: luci-app-warp-autocheck' in ctrl, 'ipk: control Package')
ok &= check('curl' in ctrl and 'amneziawg-tools' in ctrl, 'ipk: Depends')

df = tarfile.open(fileobj=io.BytesIO(members['data.tar.gz']))
names = df.getnames()
expected = [
    './usr/bin/warp-autocheck', './etc/init.d/warp-autocheck', './etc/config/warp-autocheck',
    './usr/libexec/rpcd/luci.warp-autocheck', './usr/share/rpcd/acl.d/luci-app-warp-autocheck.json',
    './usr/share/luci/menu.d/luci-app-warp-autocheck.json',
    './www/luci-static/resources/view/warp-autocheck/main.js']
for e in expected:
    ok &= check(e in names, 'ipk: ' + e)

import stat
for e, name in [('./usr/bin/warp-autocheck', 'bin'), ('./usr/libexec/rpcd/luci.warp-autocheck', 'rpcd')]:
    m = df.getmember(e).mode
    ok &= check(m & stat.S_IXUSR != 0, 'ipk: %s исполняемый' % name)

import subprocess, tempfile
tmp = tempfile.mkdtemp()
df.extractall(tmp)
for f in ['./usr/bin/warp-autocheck', './etc/init.d/warp-autocheck']:
    r = subprocess.run(['sh', '-n', os.path.join(tmp, f[2:])], capture_output=True)
    ok &= check(r.returncode == 0, 'ipk: sh -n %s' % f)

sys.exit(0 if ok else 1)
PYEOF

# (f) install.sh: синтаксис, гит-однострочник, режимы install/uninstall
[ -f "$ROOT/install.sh" ] && sh -n "$ROOT/install.sh" && ok "install.sh" || fail "install.sh"
grep -q "raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh" "$ROOT/install.sh" && ok "install.sh: гит-однострочник согласован" || fail "install.sh: гит-однострочник"
grep -q "REPO_TARBALL=\"https://github.com/aiopalm/auto-warp-manager" "$ROOT/install.sh" && ok "install.sh: tarball из репо" || fail "install.sh: tarball из репо"
grep -q "uninstall()" "$ROOT/install.sh" && ok "install.sh: режим удаления" || fail "install.sh: режим удаления"
grep -q "rm -rf /www/luci-static/resources/view/warp-autocheck" "$ROOT/install.sh" && ok "install.sh: удаление удаляет файлы пакета" || fail "install.sh: удаление"
grep -qE 'rm .*/root/WARP\.conf$' "$ROOT/install.sh" && fail "install.sh: WARP.conf НЕ должен удаляться" || ok "install.sh: WARP.conf не удаляется"

# (g) обновление перезаписывает страницу, но не настройки
if grep -q 'cp -f "\$src/\$f"' "$ROOT/install.sh" && ! grep -q '\[ -f "/\$f" \] || cp' "$ROOT/install.sh"; then
	ok "install.sh: main.js перезаписывается при обновлении"
else
	fail "install.sh: main.js перезаписывается при обновлении"
fi
if grep -q '\[ ! -f /etc/config/warp-autocheck \]' "$ROOT/install.sh"; then
	ok "install.sh: настройки не затираются"
else
	fail "install.sh: настройки не затираются"
fi

# (g) .gitignore не пускает артефакты
grep -q "^dist/" "$ROOT/.gitignore" && grep -q "^.superpowers/" "$ROOT/.gitignore" && ok ".gitignore" || fail ".gitignore"

summary
