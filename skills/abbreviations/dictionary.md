# Словарь сокращений (dictionary)

Полный, растущий список общепринятых сокращений для имён (переменные,
функции, классы, CSS-классы, токены) и для сжатого технического текста.
Правило пополнения и политика использования — в [SKILL.md](SKILL.md).

Формат таблицы: `Сокращ.` (abbreviation) | `Полное` (full form, English) |
`Контекст` (typical usage context, RU).

## Базовый набор (исходный, из project CLAUDE.md)

| Сокращ. | Полное | Контекст |
|---|---|---|
| `cfg` | config | конфиг-объект, опции |
| `ctx` | context | контекст вызова / DI / транзакции |
| `req` / `res` | request / response | HTTP / RPC |
| `err` | error | переменная ошибки |
| `idx` / `i` | index | счётчики циклов |
| `prev` / `next` | previous / next | соседние элементы / итерации |
| `tmp` | temporary | временная переменная |
| `auth` | authentication / authorization | вход / права |
| `dto` / `vo` | Data Transfer Object / Value Object | контракты |
| `fs` | filesystem | файлы |
| `db` | database | БД |
| `id` | identifier | первичный ключ / uuid |
| `cmd` | command | CLI / Yii command |
| `env` | environment | переменные окружения |
| `dir` | directory | каталог |
| `min` / `max` | minimum / maximum | границы |
| `pos` | position | координаты / индекс |
| `qty` | quantity | количество |

## Общие переменные и поток управления

| Сокращ. | Полное | Контекст |
|---|---|---|
| `msg` | message | текст сообщения / события / лога |
| `buf` | buffer | буфер данных (байты, строки, каналы) |
| `len` | length | длина строки/слайса/буфера |
| `cnt` / `count` | count | счётчик элементов/событий |
| `num` | number | число, номер (не путать с `id`) |
| `val` | value | значение (переменная/поле/результат вычисления) |
| `ptr` | pointer | указатель |
| `ref` | reference | ссылка (не указатель — логическая ссылка/ключ) |
| `arg` / `args` | argument(s) | аргументы функции/CLI |
| `param` / `params` | parameter(s) | параметры функции/запроса (внешне заданные, в отличие от `arg` — по смыслу почти взаимозаменяемы, выбирай то, что уже используется в модуле) |
| `opt` / `opts` | option(s) | опции/флаги конфигурации |
| `resp` | response | синоним `res` там, где `res` уже занято (напр. `resource`) — **неоднозначность**: если в модуле уже есть `res`=resource, используй `resp` для response |
| `acc` | accumulator / account | **неоднозначно** — в цикле/reduce почти всегда accumulator, в auth/billing-коде — account; при риске путаницы пиши полное слово |
| `amt` | amount | денежная/числовая величина (платежи, объёмы) |
| `avg` | average | среднее значение |
| `sum` | sum | сумма |
| `agg` | aggregate / aggregation | агрегированное значение/функция |
| `calc` | calculate / calculation | вычисление |
| `gen` | generate / generator | генерация значения / генератор |
| `idx` / `i` / `j` / `k` | index | счётчики вложенных циклов (`i` внешний, `j`/`k` вложенные) |
| `ok` | ok (boolean success flag) | второй возврат в Go (`v, ok := m[k]`), успех операции |
| `fn` | function | функция как значение/параметр (особенно JS/Go) |
| `cb` | callback | функция обратного вызова |
| `ch` / `chan` | channel | Go-канал |
| `wg` | wait group | `sync.WaitGroup` |
| `mu` / `mux` | mutex | `sync.Mutex` (`mux` также означает multiplexer — уточняй по контексту: HTTP-роутер vs блокировка) |
| `sig` | signal | ОС-сигнал / сигнал завершения |

## Типы и данные

| Сокращ. | Полное | Контекст |
|---|---|---|
| `obj` | object | объект/структура |
| `arr` | array | массив/слайс |
| `str` | string | строка |
| `int` | integer | целое число |
| `bool` | boolean | булево значение |
| `char` | character | символ |
| `elem` | element | элемент коллекции/DOM |
| `attr` | attribute | атрибут (DOM, структура, ORM) |
| `prop` | property | свойство (объект, компонент UI) |
| `kv` | key-value | пара ключ-значение, KV-хранилище |
| `id` | identifier | первичный ключ / uuid (см. базовый набор) |
| `uuid` | universally unique identifier | UUID-идентификатор |
| `ts` | timestamp | метка времени |
| `dt` | date-time / datetime | дата-время как тип/поле |
| `dur` | duration | продолжительность (`time.Duration` и аналоги) |
| `ns` / `ms` / `us` | nanosecond / millisecond / microsecond | единицы времени |
| `kb` / `mb` / `gb` | kilobyte / megabyte / gigabyte | единицы объёма данных |

