# Cudy WR3000S v1 + OpenWrt 25.12 + Hiddify

Готовый набор скриптов и инструкций, чтобы превратить роутер **Cudy WR3000S v1**
с **OpenWrt 25.12.6** в клиент для вашего **VPS с Hiddify** (обход блокировок),
с управлением из **LuCI**.

Всё делается руками, по шагам. Скрипты — помощники, они не делают ничего «магического»
и запускаются повторно без вреда.

---

## Что здесь

| Файл | Что это |
|------|---------|
| `install.sh` | ставит Re:HomeProxy + ядро hiddify-core + kmod + русский язык, настраивает режим РФ |
| `scripts/preflight.sh` | проверка готовности роутера (ничего не меняет) |
| `scripts/backup-partitions.sh` | бэкап уникальных разделов (Factory, bdinfo) |
| `scripts/add-subscription.sh` | добавить подписку Hiddify из консоли |
| `scripts/diagnose.sh` | быстрая диагностика состояния |
| `scripts/uninstall.sh` | удаление софта |
| `docs/01-firmware.md` | установка OpenWrt 25.12.6 на роутер |
| `docs/02-software-comparison.md` | почему Re:HomeProxy, сравнение вариантов |
| `docs/03-configuration.md` | настройка под сервер Hiddify (LuCI) |
| `docs/04-troubleshooting.md` | типовые проблемы и решения |
| `docs/05-dpi-bypass.md` | ByeDPI/Zapret — обход DPI без VPN |

---

## Коротко: что и почему

- **Роутер:** Cudy WR3000S v1 — MediaTek MT7981 (Filogic 820), 2×Cortex-A53 @1.3 ГГц,
  256 МБ RAM, 128 МБ NAND. Архитектура пакетов `aarch64_cortex-a53`.
- **Прошивка:** OpenWrt 25.12.6, профиль `cudy_wr3000s-v1`. В 25.12 менеджер пакетов —
  **apk** (не opkg).
- **Софт:** **Re:HomeProxy** (<https://github.com/1andrevich/homeproxy-hiddify>) —
  форк ImmortalWrt HomeProxy с ядром **hiddify-core** (тот же движок, что в клиенте
  Hiddify). Управление из LuCI, импорт подписок Hiddify, RU-правила, ByeDPI/Zapret.
- **Почему так:** это единственный расклад, который официально живёт на 25.12/apk,
  понимает подписки Hiddify и влезает в ресурсы этого роутера. Подробнее —
  `docs/02-software-comparison.md`.

---

## Порядок действий

### Шаг 1. OpenWrt на роутере

Если у вас ещё заводская Cudy или другая прошивка — сначала пройдите
**`docs/01-firmware.md`**. Там описан обязательный промежуточный образ Cudy,
особенности новой флеш-памяти и бэкап разделов.

> Если OpenWrt 25.12.x уже стоит — пропускайте этот шаг.

### Шаг 2. Проверка окружения

По SSH на роутере:

```sh
ssh root@192.168.1.1
wget -O /tmp/preflight.sh https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/scripts/preflight.sh
sh /tmp/preflight.sh
```

Скрипт проверит версию, архитектуру, apk, firewall4, интернет по HTTPS, время,
свободное место и ОЗУ. Если есть `[FAIL]` — исправьте до установки.

### Шаг 3. Бэкап разделов (не пропускать!)

```sh
wget -O /tmp/backup.sh https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/scripts/backup-partitions.sh
sh /tmp/backup.sh
```

Скопируйте полученные `Factory.bin` и `bdinfo.bin` к себе на компьютер (`scp -O`).
Это калибровка Wi-Fi и MAC-адреса — уникальны, сбросом не восстанавливаются.

### Шаг 4. Установка

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/install.sh
sh /tmp/install.sh
```

Скрипт поставит:

1. базовые пакеты для HTTPS;
2. ключ подписи Re:HomeProxy;
3. приложение `luci-app-re-homeproxy`;
4. русский язык LuCI;
5. модули ядра `kmod-nft-tproxy`, `kmod-tun`;
6. ядро **hiddify-core** под вашу архитектуру;
7. разумные настройки РФ и запуск службы.

Полезные флаги:

```sh
sh /tmp/install.sh --core singbox      # ядро sing-box-extended (нужно для AmneziaWG/WARP)
sh /tmp/install.sh --mirror https://my.mirror   # если GitHub блокируется
sh /tmp/install.sh --no-ru             # без русского языка
sh /tmp/install.sh --yes               # без вопросов
```

Если GitHub у вас блокируется/тормозит, ставьте зеркало — переменной перед `sh`:

```sh
wget -qO- https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/install.sh | GH_MIRROR=https://my.mirror sh
```

### Шаг 5. Настройка под Hiddify (LuCI)

Откройте **Службы → Re:HomeProxy** и пройдите **`docs/03-configuration.md`**:

1. **Настройки узлов → Подписки** — вставьте ссылку подписки из панели Hiddify,
   включите автообновление.
2. **Настройки клиента** — Основной узел = подписка или URLTest.
3. **Настройки маршрутизации** — режим **Россия (Обход Блокировок)**.
4. **Правила прокси (РФ)** — включите **Russia Inside** и **Re:Filter**.
5. **Диагностика** — убедитесь, что IP провайдера ≠ IP прокси.

Из консоли подписку можно добавить так:

```sh
wget -O /tmp/add-sub.sh https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/scripts/add-subscription.sh
sh /tmp/add-sub.sh "https://ваш-домен/sub/ТОКЕН" --auto --hour 2
```

### Шаг 6. Проверка

```sh
wget -O /tmp/diag.sh https://raw.githubusercontent.com/Synt744/cudy-wr3000s-hiddify/main/scripts/diagnose.sh
sh /tmp/diag.sh
```

Ожидаемо: ядро установлено и запущено, порты 5330–5333 слушаются, «прямой IP» и
«IP через прокси» различаются.

---

## Частые вопросы

**Нужен ли интернет на роутере при установке?** Да — скрипт качает пакеты с GitHub.
Если GitHub блокируется, используйте `--mirror`.

**Что если мало места на флеше?** Полное ядро требует ~40 МБ свободного overlay.
Если места меньше, ставьте ядро через LuCI (**Ядро и службы**) — он подберёт компактную
сборку. Подробности — `docs/02-software-comparison.md`.

**AmneziaWG/WARP?** Нужно ядро **sing-box-extended**: `--core singbox`.

**Можно ли всё сделать без скриптов?** Да, всё описано в `docs/` — скрипты лишь
автоматизируют рутину.

**Как удалить?** `sh scripts/uninstall.sh` (добавьте `--purge`, чтобы снести конфиг).

---

## Благодарности и ссылки

- Re:HomeProxy — <https://github.com/1andrevich/homeproxy-hiddify>
- hiddify-core — <https://github.com/hiddify/hiddify-core>
- Hiddify-Manager — <https://github.com/hiddify/Hiddify-Manager>
- OpenWrt WR3000S v1 — <https://openwrt.org/toh/cudy/wr3000s_v1>
- OpenWrt 25.12.6 downloads — <https://downloads.openwrt.org/releases/25.12.6/targets/mediatek/filogic/>

---

## Лицензия

Скрипты и документация в этом репозитории — под MIT (см. `LICENSE`). Сторонние
пакеты (Re:HomeProxy, hiddify-core, OpenWrt) распространяются под своими лицензиями.
