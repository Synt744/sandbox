#!/bin/sh
#
# preflight.sh — проверка готовности роутера к установке Re:HomeProxy.
# Ничего не меняет, только читает и печатает отчёт.
#
# Запуск: sh scripts/preflight.sh

set -u

PASS=0; FAIL=0; WARN=0
ok()   { printf '  [OK]   %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN] %s\n' "$*"; WARN=$((WARN+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== Preflight: Cudy WR3000S v1 / Re:HomeProxy =="

# --- OpenWrt и архитектура
if [ -r /etc/openwrt_release ]; then
	# shellcheck disable=SC1091
	. /etc/openwrt_release
	ok "OpenWrt ${DISTRIB_RELEASE:-?} (${DISTRIB_DESCRIPTION:-?})"
else
	bad "Нет /etc/openwrt_release — это не OpenWrt."
fi

ARCH="${DISTRIB_ARCH:-${OPENWRT_ARCH:-}}"
case "$ARCH" in
	aarch64_cortex-a53) ok "Архитектура $ARCH (как у WR3000S v1)." ;;
	"") bad "Не удалось определить архитектуру." ;;
	*) warn "Архитектура $ARCH отличается от ожидаемой aarch64_cortex-a53 (не тот роутер?)." ;;
esac

# --- версия
case "${DISTRIB_RELEASE:-}" in
	25.*) ok "Версия 25.x — менеджер пакетов apk, поддерживается." ;;
	24.10*) ok "Версия 24.10 — менеджер пакетов opkg, поддерживается." ;;
	SNAPSHOT) warn "SNAPSHOT — поддержка есть, но фиды могут отставать." ;;
	*) warn "Версия ${DISTRIB_RELEASE:-неизвестна} — нужна 24.10+ или 25.12+." ;;
esac

# --- менеджер пакетов
if have apk;  then ok "Менеджер пакетов: apk (OpenWrt 25.12+)."
elif have opkg; then ok "Менеджер пакетов: opkg (OpenWrt 24.10)."
else bad "Нет ни apk, ни opkg."; fi

# --- firewall4
if [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then ok "firewall4 присутствует."
else bad "Нет firewall4 (fw4) — Re:HomeProxy требует firewall4."; fi

# --- модель устройства
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null)
if [ -n "$MODEL" ]; then
	case "$MODEL" in
		*WR3000S*) ok "Модель: $MODEL" ;;
		*) warn "Модель: $MODEL (ожидалась Cudy WR3000S v1)." ;;
	esac
fi

# --- интернет и HTTPS
if have wget; then W=wget; else W=uclient-fetch; fi
if $W -q -O /tmp/.pf.$$ --timeout=15 https://raw.githubusercontent.com/1andrevich/homeproxy-hiddify/master/install.sh 2>/dev/null && [ -s /tmp/.pf.$$ ]; then
	ok "Интернет по HTTPS работает."
else
	bad "Нет HTTPS. Поставьте libustream-openssl и ca-bundle, проверьте WAN/DNS/дату."
fi
rm -f /tmp/.pf.$$

# --- системное время (важно для TLS и подписей)
YEAR=$(date +%Y)
if [ "$YEAR" -ge 2025 ] 2>/dev/null; then ok "Системное время: $(date -u '+%Y-%m-%d %H:%M UTC')."
else warn "Системное время похоже на неверное ($(date -u '+%Y-%m-%d')). Включите NTP."; fi

# --- свободное место
FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ -n "${FREE_KB:-}" ] || FREE_KB=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
FREE_MB=$(( ${FREE_KB:-0} / 1024 ))
if [ "$FREE_MB" -ge 80 ]; then ok "Свободно ~${FREE_MB} МБ — хватит на полное ядро + приложение."
elif [ "$FREE_MB" -ge 40 ]; then ok "Свободно ~${FREE_MB} МБ — хватит на полное ядро."
elif [ "$FREE_MB" -ge 25 ]; then warn "Свободно ~${FREE_MB} МБ — хватит только на компактную сборку ядра."
else bad "Свободно ~${FREE_MB} МБ — мало, нужно минимум ~25 МБ."; fi

# --- ОЗУ
RAM_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
if [ -n "${RAM_KB:-}" ]; then
	RAM_MB=$((RAM_KB/1024))
	if [ "$RAM_MB" -ge 96 ]; then ok "Свободно ОЗУ ~${RAM_MB} МБ."
	else warn "Свободно ОЗУ ~${RAM_MB} МБ (компактной сборке нужно ~96 МБ)."; fi
fi

# --- уже установлено?
[ -f /usr/bin/hiddify-core ] && ok "hiddify-core уже установлен: $(/usr/bin/hiddify-core version 2>/dev/null | head -1)."
[ -f /usr/bin/sing-box ] && ok "sing-box уже установлен: $(/usr/bin/sing-box version 2>/dev/null | head -1)."
if [ -f /etc/config/homeproxy ]; then ok "Приложение homeproxy уже установлено."
else warn "Приложение homeproxy ещё не установлено (ожидаемо до install.sh)."; fi

echo
echo "Итог: OK=$PASS, WARN=$WARN, FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
