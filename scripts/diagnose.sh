#!/bin/sh
#
# diagnose.sh — быстрая диагностика Re:HomeProxy из командной строки.
# Ничего не меняет, только читает состояние.
#
# Запуск: sh scripts/diagnose.sh

set -u

say() { printf '\n== %s ==\n' "$*"; }

say "OpenWrt"
[ -r /etc/openwrt_release ] && { . /etc/openwrt_release; echo "$DISTRIB_DESCRIPTION ($DISTRIB_ARCH)"; }
echo "Ядро Linux: $(uname -r)"

say "Пакеты"
for p in luci-app-re-homeproxy hiddify-core sing-box-extended kmod-nft-tproxy kmod-tun; do
	if command -v apk >/dev/null 2>&1; then apk info -e "$p" >/dev/null 2>&1 && echo "  установлен: $p"
	else opkg list-installed "$p" 2>/dev/null | grep -q "$p" && echo "  установлен: $p"; fi
done

say "Ядро прокси"
[ -x /usr/bin/hiddify-core ] && echo "  hiddify-core: $(/usr/bin/hiddify-core version 2>/dev/null | head -1)"
[ -x /usr/bin/sing-box ]    && echo "  sing-box: $(/usr/bin/sing-box version 2>/dev/null | head -1)"
[ -x /usr/bin/hiddify-core ] || [ -x /usr/bin/sing-box ] || echo "  ядро не установлено (Службы -> Re:HomeProxy -> Ядро и службы)"

say "Служба"
/etc/init.d/homeproxy enabled && echo "  автозапуск: включён" || echo "  автозапуск: выключен"
if pgrep -f 'hiddify-core|sing-box' >/dev/null 2>&1; then
	echo "  процесс: запущен"
	pgrep -af 'hiddify-core|sing-box' | sed 's/^/    /'
else
	echo "  процесс: НЕ запущен (запустите: /etc/init.d/homeproxy start)"
fi

say "Слушаемые порты прокси"
PORTS=$(uci -q get homeproxy.infra.mixed_port) ; PORTS="${PORTS:-5330}"
echo "  mixed=$PORTS"
netstat -ltnup 2>/dev/null | grep -E ":(5330|5331|5332|5333)\b" | sed 's/^/    /' || echo "    порты не слушаются"

say "Модули ядра"
lsmod 2>/dev/null | grep -E 'nft_tproxy|tun\b' | sed 's/^/  /' || echo "  nft_tproxy/tun не загружены"

say "Настройки маршрутизации"
echo "  режим:            $(uci -q get homeproxy.config.routing_mode)"
echo "  основной узел:    $(uci -q get homeproxy.config.main_node)"
echo "  режим прокси:     $(uci -q get homeproxy.config.proxy_mode)"
echo "  поддержка IPv6:   $(uci -q get homeproxy.config.ipv6_support)"

say "Подписки"
if uci -q show homeproxy | grep -q "=subscription"; then
	uci -q show homeproxy | grep -E '\.(url|auto_update)=' | sed 's/^/  /'
else
	echo "  подписок не настроено"
fi

say "Свободное место"
df -h /overlay /tmp 2>/dev/null | sed 's/^/  /'

say "Проверка соединения (IP провайдера)"
if command -v curl >/dev/null 2>&1; then
	echo "  прямой IP:  $(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || echo 'нет')"
	echo "  через прокси (порт 5330): $(curl -s --max-time 8 -x socks5h://127.0.0.1:5330 https://api.ipify.org 2>/dev/null || echo 'нет/недоступно')"
else
	echo "  curl не установлен — пропускаю"
fi

echo
echo "Если IP совпадают — трафик НЕ проксируется. Проверьте узел и правила в LuCI."
echo "Если порты не слушаются — запустите службу и посмотрите логи (Ядро и службы -> Логи)."
