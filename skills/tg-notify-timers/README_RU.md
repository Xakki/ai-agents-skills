# Таймеры `TG_NOTIFY_*`

Эта памятка описывает, когда Telegram-уведомления планируются, когда они
доставляются и как отменяются.

> Все интервалы здесь указаны **в секундах**. Значения по умолчанию — это
> defaults в коде hook-скриптов. Любой code-default может быть переопределён
> одноимённой переменной окружения. Секреты, реальные chat ID и содержимое
> `.env` в этой документации не приводятся.

## Что реально подключено в Hermes

У Hermes есть две разные картины:

1. **Активная Stop-ветка.** Python-плагин регистрирует `pre_llm_call`,
   `post_llm_call`, `on_session_finalize` и `on_session_reset`
   (`/home/xakki/ai-agents-skills/__init__.py:203-206`). В ней:
   `pre_llm_call` запускает `tg-prompt-start.sh`, `post_llm_call` запускает
   `tg-on-stop.sh`, а finalize/reset запускают `tg-cancel-pending.sh`
   (`__init__.py:126-179`). Поэтому в текущем Hermes действительно работает
   lifecycle уведомления «✅ Задача завершена».
2. **Не подключённая notification-ветка.** В том же Python-плагине нет
   регистрации `tg-on-notification.sh` и события `tg-on-notification`.
   Переменные permission/idle ниже документируют логику hook-скрипта и
   совместимость с другими hook-поверхностями, но сами по себе не создают
   permission/idle-события в текущем Hermes. В частности, Hermes не поставляет
   plugin event для permission/idle (`/home/xakki/ai-agents-skills/after-install.md:30-32`).

Файл `hooks/hooks.json` содержит отдельное декларативное подключение
`Notification` (`hooks/hooks.json:19-24`) для совместимого hook-рантайма; это
не означает, что текущая регистрация Python-плагина Hermes вызывает эту ветку.

## Активный lifecycle Stop: «✅ Задача завершена»

```text
UserPromptSubmit / pre_llm_call
        |
        | tg-prompt-start.sh:
        | записать started_at и prompt;
        | удалить старые pending payload;
        | снять маркер .stopped
        v
   Выполняется задача
        |
        | post_llm_call / Stop
        | tg-on-stop.sh вычисляет DUR = now - started_at
        v
   DUR < STOP_THRESHOLD? ---- да ----> skip, ничего не планировать
        |
        нет
        |
   debounce пройден? ------- нет -----> skip, ничего не планировать
        |
        да
        |
   удалить pending permission/idle payload;
   поставить .stopped;
   создать *.stop.payload;
   запустить sleep STOP_DELAY
        |
        +---- новый prompt / cancel hook до истечения delay ---->
        |     payload удалён; после sleep: cancelled; отправки нет
        |
        +---- delay истёк, payload существует ------------------>
              tg-notify.sh отправляет:
              «✅ Задача завершена (DUR)» + тело отчёта
```

`tg-on-stop.sh` всегда завершает hook с кодом 0 и передаёт доставку фоновому
процессу (`/home/xakki/ai-agents-skills/hooks/tg-on-stop.sh:132-154`). Поэтому
`STOP_DELAY` — это окно отмены после **планирования**, а не дополнительный
порог длительности задачи.

## Stop-параметры

| Переменная | Default в коде | Когда используется |
|---|---:|---|
| `TG_NOTIFY_STOP_THRESHOLD` | `1200` | В `tg-on-stop.sh:20-22`; минимальная длительность задачи `DUR`, при которой Stop-уведомление вообще планируется. При `DUR < threshold` — пропуск. Нулевая/неизвестная длительность также пропускается. |
| `TG_NOTIFY_STOP_DELAY` | `1800` | В `tg-on-stop.sh:20`; задержка `sleep` между созданием `.stop.payload` и попыткой доставки. Пока задержка не истекла, payload можно отменить. |
| `TG_NOTIFY_STOP_DEBOUNCE` | `1200` | В `tg-on-stop.sh:21,56-65`; минимальный интервал между планированиями Stop для одной сессии, по файлу `.last_stop`. |

