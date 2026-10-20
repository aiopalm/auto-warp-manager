# luci-app-warp-autocheck — автопроверка и автозамена WARP-конфига
# Для OpenWrt SDK: make package/luci-app-warp-autocheck/compile

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-warp-autocheck
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=WARP AutoCheck contributors

LUCI_TITLE:=Автопроверка и автозамена WARP-конфига (AmneziaWG)
LUCI_DESCRIPTION:=Периодически проверяет работоспособность WARP-конфига (интерфейс AmneziaWG, /root/WARP.conf) и при недоступности автоматически генерирует новый с подбором точки входа и переприменяет его.
LUCI_DEPENDS:=+curl +amneziawg-tools
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/warp-autocheck
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
rm -f /usr/libexec/rpcd/warp-autocheck
if [ -x /etc/init.d/warp-autocheck ]; then
	/etc/init.d/warp-autocheck enable
	/etc/init.d/warp-autocheck start
fi
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart
exit 0
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/warp-autocheck $(1)/usr/bin/warp-autocheck
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/warp-autocheck $(1)/etc/init.d/warp-autocheck
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/warp-autocheck $(1)/etc/config/warp-autocheck
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/luci.warp-autocheck $(1)/usr/libexec/rpcd/luci.warp-autocheck
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-warp-autocheck.json $(1)/usr/share/rpcd/acl.d/luci-app-warp-autocheck.json
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-warp-autocheck.json $(1)/usr/share/luci/menu.d/luci-app-warp-autocheck.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/warp-autocheck
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/warp-autocheck/main.js $(1)/www/luci-static/resources/view/warp-autocheck/main.js
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
