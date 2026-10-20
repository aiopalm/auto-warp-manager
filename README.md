# WARP AutoCheck (luci-app-warp-manager)

Автопроверка и автозамена WARP-конфига для OpenWrt. Дополнение к
[Zapret Manager](https://github.com/StressOzz/Zapret-Manager): периодически
проверяет, жив ли ваш WARP-туннель (интерфейс AmneziaWG из `/root/WARP.conf`), и
если он перестал работать — сам получает новые ключи WARP, подбирает рабочую
точку входа и маску (та же логика, что кнопка «Сгенерировать с проверкой»),
заменяет конфиг и переподнимает интерфейс.

Репозиторий: <https://github.com/aiopalm/auto-warp-manager>

## Требования

- OpenWrt 24.10+ (opkg) или 25.12+ (apk)
- AmneziaWG (`amneziawg-tools`) — обязателен
- `curl`
- WARP-конфиг, сгенерированный в Zapret Manager (раздел AmneziaWG) и
  импортированный как amneziawg-интерфейс

## Установка

### Быстро с гита (на роутере, под root)

Если на роутере есть curl (с Zapret Manager он ставится всегда):

```
curl -fsSL https://raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh | sh
```

Если curl нет — вариант с wget (на некоторых прошивках busybox-wget не умеет
HTTPS и молча ничего не ставит; если команда «молча» ничего не сделала — это
оно):

```
wget -qO - https://raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh | sh
```

### Через ipk

```
scp dist/luci-app-warp-autocheck_0.1.0-1_all.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "opkg install /tmp/luci-app-warp-autocheck_0.1.0-1_all.ipk"
```

### Из клона репозитория

```
git clone https://github.com/aiopalm/auto-warp-manager.git
cd auto-warp-manager
./install.sh root@192.168.1.1   # или ./install.sh --local на самом роутере
```

## Обновление

Та же одна строка, что и при установке (curl-вариант) — файлы пакета
перезапишутся свежими из репозитория, ваши настройки
(`/etc/config/warp-autocheck`) сохранятся:

```
curl -fsSL https://raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh | sh
```

После обновления обнови вкладку браузера с сбросом кэша: Ctrl+Shift+R
(Cmd+Shift+R на Маке) — LuCI агрессивно кэширует JS страницы.

Если ставили через ipk — скачайте/пересоберите свежий ipk и поставьте
поверх: `opkg install --force-reinstall /tmp/luci-app-warp-autocheck_*.ipk`.

## Удаление

Удаляет **только этот пакет** (страницу LuCI, бэкенд, cron-строку, настройки).
Интерфейсы AmneziaWG, `/root/WARP.conf`, сам AmneziaWG и Zapret Manager
остаются как были:

```
curl -fsSL https://raw.githubusercontent.com/aiopalm/auto-warp-manager/main/install.sh | sh -s --uninstall
```

## Как работает

- Проверка — раз в N часов (по умолчанию 6): рукопожатие интерфейса, trace-запрос
  через туннель, пинг-зонд. Конфиг считается мёртвым, если трафик не идёт,
  обрывается (DPI) или идёт через российский узел — при условии, что проблема
  подтвердилась несколько проверок подряд.
- Замена: новые ключи (Cloudflare API → внешний генератор → через живые туннели),
  перебор точек входа/портов/масок, атомарная запись `/root/WARP.conf` (со
  старым бэкапом), обновление ключей интерфейса, `ifup`, пост-проверка с
  автооткатом на бэкап.
- Если конфига нет — страница LuCI подскажет сгенерировать его в Zapret Manager.
  Пакет сам интерфейсы не создаёт и конфиг Mixomo/Steer не обслуживает.

## Настройки (LuCI → Службы → WARP AutoCheck)

- вкл/выкл автопроверки;
- интервал в часах (1–168, по умолчанию 6);
- имя интерфейса AmneziaWG (по умолчанию `warp`);
- число повторных проверок перед заменой (0–3, по умолчанию 2);
- ручные «Проверить сейчас» и «Заменить сейчас», лог.

UCI: `/etc/config/warp-autocheck`. Лог: `/tmp/warp-autocheck.log` и logread
(`-t warp-autocheck`).

## Сборка ipk

```
./build-ipk.sh   # → dist/luci-app-warp-autocheck_0.1.0-1_all.ipk
sh tests/run_tests.sh && python3 tests/case_07_view.py
```