### Пример timeline с `TG_NOTIFY_STOP_DELAY=300`

Предположим, `TG_NOTIFY_STOP_THRESHOLD=1200`, debounce не блокирует событие,
а задача началась в `t=0`:

```text
t=0       записан started_at
t=1200    Stop: DUR=1200, threshold пройден
          создан payload; запущен sleep 300
t=1200..1500  окно отмены: новый prompt/cancel удаляет payload
t=1500    если payload всё ещё существует — попытка отправки
```

То есть `TG_NOTIFY_STOP_DELAY=300` начнёт действовать **после перезапуска
Hermes**: новый процесс должен получить обновлённую переменную окружения.

## Неактивная в текущем Hermes permission/idle-ветка

Логика `hooks/tg-on-notification.sh` классифицирует входящее сообщение как
permission, если оно содержит `permission` или `разрешени`; остальные случаи
считает idle (`tg-on-notification.sh:53-64`). В текущем Python-плагине этот hook
не зарегистрирован, поэтому схема ниже гипотетическая для рантайма, который
действительно посылает Notification event.

| Переменная | Default в коде | Момент использования |
|---|---:|---|
| `TG_NOTIFY_PERM_THRESHOLD` | `1200` | Минимальный возраст сессии для permission-уведомления (`tg-on-notification.sh:19-21,53-69`). |
| `TG_NOTIFY_IDLE_THRESHOLD` | `1200` | Минимальный возраст сессии для idle-уведомления (`tg-on-notification.sh:19-21,59-69`). |
| `TG_NOTIFY_DELAY` | `1800` | Задержка после создания permission/idle payload; это cancel window (`tg-on-notification.sh:22,145-164`). |
| `TG_NOTIFY_DEBOUNCE` | `300` | Минимальный интервал между планированиями permission/idle для сессии, по `.last_scheduled` (`tg-on-notification.sh:23,71-80`). |

Гипотетический lifecycle:

```text
Notification event
        |
        v
DUR >= PERM_THRESHOLD (permission)
или DUR >= IDLE_THRESHOLD (idle)?
        |
       нет ------------------------------> skip
        |
       да
        v
Debounce пройден? ---- нет -------------> skip
        |
       да
        v
Создать *.permission.payload или *.idle.payload
        |
        | sleep TG_NOTIFY_DELAY
        |
        +-- prompt / PreToolUse / Stop / SessionEnd --> payload удалён
        |                                                отправки нет
        |
        +-- payload остался после delay -------------> tg-notify.sh отправляет
```

После Stop permission/idle-планирования также не должны дублировать Stop:
`tg-on-notification.sh` проверяет маркер `$SESSION_ID.stopped` и пропускает
сессию (`tg-on-notification.sh:37-41`).

## Cancellation по pending payload

Pending payload — это обычный файл в каталоге сессии
`$TG_NOTIFY_HOME/pending/<session_id>/`. Файл создаётся до фонового `sleep`.
По окончании задержки отправка выполняется **только если тот же файл всё ещё
существует**; затем он удаляется. Если файла нет, процесс только пишет
`cancelled` в лог (`tg-on-stop.sh:132-151`; аналогично
`tg-on-notification.sh:145-164`).

Удаление выполняют:

- `tg-prompt-start.sh` — при новом пользовательском prompt, то есть когда
  пользователь снова активен (`tg-prompt-start.sh:23-30`);
- `tg-cancel-pending.sh` — на cancel-событиях, включая PreToolUse/SessionEnd в
  совместимом hook-описании (`tg-cancel-pending.sh:1-24`);
- `tg-on-stop.sh` — перед планированием Stop удаляет старые permission/idle
  payload, чтобы финальное сообщение заменило их (`tg-on-stop.sh:67-73`).

Удаление pending-файла не пытается убить уже запущенный `sleep`: фоновый
процесс просыпается, проверяет отсутствие файла и не вызывает отправитель.

## Инфраструктурные переменные

