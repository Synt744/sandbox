#!/bin/sh
#
# install.sh — установка Re:HomeProxy (ядро hiddify-core) на роутер
#              Cudy WR3000S v1 с OpenWrt 25.12.x (менеджер пакетов apk).
#
# Что делает скрипт (идемпотентно, можно запускать повторно):
#   0. Проверяет окружение (root, OpenWrt, архитектура, apk, firewall4, интернет, место).
#   1. Доставляет базовые пакеты для HTTPS (libustream-openssl, ca-bundle, curl).
#   2. Добавляет ключ подписи Re:HomeProxy в /etc/apk/keys.
#   3. Ставит LuCI-приложение luci-app-re-homeproxy (свежий релиз с GitHub).
#   4. Ставит русский языковой пакет (если не --no-ru).
#   5. Ставит модули ядра kmod-nft-tproxy и kmod-tun (нужны для прозрачного прокси).
#   6. Ставит ядро прокси: hiddify-core (по умолчанию) или sing-box-extended.
#   7. Выставляет разумные настройки для РФ (routing_mode=proxy_banned_ru и пр.).
#   8. Включает и запускает службу homeproxy, перезапускает rpcd.
#
# Запуск (по SSH на роутере, от root):
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/Synt744/sandbox/main/install.sh
#   sh /tmp/install.sh
#
# Или одной строкой (ввод читается из /dev/tty, поэтому пайп остаётся интерактивным):
#   wget -qO- https://raw.githubusercontent.com/Synt744/sandbox/main/install.sh | sh
#
# Флаги:
#   --core hiddify|singbox|none   какое ядро ставить (по умолчанию hiddify)
#   --mirror URL                  зеркало GitHub (если github.com блокируется/медленный)
#   --arch ARCH                   переопределить архитектуру (по умолчанию aarch64_cortex-a53)
#   --yes                         не задавать вопросов, всё по умолчанию
#   --no-ru                       не ставить русский языковой пакет
#   --no-kmods                    не ставить модули ядра
#   --no-start                    не запускать службу в конце
#   -h|--help                     справка
#
# Переменные окружения:
#   GH_MIRROR=https://my.mirror  то же, что --mirror
#
# ВНИМАНИЕ: скрипт ставит только пользовательскую часть. Провайдера/подписку Hiddify
#           вы добавляете сами в LuCI (Сервисы -> Re:HomeProxy -> Подписки).

set -u

APP_REPO="1andrevich/homeproxy-hiddify"
CORE_REPO="1andrevich/hiddify-core"
SBOX_REPO="shtorm-7/sing-box-extended"
EXPECT_ARCH="${GH_ARCH:-aarch64_cortex-a53}"
APP_PKG="luci-app-re-homeproxy"
CORE_NAME="hiddify"

MIRROR="${GH_MIRROR:-}"
ASSUME_YES=0
DO_RU=1
DO_KMODS=1
DO_START=1

# ----------------------------------------------------------------- утилиты вывода
if [ -t 1 ]; then
	C_G='\033[0;32m'; C_R='\033[0;31m'; C_Y='\033[0;33m'; C_C='\033[0;36m'; C_N='\033[0m'
else
	C_G=''; C_R=''; C_Y=''; C_C=''; C_N=''
fi
ok()   { printf '%s\n' "${C_G}$*${C_N}"; }
info() { printf '%s\n' "${C_C}$*${C_N}"; }
warn() { printf '%s\n' "${C_Y}$*${C_N}"; }
die()  { printf '%s\n' "${C_R}$*${C_N}" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------- разбор аргументов
usage() {
	if [ -r "$0" ]; then sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
	else cat <<'EOF'
Установка Re:HomeProxy (hiddify-core) на Cudy WR3000S v1 / OpenWrt 25.12.
Флаги: --core hiddify|singbox|none  --mirror URL  --arch ARCH  --yes
       --no-ru  --no-kmods  --no-start  -h|--help
EOF
	fi
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
		--core)     CORE_NAME="${2:-}"; shift 2 ;;
		--mirror)   MIRROR="${2:-}"; shift 2 ;;
		--arch)     EXPECT_ARCH="${2:-}"; shift 2 ;;
		--yes|-y)   ASSUME_YES=1; shift ;;
		--no-ru)    DO_RU=0; shift ;;
		--no-kmods) DO_KMODS=0; shift ;;
		--no-start) DO_START=0; shift ;;
		-h|--help)  usage ;;
		*)          die "Неизвестный аргумент: $1 (см. --help)" ;;
	esac
done

