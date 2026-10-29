# Устранение неполадок

Собрано по вики Re:HomeProxy и типовым проблемам WR3000S v1 / OpenWrt 25.12.

---

## Быстрая диагностика

```sh
sh scripts/diagnose.sh          # общий отчёт
sh scripts/preflight.sh         # проверка окружения
```

---

## «Object not found» / нет опций TProxy-TUN / TypeError в LuCI

**Причина:** rpcd не подхватил модуль `luci.homeproxy` (часто сразу после установки
или обновления).

**Решение:**

```sh
/etc/init.d/rpcd restart
```

Затем **выйдите из LuCI и войдите заново** (старая сессия не видит новые права).
Нужны оба шага.

---

## wget не работает по HTTPS («Operation not permitted»)

**Причина:** встроенный wget (uclient-fetch) без SSL.

**Решение:**

```sh
apk add libustream-openssl ca-bundle curl     # на 25.12
# opkg install libustream-openssl ca-bundle curl   # на 24.10
```

---

## Ядро не устанавливается / «bus error» при запуске

**Причина:** бинарник ядра больше свободного места на `/overlay` — при записи он
обрезается и падает с SIGBUS.

**Решение:** проверьте свободное место (`df -h /overlay`). Если мало — ставьте ядро
через вкладку **Ядро и службы** (она сама выберет компактную сборку), либо освободите
место. Не заливайте полный бинарник на тесный overlay.

---

## Прокси не маршрутизирует трафик

Проверьте по порядку:

1. Установлены ли модули ядра:
   ```sh
   apk add kmod-nft-tproxy kmod-tun
   lsmod | grep -E 'nft_tproxy|tun'
   ```
2. Запущена ли служба: `/etc/init.d/homeproxy status`
3. Слушаются ли порты: `netstat -ltnup | grep -E ':(5330|5331|5332|5333)'`
4. Есть ли выбранный **Основной узел** и включены ли списки в **Правила прокси (РФ)**.
5. Диагностика → Проверка соединения: IP провайдера ≠ IP прокси.

---

## Нет интернета при включённом прокси (конфликт с mwan3)

**Причина:** mwan3 и прокси-ядро используют fwmark и policy routing, и mwan3 может
перехватывать исходящие соединения ядра.

**Решение:** добавить постоянное правило файрвола, чтобы mwan3 пропускал
трафик, уже помеченный Re:HomeProxy (mark `0x64`). Через UCI:

```sh
uci add firewall include
uci set firewall.@include[-1].path='/etc/firewall.d/homeproxy-mwan3'
uci set firewall.@include[-1].type='script'
uci commit firewall
```

и создать `/etc/firewall.d/homeproxy-mwan3` со скриптом обхода mwan3 для метки
`0x64` (см. вики Re:HomeProxy → Troubleshooting). Если mwan3 вам не нужен —
проще удалить его: `apk del mwan3`.

---

## Утечка IPv6

В режиме России IPv6 намеренно **выключен**: RU-списки не содержат IPv6-подсетей,
поэтому IPv6-трафик обошёл бы и прокси, и правила. Оставьте `ipv6_support=0`,
если не уверены. Проверить: `uci get homeproxy.config.ipv6_support`.

---

## Медленно / тормозит YouTube и Discord

Если сайт **заблокирован** — он должен идти через VPN-узел (список Re:Filter).
Если **замедляется** — направьте его через **ByeDPI** или **Zapret** вместо VPN
(см. `05-dpi-bypass.md`): это дешевле по трафику и часто быстрее.

Также проверьте **Основной узел**: с URLTest роутер сам выберет быстрейший узел.

---

## Обновился, но интерфейс/методы устарели

После обновления пакета всегда:

```sh
/etc/init.d/rpcd restart
```

и повторный вход в LuCI. Это лечит «DNS not ready», «Method not found», «?» в
управлении ядром.

---

## Полный сброс прокси, не трогая прошивку

```sh
/etc/init.d/homeproxy stop
rm -f /etc/config/homeproxy
sh scripts/uninstall.sh          # при необходимости
# затем заново: sh install.sh
```

---

## Роутер вообще не грузится (после прошивки)

См. `01-firmware.md`, раздел «Если что-то пошло не так»: сброс кнопкой, failsafe,
восстановление заводской Cudy по TFTP, затем повтор шагов.
