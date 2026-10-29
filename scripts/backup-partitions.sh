#!/bin/sh
#
# backup-partitions.sh — резервное копирование уникальных разделов Cudy WR3000S v1.
#
# ЗАЧЕМ: разделы Factory (калибровка Wi-Fi) и bdinfo (MAC-адреса) уникальны для
# каждого экземпляра и НЕ восстанавливаются сбросом. Потеря = мёртвый Wi-Fi/сеть.
# Делайте этот бэкап ДО любых манипуляций с прошивкой/загрузчиком.
#
# Запуск (на роутере, от root):
#   sh scripts/backup-partitions.sh              # только Factory + bdinfo
#   sh scripts/backup-partitions.sh --full       # + BL2, u-boot-env, FIP (перед ubootmod)
#
# Что получится: файлы в /tmp/backup-<дата>/ и их sha256.
# ОБЯЗАТЕЛЬНО скопируйте их на компьютер (scp) — в /tmp они живут до перезагрузки.

set -u

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

[ "$(id -u)" = "0" ] || { echo "Запустите от root." >&2; exit 1; }

DIR="/tmp/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"

for p in /dev/mtd2 /dev/mtd3; do [ -e "$p" ] || { echo "Нет $p — не тот роутер?" >&2; exit 1; }; done

dump() {
	# dump <mtd> <имя>
	dev="$1"; name="$2"
	if [ -e "$dev" ]; then
		echo "  читаю $dev -> $name"
		cat "$dev" > "$DIR/$name" 2>/dev/null || { echo "    ошибка чтения $dev" >&2; return 1; }
		[ -s "$DIR/$name" ] || { echo "    файл пустой: $name" >&2; return 1; }
	fi
}

echo "== Бэкап разделов Cudy WR3000S v1 =="
echo "Каталог: $DIR"
echo

# --- обязательные
dump /dev/mtd2 Factory.bin || echo "  ВНИМАНИЕ: не удалось сохранить Factory.bin" >&2
dump /dev/mtd3 bdinfo.bin  || echo "  ВНИМАНИЕ: не удалось сохранить bdinfo.bin" >&2

# --- для перехода на ubootmod
if [ "$FULL" = 1 ]; then
	echo "  (--full: добавляю BL2/u-boot-env/FIP)"
	dump /dev/mtd0 BL2.bin
	dump /dev/mtd1 u-boot-env.bin
	dump /dev/mtd4 FIP.bin
fi

echo
echo "== Проверка целостности (sha256) =="
( cd "$DIR" && sha256sum ./*.bin 2>/dev/null )

echo
echo "== Готово =="
echo "Скопируйте файлы на компьютер (не оставляйте только на роутере!):"
echo "  # на вашем компьютере:"
echo "  scp -O root@192.168.1.1:$DIR/*.bin ./"
echo
echo "Проверка на компьютере:"
echo "  sha256sum ./*.bin   # хэши должны совпасть с выведенными выше"
echo
echo "Храните Factory.bin и bdinfo.bin в надёжном месте — они нужны для восстановления"
echo "Wi-Fi и MAC-адресов после ошибок прошивки."
