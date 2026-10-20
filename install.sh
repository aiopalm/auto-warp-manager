#!/bin/sh
# Установщик luci-app-warp-autocheck.
#
# Быстрая установка с гита (на роутере, под root):
#   wget -qO - https://raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh | sh
#
# Локально из клона репозитория:
#   ./install.sh --local
#
# Копирование на роутер по SSH из клона:
#   ./install.sh root@192.168.1.1

REPO_TARBALL="https://github.com/aiopalm/auto-warp-manager/archive/refs/heads/main.tar.gz"
PKG_SRC="auto-warp-manager-main/luci-app-warp-autocheck/files"
PKG_DIR="luci-app-warp-autocheck/files"
TMP_DIR="/tmp/warp-autocheck-install"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

# --- определить, откуда брать файлы -----------------------------------------
install_from() { # каталог с содержимым files/
	local src="$1"
	echo "==> Копируем файлы"

	for f in \
		usr/bin/warp-autocheck \
		etc/init.d/warp-autocheck \
		usr/libexec/rpcd/luci.warp-autocheck; do
		cp -f "$src/$f" "/$f" || die "не удалось скопировать $f"
		chmod 755 "/$f"
	done
	# уборка плагина до переименования (иначе rpcd покажет битый второй объект)
	rm -f /usr/libexec/rpcd/warp-autocheck
	for f in \
		etc/config/warp-autocheck \
		usr/share/rpcd/acl.d/luci-app-warp-autocheck.json \
		usr/share/luci/menu.d/luci-app-warp-autocheck.json \
		www/luci-static/resources/view/warp-autocheck/main.js; do
		mkdir -p "$(dirname "/$f")"
		[ -f "/$f" ] || cp "$src/$f" "/$f"   # не затирать существующие настройки
		chmod 644 "/$f"
	done
}

activate() {
	echo "==> Проверяем зависимости"
	command -v curl >/dev/null 2>&1 || echo "   ! нет curl — установите: opkg install curl (или apk add curl)"
	command -v awg >/dev/null 2>&1 || echo "   ! нет awg — установите AmneziaWG (амнезиа-утилиты)"

	echo "==> Включаем службу"
	/etc/init.d/warp-autocheck enable
	/etc/init.d/warp-autocheck start

	echo "==> Перезапускаем rpcd и cron"
	/etc/init.d/rpcd restart 2>/dev/null || /etc/init.d/rpcd reload
	/etc/init.d/cron restart 2>/dev/null || true

	echo
	echo "Готово: WARP AutoCheck установлен"
	echo "LuCI: Службы → WARP AutoCheck"
	echo
	echo "Если WARP-конфига ещё нет — сгенерируйте его в Zapret Manager (раздел AmneziaWG),"
	echo "затем импортируйте WARP.conf как интерфейс и укажите его имя на странице пакета."
}

install_local() {
	# файлы лежат рядом? (клон репозитория / scp-режим / скачанный архив)
	if [ -d "$PKG_DIR" ]; then
		install_from "$PKG_DIR"
	elif [ -d "$TMP_DIR/files" ]; then
		install_from "$TMP_DIR/files"
		activate
		cleanup_tmp
	elif [ -d "$TMP_DIR/$PKG_SRC" ]; then
		install_from "$TMP_DIR/$PKG_SRC"
		cleanup_tmp
		activate
	else
		# установка с гита: скачаем архив репозитория
		download_and_install
		return
	fi
}

download_and_install() {
	echo "==> Скачиваем файлы из репозитория"
	mkdir -p "$TMP_DIR"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$REPO_TARBALL" -o "$TMP_DIR/repo.tar.gz" || { cleanup_tmp; die "не удалось скачать $REPO_TARBALL"; }
	else
		wget -qO "$TMP_DIR/repo.tar.gz" "$REPO_TARBALL" || { cleanup_tmp; die "не удалось скачать $REPO_TARBALL"; }
	fi
	[ "$(wc -c < "$TMP_DIR/repo.tar.gz" 2>/dev/null | tr -d ' ')" -gt 1000 ] || { cleanup_tmp; die "файл скачался не целиком"; }
	tar xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR" || { cleanup_tmp; die "архив повреждён"; }
	[ -d "$TMP_DIR/$PKG_SRC" ] || { cleanup_tmp; die "в архиве нет $PKG_SRC"; }
	install_from "$TMP_DIR/$PKG_SRC"
	cleanup_tmp
	activate
}

cleanup_tmp() { rm -rf "$TMP_DIR"; }

uninstall() {
	echo "==> Останавливаем службу и убираем cron-строку"
	[ -x /etc/init.d/warp-autocheck ] && /etc/init.d/warp-autocheck disable 2>/dev/null
	[ -x /etc/init.d/warp-autocheck ] && /etc/init.d/warp-autocheck stop 2>/dev/null

	echo "==> Удаляем файлы пакета"
	rm -f /usr/bin/warp-autocheck
	rm -f /etc/init.d/warp-autocheck
	rm -f /usr/libexec/rpcd/luci.warp-autocheck
	rm -f /usr/libexec/rpcd/warp-autocheck   # старый плагин до переименования
	rm -f /usr/share/rpcd/acl.d/luci-app-warp-autocheck.json
	rm -f /usr/share/luci/menu.d/luci-app-warp-autocheck.json
	rm -rf /www/luci-static/resources/view/warp-autocheck
	rm -f /etc/config/warp-autocheck
	rm -rf /tmp/warp-autocheck.run
	rm -f /tmp/warp-autocheck.state /tmp/warp-autocheck.log /tmp/warp-autocheck.lock /tmp/warp-autocheck.job

	echo "==> Перезапускаем rpcd и cron"
	/etc/init.d/rpcd restart 2>/dev/null || /etc/init.d/rpcd reload
	/etc/init.d/cron restart 2>/dev/null || true

	echo
	echo "Готово: WARP AutoCheck удалён."
	echo "Тронутое только наш пакет. Интерфейсы AmneziaWG, /root/WARP.conf и сам AmneziaWG — не тронуты."
}

# --- режимы ------------------------------------------------------------------
case "${1:-}" in
	--uninstall|-u)
		uninstall
		;;
	--local)
		install_local
		;;
	""|--)
		# запущено как «wget -qO - url | sh» — ставим с гита
		download_and_install
		;;
	-*)
		die "использование: $0 [--local | root@router-ip]"
		;;
	*)
		# скопировать на роутер по SSH из клона
		REMOTE="$1"
		echo "==> Копируем файлы на $REMOTE"
		ssh "$REMOTE" "mkdir -p $TMP_DIR"
		scp -r "$PKG_DIR" "$REMOTE:$TMP_DIR/files"
		scp install.sh "$REMOTE:$TMP_DIR/install.sh"
		echo "==> Устанавливаем на роутере"
		ssh "$REMOTE" "sh $TMP_DIR/install.sh --local"
		ssh "$REMOTE" "rm -rf $TMP_DIR"
		echo "Готово."
		;;
esac