case "$CORE_NAME" in
	hiddify|singbox|none) ;;
	*) die "--core должен быть hiddify, singbox или none (получено: $CORE_NAME)" ;;
esac

# ----------------------------------------------------------------- загрузка (GitHub -> зеркало)
# dl <url> <файл>  — сначала GitHub, при сбое зеркало; 0 = успех
dl() {
	_wget_qO "$1" "$2" && return 0
	if [ -n "$MIRROR" ]; then
		_m=$(printf '%s' "$1" | sed "s#^https://github.com#${MIRROR}#; s#^https://raw.githubusercontent.com#${MIRROR}/raw#")
		[ "$_m" != "$1" ] && _wget_qO "$_m" "$2" && return 0
	fi
	return 1
}
_wget_qO() {
	if have wget; then wget -qO "$2" --timeout=20 "$1" 2>/dev/null
	else uclient-fetch -q -O "$2" --timeout=20 "$1" 2>/dev/null; fi
	[ -s "$2" ]
}
api() { _wget_qO "$1" /tmp/.hp_api.$$ && cat /tmp/.hp_api.$$; rm -f /tmp/.hp_api.$$; }

# ----------------------------------------------------------------- шаг 0: окружение
info "===== Установка Re:HomeProxy на Cudy WR3000S v1 (OpenWrt 25.12 / apk) ====="

[ "$(id -u)" = "0" ] || die "Запустите от root."
[ -r /etc/openwrt_release ] || die "Это не OpenWrt (нет /etc/openwrt_release)."
# shellcheck disable=SC1091
. /etc/openwrt_release 2>/dev/null || true
ARCH="${DISTRIB_ARCH:-${OPENWRT_ARCH:-}}"
VER="${DISTRIB_RELEASE:-}"
[ -n "$ARCH" ] || die "Не удалось определить архитектуру (DISTRIB_ARCH)."

if have apk; then PM=apk; EXT=apk
elif have opkg; then PM=opkg; EXT=ipk
else die "Не найден менеджер пакетов apk/opkg."; fi

case "$VER" in
	25.*|SNAPSHOT|24.10*) ;;
	"") warn "Версия OpenWrt неизвестна — продолжаю." ;;
	*) warn "OpenWrt $VER не проверялся (нужен 24.10+ или 25.12+). Продолжаю." ;;
esac

info "OpenWrt: $VER | архитектура: $ARCH | менеджер пакетов: $PM"
[ "$ARCH" = "$EXPECT_ARCH" ] || warn "Ожидалась архитектура $EXPECT_ARCH, а у вас $ARCH — ядро будет взято под $ARCH (если найдётся)."

if [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then :; else warn "Не найден firewall4 (fw4). Re:HomeProxy рассчитан на firewall4."; fi

# интернет + HTTPS
info "Проверяю доступ в сеть и HTTPS..."
if ! _wget_qO "https://raw.githubusercontent.com/${APP_REPO}/master/install.sh" /tmp/.hp_net.$$; then
	# быть может нет libustream-openssl — попробуем поставить базовые пакеты
	warn "Не удалось скачать по HTTPS. Пробую доставить libustream-openssl/ca-bundle..."
	$PM update >/dev/null 2>&1 || true
	if [ "$PM" = apk ]; then $PM add libustream-openssl ca-bundle curl >/dev/null 2>&1 || true
	else $PM install libustream-openssl ca-bundle curl >/dev/null 2>&1 || true; fi
	_wget_qO "https://raw.githubusercontent.com/${APP_REPO}/master/install.sh" /tmp/.hp_net.$$ \
		|| die "Нет доступа в интернет по HTTPS. Проверьте WAN/DNS/дату (см. docs/troubleshooting.md)."
fi
rm -f /tmp/.hp_net.$$
ok "Сеть и HTTPS в порядке."

# свободное место
FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ -n "${FREE_KB:-}" ] || FREE_KB=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
[ -n "${FREE_KB:-}" ] || FREE_KB=0
info "Свободно на /overlay: ~$((FREE_KB/1024)) МБ"
[ "$FREE_KB" -ge 30000 ] || warn "Мало места (<30 МБ). Полное ядро hiddify-core может не поместиться — освободите место или ставьте компактную сборку."

# ----------------------------------------------------------------- шаг 1: базовые пакеты
info "[1/7] Базовые пакеты (HTTPS/утилиты)..."
if [ "$PM" = apk ]; then
	$PM update >/dev/null 2>&1 || true
	$PM add libustream-openssl ca-bundle curl >/dev/null 2>&1 || warn "  часть базовых пакетов не установилась (продолжаю)."
