#!/bin/sh
#
# uninstall.sh — удаление Re:HomeProxy, ядра и модулей с роутера.
# Конфигурация homeproxy (/etc/config/homeproxy) НЕ удаляется, если не указан --purge.
#
# Запуск:
#   sh scripts/uninstall.sh            # снять приложение, ядро, kmod
#   sh scripts/uninstall.sh --purge    # + удалить конфиг, списки и сертификаты
#   sh scripts/uninstall.sh --keep-core # оставить ядро прокси

set -u

PURGE=0
KEEP_CORE=0
for a in "$@"; do
	case "$a" in
		--purge)     PURGE=1 ;;
		--keep-core) KEEP_CORE=1 ;;
		*) echo "Неизвестный аргумент: $a" >&2; exit 1 ;;
	esac
done

[ "$(id -u)" = "0" ] || { echo "Запустите от root." >&2; exit 1; }

if command -v apk >/dev/null 2>&1; then PM=apk; else PM=opkg; fi

echo "== Останавливаю службу =="
/etc/init.d/homeproxy stop     >/dev/null 2>&1
/etc/init.d/homeproxy disable  >/dev/null 2>&1

echo "== Удаляю приложение =="
if [ "$PM" = apk ]; then apk del luci-app-re-homeproxy >/dev/null 2>&1 || true
else opkg remove luci-app-re-homeproxy >/dev/null 2>&1 || true; fi

if [ "$KEEP_CORE" = 0 ]; then
	echo "== Удаляю ядро прокси =="
	if [ "$PM" = apk ]; then apk del hiddify-core sing-box-extended >/dev/null 2>&1 || true
	else opkg remove hiddify-core sing-box-extended >/dev/null 2>&1 || true; fi
else
	echo "== Ядро оставлено (--keep-core) =="
fi

if [ "$PURGE" = 1 ]; then
	echo "== Удаляю конфигурацию и данные =="
	rm -f  /etc/config/homeproxy
	rm -rf /etc/homeproxy
	rm -rf /usr/share/homeproxy
	rm -f  /etc/apk/keys/homeproxy-hiddify.pub
	[ "$PM" = opkg ] && rm -f /etc/opkg/keys/* 2>/dev/null
fi

/etc/init.d/rpcd restart >/dev/null 2>&1

echo
echo "== Готово =="
[ "$PURGE" = 0 ] && echo "Конфиг сохранён: /etc/config/homeproxy (для полного удаления: --purge)"
echo "Модули ядра kmod-nft-tproxy/kmod-tun не тронуты — они безопасны и могут использоваться другими."
