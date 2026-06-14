# Python — структурный JSON в stdout

Цель: контейнер пишет **одну JSON-строку на запись в stdout/stderr**. Глобальный
парсер `json_default` fluent-bit развернёт JSON автоматически (на всех `gl.*`),
`log_format` можно не задавать → `gl.auto`. Поля — по контракту из [rules.md](rules.md).
Рабочий референс: `<project>/app/logging_setup.py`.

## Минимальные требования
1. **Единая настройка во ВСЕХ точках входа** (web/worker/cron/скрипты) — один
   `configure_logging()`-модуль, не копипастить `basicConfig` по файлам.
2. **JSON-форматтер** на root-хендлере. Либо `python-json-logger`, либо свой
   `logging.Formatter`, сериализующий `{datetime, level, level_name, message,
   context:{...}}`. JSON сам экранирует control-chars (защита от log injection).
3. **Фильтр-маскировка секретов** на root-ХЕНДЛЕРЕ (не на логгере — иначе не ловит
   propagated-записи дочерних логгеров типа httpx/telethon/sqlalchemy).
4. **Уровни** по дереву решений ([rules.md](rules.md)); дефолт прода `info`.
5. **Бизнес-значения** — в `extra`/context, не в f-string: `log.info("order paid",
   extra={"context": {"order_id": oid, "amount_cents": 4999, "tag": "billing"}})`.

## Маскировка секретов (паттерн)
Частая утечка: httpx/SDK логируют URL с токеном в пути (Telegram
`api.telegram.org/bot<id>:<secret>/method`). Фильтр режет секрет ДО эмита:

```python
import logging, re
_TG_TOKEN = re.compile(r"(\d{6,}):[A-Za-z0-9_-]{35,}")   # bot_id публичен, секрет — нет

class RedactSecrets(logging.Filter):
    def filter(self, record):
        try: msg = record.getMessage()
        except Exception: return True
        if ":" in msg and _TG_TOKEN.search(msg):
            record.msg = _TG_TOKEN.sub(r"\1:<REDACTED>", msg); record.args = ()
        return True

def configure_logging(level=logging.INFO):
    logging.basicConfig(level=level, format="%(asctime)s %(name)s %(levelname)s: %(message)s")
    for h in logging.getLogger().handlers:
        if not any(isinstance(f, RedactSecrets) for f in h.filters):
            h.addFilter(RedactSecrets())
```
Расширяй ban-list под проект (Authorization-заголовки, API-ключи, пароли, PHPSESSID…).
**PII-regression тест обязателен:** известный (фейковый) секрет НЕ должен попасть в вывод.

## Шумные библиотеки
- `httpx`/`uvicorn`/`telethon`/`sqlalchemy` пишут в свои логгеры → propagate в root →
  маскировка применяется (фильтр на root-хендлере). Уровень шумных — поднять до WARNING,
  если INFO не нужен.
- **arq** (воркер): CLI вешает свой хендлер на логгер `arq` → вместе с root двойной
  вывод. Гасить **на уровне модуля** (до старта воркера): `logging.getLogger("arq").
  propagate = False` (баннер «Starting worker» логируется до on_startup — в on_startup поздно).

## Best-effort и пул БД
- `fluentd-async: true` → сокет недоступен не роняет приложение (см. integration.md).
- **Перевод БД на fluentd = рекреация postgres = бонс** → пул SQLAlchemy получает
  мёртвые коннекты. Обязательно `create_async_engine(..., pool_pre_ping=True,
  pool_recycle=1800)` — иначе каскад «Can't reconnect until invalid transaction is
  rolled back». Это применимо к ЛЮБОМУ рестарту БД (деплой), не только к включению логов.

## NDJSON-файл (альтернатива stdout)
Если логи в файл, а не stdout: писать `<JSON_LOG_PATH>/<service>.ndjson`, один JSON на
строку; fluent-bit тейлит `/var/log/json/*.ndjson`, имя файла = `docker_service`.
Применять когда stdout занят (легаси) — по умолчанию предпочтительнее stdout (12-factor).