## Структура кода / архитектура

| Сокращ. | Полное | Контекст |
|---|---|---|
| `impl` | implementation | реализация интерфейса/абстракции |
| `init` | initialize / initialization | инициализация |
| `util` / `utils` | utility / utilities | вспомогательные функции |
| `svc` | service | сервисный слой |
| `repo` | repository | слой доступа к данным (repository pattern) |
| `mgr` | manager | менеджер (управляющая сущность, напр. `ConnMgr`) |
| `ctl` / `ctrl` | controller | контроллер (MVC/HTTP) |
| `hdlr` | handler | обработчик (HTTP/событий/ошибок) |
| `pkg` | package | пакет (Go/npm) |
| `mod` | module | модуль |
| `lib` | library | библиотека |
| `bin` | binary | бинарный файл/директория сборки |
| `src` | source | исходный код/директория |
| `doc` / `docs` | document(ation) | документация |
| `spec` | specification | спецификация/описание теста (`_spec` в тестах) |
| `def` | definition | определение (тип, схема) |
| `decl` | declaration | объявление (переменной/типа) |
| `expr` | expression | выражение (AST, парсинг) |
| `stmt` | statement | оператор/инструкция (SQL, AST) |
| `ns` | namespace | пространство имён |
| `cap` | capacity | ёмкость (Go slice/map `cap()`, лимиты) |

## Домены и протоколы

| Сокращ. | Полное | Контекст |
|---|---|---|
| `orm` | Object-Relational Mapping | ORM-слой |
| `sql` | Structured Query Language | язык запросов к БД |
| `ddl` / `dml` | Data Definition / Manipulation Language | DDL — схема, DML — данные |
| `crud` | Create, Read, Update, Delete | базовые операции над сущностью |
| `pk` / `fk` | primary key / foreign key | ключи таблиц БД |
| `tx` | transaction | **неоднозначно** с `transmit`/`text` в некоторых доменах (радио/сети) — в контексте БД/бэкенда почти всегда transaction; при работе с сетевым/radio-кодом уточняй явным именем |
| `conn` | connection | сетевое/БД-соединение |
| `pool` | (connection) pool | пул соединений/ресурсов |
| `cache` | cache | кэш (не сокращение, но частый корень: `cacheKey`, `cacheTTL`) |
| `ttl` | time to live | время жизни записи/кэша |
| `mq` | message queue | очередь сообщений |
| `pubsub` | publish-subscribe | паттерн pub/sub |
| `ws` | WebSocket | WebSocket-соединение |
| `rpc` | Remote Procedure Call | RPC-вызов |
| `http` | HyperText Transfer Protocol | HTTP-протокол |
| `url` / `uri` | Uniform Resource Locator / Identifier | ссылка/идентификатор ресурса |
| `dns` | Domain Name System | DNS |
| `ip` | Internet Protocol (address) | IP-адрес |
| `tls` / `ssl` | Transport Layer Security / Secure Sockets Layer | шифрование транспорта |
| `jwt` | JSON Web Token | JWT-токен |
| `hmac` | Hash-based Message Authentication Code | HMAC-подпись |
| `csrf` | Cross-Site Request Forgery | CSRF-защита/токен |
| `cors` | Cross-Origin Resource Sharing | CORS-политика |
| `cdn` | Content Delivery Network | CDN |
| `api` | Application Programming Interface | API |
| `cli` | Command-Line Interface | CLI-утилита |
| `ui` / `ux` | User Interface / User Experience | интерфейс / опыт использования |
| `i18n` / `l10n` | internationalization / localization | numeronym: i + 18 букв + n / l + 10 букв + n |
| `regex` / `re` | regular expression | регулярное выражение |
| `json` / `yaml` / `csv` | JavaScript Object Notation / YAML Ain't Markup Language / Comma-Separated Values | форматы данных |
| `ci` / `cd` | Continuous Integration / Continuous Delivery(Deployment) | CI/CD-пайплайн |
| `k8s` | Kubernetes | Kubernetes (numeronym: k + 8 букв + s) |

## Конкурентность и асинхронность

| Сокращ. | Полное | Контекст |
|---|---|---|
| `sync` | synchronous / synchronization | синхронный код / примитив синхронизации |
| `async` | asynchronous | асинхронный код |
| `concur` | concurrency / concurrent | параллелизм/конкурентность |
| `seq` | sequence / sequential | последовательность / последовательное выполнение |
| `deadline` | deadline | предельное время выполнения (`context.WithDeadline`) |
| `ctx` | context | контекст вызова/отмены (см. базовый набор) |
| `goroutine` | — | **не сокращать** — общепринятого сокращения нет, писать полностью |
