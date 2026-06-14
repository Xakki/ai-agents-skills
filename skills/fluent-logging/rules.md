# Правила логов (конспект LaraLog `docs/LoggingRules.ru.md`)

Принципы языко-независимы (PHP/Python/Node). Источник:
<https://raw.githubusercontent.com/Xakki/LaraLog/refs/heads/main/docs/LoggingRules.ru.md>

## Базовые принципы
1. **Лог — это API.** Сломать имя поля = сломать REST. Имена стабильны.
2. **Структура важнее прозы.** Запись — JSON со стабильными именами; `message` для
   глаз, поиск — по `context`/`extra`.
3. **Логируем один раз, на границе.** Не catch-log-rethrow на каждом уровне.
4. **Логирование не роняет запрос.** Best-effort; приёмник недоступен → запрос ОК.
5. **Cardinality:** меняющееся per-request — в ПОЛЯ, не в индексные лейблы.

## Что НЕ логировать (нарушение = security-инцидент)
Пароли/хеши/reset-токены; API-ключи, bearer/refresh; сессионные ID (`PHPSESSID`,
`Cookie: session=`); полные платёжные (PAN/CVV); гос-ID (СНИЛС/ИНН/паспорт/SSN),
медданные; полный PII скопом; сырые body эндпоинтов с этим. **Редактировать на
границе процесса**, плейсхолдеры `***`/`[redacted]`/`sha256:<8 симв>`. Осторожно с
дампами HTTP, трейсами с аргументами, ORM-биндингами, message исключений с user input.

## Уровни — дерево решений
- Сервис не обслуживает запросы → **emergency**
- Данные повреждены/потеряны → **critical** (немедленный алерт)
- Операция упала, восстановления нет, ушло пользователю → **error** (алерт от 1%)
- Сбой поглощён, но надо что-то сделать → **warning** (от 5%)
- Странное/подозрительное/автокорректировалось → **notice** (от 10%)
- Нормальное бизнес-событие → **info**
- Полезно только при воспроизведении бага → **debug** (в проде выключен)

Правила: **WARN без конкретного действия → NOTICE** (тест: «что должен сделать
разработчик?»; «иногда бывает» → notice, иначе warning-fatigue). **WARN** = система
поглотила сбой (fallback/кеш, запрос пользователя успешен); **ERROR** = сбой ушёл
наружу (retry исчерпаны, 5xx). Промежуточные retry → warning, финальное → error.
Числовые severity: debug 100, info 200, notice 250, warning 300, error 400,
critical 500, alert 550, emergency 600. Дефолт прода — `info`; debug включается
локально/per-instance/под инцидент, НИКОГДА глобально.

## Форма записи
**Top-level (контракт):** `datetime` (RFC3339), `level` (int), `level_name`
(lowercase), `channel`, `message` (короткое предложение, без интерполяции),
`context` (per-event), `extra` (стабильно за процесс).
- **extra:** `app_name`, `app_env`, `app_ver`, `tier`, `release_tag`, load_avg…
- **context:** `log_type`, `request_id` (UUID, переносится через очереди/исходящие),
  `trace_id`/`span_id`, `user_id`, `file`/`line`, `exception` (FQN), `tag`, бизнес-ID.
- **log_type:** `logger` (явный вызов), `trigger` (рантайм/deprecation), `exception`
  (uncaught/залогированное), `fatal` (shutdown/OOM/timeout). Алерт на `exception,fatal`.
- **Бизнес-ID в `context`, не в `message`.** Дисциплина типов: `*_id/*_count` → int;
  `is_*/has_*` → bool; деньги → int в минорных единицах (`amount_cents`), не float;
  длительности → int мс. Имена — `snake_case`, префиксы `app_*`/`http_*`/`db_*`/`queue_*`.
- **Лимиты:** `message` ~3 KB; вся строка <16 KB; трейс 5/10/20 кадров (Warn/Error/Crit);
  аргументы в трейсе 128 chars; обрезка маркером `…`.

## Корреляция
3 ID: `trace_id` (вся транзакция, OTel), `span_id` (единица работы), `request_id`
(один HTTP-запрос, `X-Request-ID`). Инжектить в scope один раз на entrypoint (MDC),
руками не таскать. Каждый entrypoint — пара `entry`/`exit` (`duration_ms`, `success`,
`status_code`). Исходящий HTTP пробрасывает `X-Request-ID`/`traceparent`; queue job
сериализует ID в payload.

## Особые сценарии
- **Исключения:** логировать один раз сверху с бизнес-контекстом. Поля: `exception`
  (FQN, не message), `exception_code`, `file:line`, `trace`, цепочка `prev`. Message
  исключения — под подозрением (PII/log-injection): хранить FQN+code, message только
  не в prod или санитайзенный.
- **Внешние вызовы:** на каждый — `info` без payload, поля `target` (имя, не URL),
  `method`, `path`, `response_code`, `latency_ms`, `attempt`. Прогрессия по сбоям:
  1-й (retry стартует) → notice; retry → warning; max_attempts → error.
- **Slow SQL:** канал `tag:sql`, поля `db_query` (обрезан), `db_table`, `db_time_ms`;
  НИКОГДА сырые bindings в проде. N+1 (>50 одинаковых в одном request_id) → warning.
- **Audit** (кто/что/когда/результат) — ОТДЕЛЬНЫЙ sink/индекс/retention, durable
  append-only, без сэмплинга, sync. Не смешивать с operational. Детали — §6.5 доки.

## Антипаттерны
Интерполяция в message; лог исключения на каждом catch; `throw` без `previous`;
`error("something happened")` (message = существительное+глагол, значения в context);
warning на всегда-срабатывающем пути; `info` в tight loop (сэмплинг/debug);
`request_id`/`user_id` как лейблы (→ поля); лог полного body (→ `size`/`content_type`);
catch-and-swallow без лога; `print_r`/`var_export` в message; sync-запись на request path.

## Транспорт
12-factor: app пишет JSON в **stdout/stderr**, не заботясь о роутинге/хранении →
агент (fluent-bit) тейлит → pipeline (Graylog). Backpressure на агенте, не в приложении.
Среды изолированы (dev/staging НЕ в один индекс с prod). Sampling — только info/debug
(notice+ всегда полностью); sticky-per-trace — де-факто стандарт; не сэмплить audit.

## Жизненный цикл
- **Линтер в CI:** запрет интерполяции в message, `print_r`/`var_export`, ban-list ключей.
- **PII regression тесты:** известные секреты НЕ попадают в логи (обязательно).
- **Каталог полей** (`docs/log-fields.yml`) — source of truth; whitelist для `tag`
  (auth, billing, sql, queue, upstream, entrypoint, audit, cron). Переименование поля =
  dual-write ≥2 релиза.
- **Алерты:** critical/emergency сразу; error >1% & count≥5; warning >5% & count≥20;
  notice >10% & count≥50; окно 5 мин. Метрика-цель — MTTR.
