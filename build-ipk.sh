#!/bin/sh
# Сборка luci-app-warp-autocheck_<ver>_all.ipk (opkg-формат) без OpenWrt SDK
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
PKG_DIR="luci-app-warp-autocheck"
VERSION="0.1.0"
RELEASE="1"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"

trap 'rm -rf "$STAGE"' EXIT

# --- control ----------------------------------------------------------------
mkdir -p "$STAGE/control"
cat > "$STAGE/control/control" <<EOF
Package: luci-app-warp-autocheck
Version: $VERSION-$RELEASE
Depends: curl, amneziawg-tools
Architecture: all
Section: luci
Description: Автопроверка и автозамена WARP-конфига (AmneziaWG). Периодически проверяет работоспособность WARP-туннеля и при недоступности генерирует новый конфиг с подбором точки входа.
Maintainer: WARP AutoCheck contributors
Source: https://github.com/StressOzz/Zapret-Manager
Installed-Size: $(du -sk "$PKG_DIR/files" | cut -f1)
EOF
echo "2.0" > "$STAGE/debian-binary"

# --- data -------------------------------------------------------------------
mkdir -p "$STAGE/data"
( cd "$PKG_DIR/files" && cp -R . "$STAGE/data/" )
chmod -R u+rwX "$STAGE/data"
chmod 755 "$STAGE/data/usr/bin/warp-autocheck" \
	"$STAGE/data/etc/init.d/warp-autocheck" \
	"$STAGE/data/usr/libexec/rpcd/warp-autocheck"
chmod 644 "$STAGE/data/etc/config/warp-autocheck" \
	"$STAGE/data/usr/share/rpcd/acl.d/luci-app-warp-autocheck.json" \
	"$STAGE/data/usr/share/luci/menu.d/luci-app-warp-autocheck.json" \
	"$STAGE/data/www/luci-static/resources/view/warp-autocheck/main.js"
( cd "$STAGE/data" && tar czf "$STAGE/data.tar.gz" --owner=0 --group=0 . )
( cd "$STAGE/control" && tar czf "$STAGE/control.tar.gz" --owner=0 --group=0 . )

mkdir -p "$DIST"
rm -f "$DIST"/luci-app-warp-autocheck_*_all.ipk
# ar-архив пишем вручную: macOS ar добавляет SYMDEF, который opkg не понимает
python3 - "$STAGE" "$DIST/luci-app-warp-autocheck_${VERSION}-${RELEASE}_all.ipk" <<'PYEOF'
import sys, os
stage, out = sys.argv[1], sys.argv[2]
members = [('debian-binary', b'2.0\n'),
           ('control.tar.gz', open(os.path.join(stage, 'control.tar.gz'), 'rb').read()),
           ('data.tar.gz', open(os.path.join(stage, 'data.tar.gz'), 'rb').read())]
def hdr(name, size):
    return ('%-16s%-12s%-6s%-6s%-8s%-10s`\n' % (name + '/', '0', '0', '0', '100644', str(size))).encode()
with open(out, 'wb') as f:
    f.write(b'!<arch>\n')
    for name, data in members:
        f.write(hdr(name, len(data)))
        f.write(data)
        if len(data) % 2: f.write(b'\n')
print('ar ok')
PYEOF
echo "OK: $DIST/luci-app-warp-autocheck_${VERSION}-${RELEASE}_all.ipk"
