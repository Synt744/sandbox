# AGENTS.md

Контекст репозитория для будущих сессий (и людей, и агентов).

## Что это

Набор скриптов и инструкций: превратить роутер **Cudy WR3000S v1** с **OpenWrt 25.12.x**
в клиент к VPS с **Hiddify** (обход блокировок), с управлением из LuCI.

## Ключевые факты (проверены)

- **Устройство:** Cudy WR3000S v1 = MediaTek MT7981BA (Filogic 820), 2×Cortex-A53 @1.3 ГГц,
  **256 МБ RAM**, **128 МБ NAND** (overlay ~48 МБ). Архитектура пакетов `aarch64_cortex-a53`.
- **Профиль OpenWrt:** `cudy_wr3000s-v1`, цель `mediatek/filogic`. Есть и `...-ubootmod`
  (не используем по умолчанию). Поддержка с 24.10; ubootmod — с 25.12.4.
- **OpenWrt 25.12 использует `apk`** (не `opkg`). Пакеты — `.apk`. Это ломает старые фиды.
- **Установка на WR3000S требует промежуточного образа, подписанного Cudy** (сначала
  заводской Cudy → Cudy-подписанный OpenWrt → официальный sysupgrade). См. `docs/01-firmware.md`.
- **Новая флеш-память:** экземпляры с кодом партии 2543+ (ESMT F50L1G41LC) требуют
  OpenWrt 24.10.5+ и промежуточный образ Cudy 20251119+.
- **Разделы Factory (mtd2) и bdinfo (mtd3)** уникальны, сбросом не восстанавливаются — бэкапить.

## Выбранный софт

- **Re:HomeProxy** — <https://github.com/1andrevich/homeproxy-hiddify>
  (форк ImmortalWrt HomeProxy). Ядро на выбор: **hiddify-core** (по умолчанию) или
  **sing-box-extended** (для AmneziaWG/WARP). Поддерживает 25.12/apk, подписки Hiddify
  (sing-box JSON, base64, share-ссылки), RU-правила (Russia Inside, Re:Filter), ByeDPI, Zapret2.
- Релизы: `luci-app-re-homeproxy_*_all.apk`, ключ `homeproxy-hiddify.pub`,
  перевод `luci-i18n-homeproxy-ru_*_all.apk`.
- Ядро hiddify-core: <https://github.com/1andrevich/hiddify-core>, ассеты
  `hiddify-core_${ARCH}.apk` (полная сборка) и ветка `upx` (компактная).
- sing-box-extended: <https://github.com/shtorm-7/sing-box-extended>, ассеты
  `sing-box-extended_*_openwrt_${ARCH}.apk`.
- Пороги места (из `core_mgmt.uc`): полное ядро ~80 МБ на несжимающем overlay
  (~32 МБ на jffs2/ubifs), компактная ~25 МБ + ~96 МБ RAM.
- UCI-схема: подписки — `list subscription_url` в секции `homeproxy.subscription`;
  режим РФ — `homeproxy.config.routing_mode=proxy_banned_ru`.
- **У тебя (Synt744) уже есть форк:** `Synt744/homeproxy-hiddify` (форк `1andrevich/homeproxy-hiddify`).

## Структура репо

- `install.sh` — основной установщик (идемпотентный).
- `scripts/` — preflight, backup-partitions, add-subscription, diagnose, uninstall.
- `docs/` — 01 firmware, 02 сравнение, 03 настройка, 04 траблшутинг, 05 DPI-обход.

## Где лежит репо

Опубликовано в **`Synt744/sandbox`**, ветка `main`
(<https://github.com/Synt744/sandbox>). Ссылки в README/install.sh указывают сюда.

> Токен окружения — GitHub App installation token: он **не может создавать репозитории
> и форки** («Resource not accessible by integration»), но имеет push в 8 существующих
> репозиториев Synt744. Поэтому отдельный репозиторий под проект создать не удалось —
> контент залит в `sandbox`. Если появится доступ к созданию репо, стоит перенести в
> `Synt744/cudy-wr3000s-hiddify` и обновить ссылки (sed по `Synt744/sandbox`).

## Конвенции

- Все скрипты — POSIX `sh` (busybox ash на OpenWrt), без bash-измов.
- Проверка синтаксиса: `sh -n install.sh scripts/*.sh`.
- Тексты для пользователя — на русском.
- Никаких секретов/токенов в репо.

## Проверка изменений

```sh
sh -n install.sh scripts/*.sh
```
