---
name: tg-notify-timers
description: View or change the timers/thresholds that control the tg-notify hooks (Stop + Notification) — idle/permission/stop thresholds, delivery delays, debounce. They are environment variables that override the hooks' built-in defaults; this skill sets them in settings.json. Use when the user asks to tune Telegram notification delays, debounce, idle/permission/stop thresholds, or to silence/sensitize TG notifications. Triggers (RU/EN) — «таймеры тг», «пороги тг», «debounce TG», «idle threshold», «когда писать в телеграм», «увеличить/уменьшить пороги уведомлений», «tune tg notify», «adjust telegram thresholds».
---

# tg-notify-timers — конфиг таймеров TG-хуков

Управляет 7 переменными, которыми хуки плагина `tg-on-notification.sh` и `tg-on-stop.sh`
решают, когда и через какую задержку слать сообщение в Telegram.

## Как это работает (важно)

Хуки читают каждое значение как `${TG_NOTIFY_*:-<default>}` — то есть **берут число
из окружения, а если переменной нет — встроенный дефолт**. Скрипты хуков лежат в
read-only кэше плагина (`~/.claude/plugins/cache/...`), редактировать их **нельзя** —
перезапишутся при обновлении. Поэтому единственный способ изменить таймер —
**задать env-переменную**, которая перебьёт дефолт.

Канонически — в `env` файла `~/.claude/settings.json` (его окружение наследуют хуки).
**Профиль «default» = ни одной из 7 переменных не задано** → работают встроенные
дефолты. Изменения подхватываются **после перезапуска** Claude Code (env читается на старте).

## Параметры

| Переменная | Хук | Семантика | Default |
|---|---|---|---|
| `TG_NOTIFY_PERM_THRESHOLD` | notification | мин. длительность (сек) для «🔐 Требуется разрешение» | 1200 (20м) |
| `TG_NOTIFY_IDLE_THRESHOLD` | notification | мин. длительность (сек) для «⏰ Ожидает ввода» | 600 (10м) |
| `TG_NOTIFY_DELAY` | notification | задержка доставки (окно отмены, сек) | 300 (5м) |
| `TG_NOTIFY_DEBOUNCE` | notification | мин. интервал между schedule на сессии | 300 (5м) |
| `TG_NOTIFY_STOP_THRESHOLD` | stop | мин. длительность задачи для Stop-уведомления | 1200 (20м) |
| `TG_NOTIFY_STOP_DELAY` | stop | задержка доставки Stop (окно отмены) | 600 (10м) |
| `TG_NOTIFY_STOP_DEBOUNCE` | stop | мин. интервал между Stop-schedule на сессии | 300 (5м) |

Все значения — секунды, в JSON хранятся строками (`"1800"`).

## Посмотреть текущие

```bash
jq '.env | with_entries(select(.key | startswith("TG_NOTIFY_")))' ~/.claude/settings.json
```
Пусто → действуют дефолты из таблицы.

## Поменять

Правится `env` в `~/.claude/settings.json` (напрямую через Edit / skill `update-config`,
либо jq ниже). Один таймер:

```bash
jq '.env.TG_NOTIFY_STOP_THRESHOLD = "1800"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

Сбросить в default (убрать все 7 → встроенные дефолты):

```bash
jq 'del(.env.TG_NOTIFY_PERM_THRESHOLD, .env.TG_NOTIFY_IDLE_THRESHOLD, .env.TG_NOTIFY_DELAY, .env.TG_NOTIFY_DEBOUNCE, .env.TG_NOTIFY_STOP_THRESHOLD, .env.TG_NOTIFY_STOP_DELAY, .env.TG_NOTIFY_STOP_DEBOUNCE)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

После любой правки — перезапустить Claude Code, чтобы хуки увидели новый env.

## Профили

Применять одним jq-мёрджем в `.env`.

### тише
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"1800",TG_NOTIFY_IDLE_THRESHOLD:"1200",TG_NOTIFY_DELAY:"600",TG_NOTIFY_DEBOUNCE:"600",TG_NOTIFY_STOP_THRESHOLD:"1800",TG_NOTIFY_STOP_DELAY:"900",TG_NOTIFY_STOP_DEBOUNCE:"600"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### чувствительнее
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"600",TG_NOTIFY_IDLE_THRESHOLD:"300",TG_NOTIFY_DELAY:"180",TG_NOTIFY_DEBOUNCE:"180",TG_NOTIFY_STOP_THRESHOLD:"600",TG_NOTIFY_STOP_DELAY:"300",TG_NOTIFY_STOP_DEBOUNCE:"180"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### отключить (пороги в недостижимое)
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"99999999",TG_NOTIFY_IDLE_THRESHOLD:"99999999",TG_NOTIFY_STOP_THRESHOLD:"99999999"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

## Проверка

```bash
# что задано в окружении
jq '.env | with_entries(select(.key | startswith("TG_NOTIFY_")))' ~/.claude/settings.json
# JSON валиден?
jq empty ~/.claude/settings.json && echo "settings.json OK"
# лог: что хук планирует/шлёт (runtime home: $TG_NOTIFY_HOME, по умолчанию ~/.local/state/tg-notify)
tail -50 "${TG_NOTIFY_HOME:-$HOME/.local/state/tg-notify}/tg-notify.log" 2>/dev/null
# активные pending payload-файлы
ls -la "${TG_NOTIFY_HOME:-$HOME/.local/state/tg-notify}/pending/"*/ 2>/dev/null
```

## Связанные

- Хуки плагина (read-only, **не редактировать**): `hooks/tg-on-notification.sh`, `hooks/tg-on-stop.sh`,
  `hooks/tg-prompt-start.sh`, `hooks/tg-cancel-pending.sh`.
- Отправка и креды/назначение — скилл `tg-notify` (`skills/tg-notify/`).