Runtime вычисляет пути в `skills/tg-notify/runtime.sh:4-22`, а отправитель
применяет override в `skills/tg-notify/tg-notify.sh:61-63`.

| Переменная | Default / разрешение | Назначение |
|---|---|---|
| `TG_NOTIFY_HOME` | `$CLAUDE_PLUGIN_DATA`, иначе `${XDG_STATE_HOME:-$HOME/.local/state}/tg-notify` | Корень изменяемого runtime-состояния. Внутри создаются `state/`, `pending/`, `failed/` и лог по умолчанию. |
| `TG_NOTIFY_ENV` | `${XDG_CONFIG_HOME:-$HOME/.config}/tg-notify/.env` | Путь к файлу credentials для `tg-notify.sh`; экспортированные переменные окружения имеют приоритет (`tg-notify.sh:26-28,42-48`). Содержимое файла здесь не приводится. |
| `TG_NOTIFY_LOG` | `$TG_NOTIFY_HOME/tg-notify.log` | Явный путь журнала отправителя. Если не задан, используется вычисленный runtime-лог (`tg-notify.sh:61,162-166`). |
| `TG_NOTIFY_FAILED_DIR` | `$TG_NOTIFY_HOME/failed` | Каталог для payload/chunk, которые не удалось доставить после всех попыток (`tg-notify.sh:62,168-179,226-228`). |
| `TG_NOTIFY_MAX_ATTEMPTS` | `3` | Максимум попыток для каждого chunk; между ошибками используется backoff, после исчерпания payload сохраняется в failed-каталог (`tg-notify.sh:63,210-228`). |

`TG_NOTIFY_HOME` также определяет фактический каталог pending, который hooks
используют через `TG_PENDING_DIR` (`runtime.sh:12-16`).

## Компактная карта «переменная → момент использования»

| Переменная | Момент использования |
|---|---|
| `TG_NOTIFY_STOP_THRESHOLD` | Stop hook вычисляет длительность и решает, планировать ли «✅ Задача завершена». |
| `TG_NOTIFY_STOP_DEBOUNCE` | Stop hook перед созданием нового `.stop.payload`, чтобы не планировать слишком часто. |
| `TG_NOTIFY_STOP_DELAY` | Stop hook после создания `.stop.payload`, как время до попытки доставки. |
| `TG_NOTIFY_PERM_THRESHOLD` | Notification hook (если подключён) проверяет порог permission. |
| `TG_NOTIFY_IDLE_THRESHOLD` | Notification hook (если подключён) проверяет порог idle. |
| `TG_NOTIFY_DEBOUNCE` | Notification hook (если подключён) ограничивает частоту permission/idle-планирований. |
| `TG_NOTIFY_DELAY` | Notification hook (если подключён) задаёт cancel window перед доставкой. |
| `TG_NOTIFY_HOME` | `runtime.sh` строит state/pending/log/failed-пути до работы hooks и sender. |
| `TG_NOTIFY_ENV` | `tg-notify.sh` выбирает файл credentials перед отправкой. |
| `TG_NOTIFY_LOG` | `tg-notify.sh` выбирает файл журнала при попытке, успехе или ошибке отправки. |
| `TG_NOTIFY_FAILED_DIR` | `tg-notify.sh` выбирает каталог для недоставленных payload после retries. |
| `TG_NOTIFY_MAX_ATTEMPTS` | `tg-notify.sh` ограничивает число попыток на каждый chunk. |

### Источники в репозитории

- `/home/xakki/ai-agents-skills/__init__.py`
- `/home/xakki/ai-agents-skills/hooks/tg-prompt-start.sh`
- `/home/xakki/ai-agents-skills/hooks/tg-on-stop.sh`
- `/home/xakki/ai-agents-skills/hooks/tg-on-notification.sh`
- `/home/xakki/ai-agents-skills/hooks/tg-cancel-pending.sh`
- `/home/xakki/ai-agents-skills/skills/tg-notify/runtime.sh`
- `/home/xakki/ai-agents-skills/skills/tg-notify/tg-notify.sh`
- `/home/xakki/ai-agents-skills/hooks/hooks.json`
