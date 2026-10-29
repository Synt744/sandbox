#!/bin/sh
#
# add-subscription.sh — добавить ссылку подписки Hiddify из командной строки
#                       (альтернатива ручному вводу в LuCI).
#
# Запуск (на роутере, от root):
#   sh scripts/add-subscription.sh "https://ваш-домен/sub/ВАШ-ТОКЕН"
#   sh scripts/add-subscription.sh "URL" --ua "Hiddify/2.5.7" --auto
#
# Флаги:
#   --auto        включить автообновление подписки
#   --hour N      час автообновления (0-23, по умолчанию 2)
#   --ua STRING   свой User-Agent (Hiddify отдаёт sing-box JSON по UA)
#   --replace     заменить все существующие подписки этой одной
#
# После добавления:
#   ucode /etc/homeproxy/scripts/update_subscriptions.uc   # скачать узлы сейчас
#   /etc/init.d/homeproxy restart

set -u

URL="${1:-}"
[ -n "$URL" ] || { echo "Использование: sh add-subscription.sh <URL> [--auto] [--hour N] [--ua STR] [--replace]" >&2; exit 1; }
shift

AUTO=0; HOUR=2; UA=""; REPLACE=0
while [ $# -gt 0 ]; do
	case "$1" in
		--auto)    AUTO=1; shift ;;
		--hour)    HOUR="${2:-2}"; shift 2 ;;
		--ua)      UA="${2:-}"; shift 2 ;;
		--replace) REPLACE=1; shift ;;
		*) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
	esac
done

[ "$(id -u)" = "0" ] || { echo "Запустите от root." >&2; exit 1; }
[ -f /etc/config/homeproxy ] || { echo "Приложение homeproxy не установлено." >&2; exit 1; }

if [ "$REPLACE" = 1 ]; then
	while uci -q delete homeproxy.subscription.subscription_url; do :; done
fi

uci add_list homeproxy.subscription.subscription_url="$URL"

[ "$AUTO" = 1 ] && uci set homeproxy.subscription.auto_update=1
[ "$AUTO" = 1 ] && uci set homeproxy.subscription.update_time="$HOUR"
[ -n "$UA" ]    && uci set homeproxy.subscription.user_agent="$UA"

uci commit homeproxy
echo "Подписка добавлена: $URL"

echo "Скачиваю узлы..."
if ! ucode /etc/homeproxy/scripts/update_subscriptions.uc 2>/dev/null; then
	echo "Не удалось обновить автоматически — сделайте это в LuCI (Подписки -> Обновить)."
fi

/etc/init.d/homeproxy restart >/dev/null 2>&1
echo "Готово. Откройте LuCI: Службы -> Re:HomeProxy -> Настройки узлов -> Узлы."