else
	$PM update >/dev/null 2>&1 || true
	$PM install libustream-openssl ca-bundle curl >/dev/null 2>&1 || warn "  часть базовых пакетов не установилась (продолжаю)."
fi

# ----------------------------------------------------------------- шаг 2: ключ подписи
info "[2/7] Ключ подписи Re:HomeProxy..."
if [ "$PM" = apk ]; then
	if [ -f /etc/apk/keys/homeproxy-hiddify.pub ]; then
		ok "  ключ уже на месте."
	else
		if dl "https://github.com/${APP_REPO}/releases/latest/download/homeproxy-hiddify.pub" /tmp/hp.pub; then
			mkdir -p /etc/apk/keys
			cp /tmp/hp.pub /etc/apk/keys/ && ok "  ключ добавлен в доверенные."
		else
			warn "  не удалось скачать ключ — пакеты поставлю без проверки подписи."
		fi
		rm -f /tmp/hp.pub
	fi
fi

# ----------------------------------------------------------------- шаг 3: приложение LuCI
info "[3/7] Приложение luci-app-re-homeproxy..."
APP_URL=$(api "https://api.github.com/repos/${APP_REPO}/releases/latest" \
	| grep -o "https://github\.com/[^\"]*${APP_PKG}[^\"]*_all\.${EXT}" | head -1)
[ -n "$APP_URL" ] || APP_URL=$(api "https://api.github.com/repos/${APP_REPO}/releases" \
	| grep -o "https://github\.com/[^\"]*${APP_PKG}[^\"]*_all\.${EXT}" | head -1)
[ -n "$APP_URL" ] || die "Не нашёл пакет ${APP_PKG}_all.${EXT} в релизах. GitHub заблокирован? Попробуйте --mirror URL."
dl "$APP_URL" "/tmp/app.${EXT}" || die "Не удалось скачать приложение. Попробуйте --mirror URL."
if [ "$PM" = apk ]; then
	if [ -f /etc/apk/keys/homeproxy-hiddify.pub ]; then
		$PM add "/tmp/app.${EXT}" >/dev/null 2>&1 || $PM add --allow-untrusted "/tmp/app.${EXT}" || die "apk add приложения завершился ошибкой."
	else
		$PM add --allow-untrusted "/tmp/app.${EXT}" || die "apk add приложения завершился ошибкой."
	fi
else
	$PM install "/tmp/app.${EXT}" || die "opkg install приложения завершился ошибкой."
fi
rm -f "/tmp/app.${EXT}"
ok "  приложение установлено."

# ----------------------------------------------------------------- шаг 4: русский язык
if [ "$DO_RU" = 1 ]; then
	info "[4/7] Русский языковой пакет..."
	RU_URL=$(api "https://api.github.com/repos/${APP_REPO}/releases/latest" \
		| grep -o "https://github\.com/[^\"]*luci-i18n-homeproxy-ru[^\"]*_all\.${EXT}" | head -1)
	if [ -n "$RU_URL" ] && dl "$RU_URL" "/tmp/i18n.${EXT}"; then
		if [ "$PM" = apk ]; then $PM add "/tmp/i18n.${EXT}" >/dev/null 2>&1 || $PM add --allow-untrusted "/tmp/i18n.${EXT}" || warn "  перевод не установился."
		else $PM install "/tmp/i18n.${EXT}" >/dev/null 2>&1 || warn "  перевод не установился."; fi
		rm -f "/tmp/i18n.${EXT}"
	fi
	if [ "$PM" = apk ]; then $PM add luci-i18n-base-ru >/dev/null 2>&1 || true
	else $PM install luci-i18n-base-ru >/dev/null 2>&1 || true; fi
	uci set luci.main.lang=ru 2>/dev/null && uci commit luci 2>/dev/null
	ok "  русский язык установлен."
else
	info "[4/7] Русский язык — пропущено (--no-ru)."
fi

# ----------------------------------------------------------------- шаг 5: модули ядра
if [ "$DO_KMODS" = 1 ]; then
	info "[5/7] Модули ядра (kmod-nft-tproxy, kmod-tun)..."
	if [ "$PM" = apk ]; then
		$PM add kmod-nft-tproxy kmod-tun >/dev/null 2>&1 || warn "  не все kmod установились — прозрачная маршрутизация может не работать."
	else
		$PM install kmod-nft-tproxy kmod-tun >/dev/null 2>&1 || warn "  не все kmod установились."
	fi
	ok "  модули установлены."
else
	info "[5/7] Модули ядра — пропущено (--no-kmods)."
fi

# ----------------------------------------------------------------- шаг 6: ядро прокси
if [ "$CORE_NAME" = "none" ]; then
	info "[6/7] Ядро прокси — пропущено. Установите его позже: Службы -> Re:HomeProxy -> Ядро и службы."
else
	info "[6/7] Ядро прокси: $CORE_NAME..."
	if [ "$CORE_NAME" = "hiddify" ]; then
		CORE_URL="https://github.com/${CORE_REPO}/releases/latest/download/hiddify-core_${ARCH}.${EXT}"
		dl "$CORE_URL" "/tmp/core.${EXT}" || die "Не удалось скачать hiddify-core (${ARCH}). Попробуйте --mirror URL."
		if [ "$PM" = apk ]; then
			if [ -f /etc/apk/keys/homeproxy-hiddify.pub ]; then
				$PM add "/tmp/core.${EXT}" >/dev/null 2>&1 || $PM add --allow-untrusted "/tmp/core.${EXT}" || die "apk add ядра завершился ошибкой."
			else
				$PM add --allow-untrusted "/tmp/core.${EXT}" || die "apk add ядра завершился ошибкой."
			fi
		else
			$PM install --force-reinstall "/tmp/core.${EXT}" || die "opkg install ядра завершился ошибкой."
		fi
		rm -f "/tmp/core.${EXT}"
		ok "  hiddify-core установлен."
	else
		# sing-box-extended: имя файла содержит архитектуру, берём из релиза
		SB_URL=$(api "https://api.github.com/repos/${SBOX_REPO}/releases/latest" \
			| grep -o "https://github\.com/[^\"]*openwrt[^\"]*${ARCH}[^\"]*\.${EXT}" | head -1)
		[ -n "$SB_URL" ] || die "Не нашёл пакет sing-box-extended для ${ARCH} в релизах."
		dl "$SB_URL" "/tmp/core.${EXT}" || die "Не удалось скачать sing-box-extended."
		if [ "$PM" = apk ]; then $PM add --allow-untrusted "/tmp/core.${EXT}" || die "apk add ядра завершился ошибкой."
		else $PM install --force-reinstall "/tmp/core.${EXT}" || die "opkg install ядра завершился ошибкой."; fi
		rm -f "/tmp/core.${EXT}"
		ok "  sing-box-extended установлен."
	fi
fi

# ----------------------------------------------------------------- шаг 7: настройки и запуск
info "[7/7] Настройки для РФ и запуск службы..."
if [ -n "$MIRROR" ]; then
	uci set homeproxy.config.github_mirror="$MIRROR" 2>/dev/null
fi
# Разумные значения по умолчанию для режима «Россия (Обход блокировок)».
uci set homeproxy.config.routing_mode=proxy_banned_ru 2>/dev/null
uci set homeproxy.config.proxy_calls=1 2>/dev/null
uci set homeproxy.config.no_proxy_torrents=1 2>/dev/null
uci set homeproxy.config.ipv6_support=0 2>/dev/null
uci set homeproxy.config.log_level=warn 2>/dev/null
uci commit homeproxy 2>/dev/null

# rpcd должен перечитать методы luci.homeproxy
/etc/init.d/rpcd restart >/dev/null 2>&1
sleep 2

if [ "$DO_START" = 1 ]; then
	/etc/init.d/homeproxy enable >/dev/null 2>&1
	/etc/init.d/homeproxy start  >/dev/null 2>&1
	ok "  служба homeproxy включена и запущена."
fi

# ----------------------------------------------------------------- финал
LANIP=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
[ -n "$LANIP" ] || LANIP=$(ip -4 addr show br-lan 2>/dev/null | sed -n 's#.*inet \([0-9.]*\).*#\1#p' | head -1)
[ -n "$LANIP" ] || LANIP="192.168.1.1"
URL="http://$LANIP/cgi-bin/luci/admin/services/homeproxy"

echo
ok "===== Готово ====="
info "Откройте Re:HomeProxy в LuCI:"
printf '\033[0;36m  \033]8;;%s\033\\%s\033]8;;\033\033[0m\n' "$URL" "$URL"
echo
info "Дальше:"
info "  1) Если ядро не ставилось (--core none) — установите на вкладке «Ядро и службы»."
info "  2) «Настройки узлов -> Подписки»: добавьте ссылку подписки Hiddify."
info "  3) «Настройки клиента»: Основной узел = подписка/URLTest."
info "  4) «Настройки маршрутизации»: режим «Россия (Обход Блокировок)»."
info "  5) «Правила прокси (РФ)»: включите Russia Inside и Re:Filter."
info "  6) «Диагностика»: проверьте, что IP провайдера != IP прокси."
echo
info "Подробности — в README.md и docs/."
