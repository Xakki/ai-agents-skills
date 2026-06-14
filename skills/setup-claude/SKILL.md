---
name: setup-claude
description: Universal template to set up Claude Code in any repository — generates CLAUDE.md, sub-agents, skills, .mcp.json, settings.json, and Makefile. Use when initializing Claude Code in a new project, auditing existing config, or migrating .claude/commands/ to skills. Token-economy focused; mandates make-targets; always asks user which hooks to enable.
when_to_use: User says "настрой Claude Code", "init claude", "сделай CLAUDE.md", "проанализируй проект и настрой агентов", "/setup-claude", or asks to configure sub-agents/skills/MCP/hooks for a repo.
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash WebFetch WebSearch Write Edit
---

# Setup Claude Code in this repository

Универсальный шаблон, не зависит от стека. Все артефакты — локально в репо и под git.

## 1. Цель

Настроить Claude Code так, чтобы агент тратил **минимум токенов** на повторяющиеся операции: не пересканировал структуру, знал процесс работы команды, имел узкоспециализированных сабагентов и скиллы только под реальные нужды.

## 2. Источники (обязательно — WebFetch перед работой)

Только официальная документация Anthropic. Канонический домен — `code.claude.com/docs/en/*`.

- `https://code.claude.com/docs/en/memory` — CLAUDE.md, иерархия, `@import`, `.claude/rules/`, auto memory
- `https://code.claude.com/docs/en/sub-agents` — фронтматтер, модель, tools, skills, mcpServers, isolation
- `https://code.claude.com/docs/en/skills` — `.claude/skills/<name>/SKILL.md`, фронтматтер, progressive disclosure
- `https://code.claude.com/docs/en/slash-commands` — legacy `.claude/commands/*.md` (merged into skills)
- `https://code.claude.com/docs/en/mcp` — `.mcp.json`, scopes, `claude mcp add`
- `https://code.claude.com/docs/en/settings` — hierarchy, permissions, enabledMcpjsonServers
- `https://code.claude.com/docs/en/hooks` — события, JSON-схема, exit-коды, matcher
- `https://code.claude.com/docs/en/common-workflows` и `https://code.claude.com/docs/en/best-practices`
- `https://code.claude.com/docs/llms.txt` — индекс

Если 404 — `WebSearch site:code.claude.com <topic>`. Сторонние блоги — игнорировать.

## 3. Discovery (фаза 1, без записи файлов)

1. `git log --oneline -30`, `git log --stat -10`, активные ветки
2. Корень: `ls -la`, манифесты (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Makefile`, `docker-compose.yml`)
3. README/CONTRIBUTING/TODO/CHANGELOG — выписать только **процесс команды** и **что нельзя трогать**
4. Существующие `CLAUDE.md` (managed → user → project), `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.mcp.json`, `AGENTS.md`
5. Карта стеков, монолит/модули, legacy vs new
6. Зоны-«не читать»: `vendor/`, `node_modules/`, `*_data/`, `dist/`, `build/`, бинари
7. **Наличие и качество `Makefile`**

Результат фазы 1 — отчёт ≤ 30 строк:
- Что найдено (стеки, процесс, существующая Claude-конфигурация, наследуемый родительский `CLAUDE.md`)
- Предложение: какие сабагенты / скиллы / MCP / правила
- План по `Makefile`: использовать / дополнить / создать
- **Запрос по хукам** (см. п. 4.8) с явным выбором

Дождаться `ок`. Альтернатива: предложить `/init` как стартовую точку, затем доработать.

## 4. Деливерэблы (фаза 2, после подтверждения)

### 4.1 `CLAUDE.md` (project)

`./CLAUDE.md` или `./.claude/CLAUDE.md`. **Лимит ≤ 200 строк** (рекомендация Anthropic).

Содержит **только то, что нельзя получить чтением кода**:
- Назначение проекта (1–3 строки)
- Архитектурная карта стеков
- **Команды — ссылка на `make help`** + 5–10 ключевых таргетов одной строкой
- Правила процесса: ветки, коммиты, ПР, деплой, что не вливать
- **Защищённые пути**: данные БД, секреты, артефакты сборки
- **Не индексировать без необходимости**: `vendor/`, `node_modules/`, дампы
- Указатели на TODO/ADR/runbooks
- `@import` родительских `CLAUDE.md` (макс 5 хопов; пути относительно файла)
- Если есть `AGENTS.md`: `@AGENTS.md` в начале
- **Жёсткое правило**: «Все операции с проектом — через `make <target>`. Если нужного таргета нет — добавить в `Makefile`, не запускать команду напрямую»

**Принципы из доки**:
- **Specificity**: «Use 2-space indentation» вместо «format code properly»
- Markdown-структура: заголовки и буллиты
- HTML-комментарии `<!-- ... -->` на блочном уровне вырезаются — для maintainer-заметок без расхода токенов
- В монорепо мешающие ancestor-CLAUDE.md исключать через `claudeMdExcludes` в `.claude/settings.local.json`

**Анти-паттерны**: пересказ структуры папок, дублирование README, объяснение фреймворка.

### 4.1a `.claude/rules/*.md` — опциональная альтернатива

Для крупных репо. Path-scoped rules через YAML-фронтматтер `paths:` — грузятся только при работе с матчящими файлами:

```yaml
---
paths:
  - "src/api/**/*.ts"
---
```

Без `paths:` — грузятся каждую сессию.

### 4.2 `.claude/agents/*.md` — сабагенты

Кандидаты: `*-explorer` для каждого крупного стека, `db-schema`, `log-investigator`, `test-runner`, `migration-author`.

**Фронтматтер (подтверждённые поля)**:
```yaml
---
name: code-reviewer            # required, lowercase + hyphens
description: When Claude should delegate here  # required
tools: Read, Glob, Grep, Bash  # comma-separated; omit = inherit all
disallowedTools: Write, Edit   # denylist (применяется первым)
model: sonnet                  # sonnet|opus|haiku|claude-opus-4-7|inherit
permissionMode: default        # default|acceptEdits|auto|dontAsk|bypassPermissions|plan
maxTurns: 20
skills: [api-conventions]      # preload skill content at startup
mcpServers: [your-mcp-server]
hooks: { ... }
memory: project                # user|project|local
isolation: worktree
effort: medium                 # low|medium|high|xhigh|max
background: false
color: cyan
---
```

Правила:
- `name` + `description` обязательны
- `tools:` (allowlist) **или** `disallowedTools:` (denylist) — не `*`
- `description` пишется так, чтобы Claude автоделегировал: «Use when…», «proactively after…»
- Узкий scope — сабагент возвращает только summary
- Инструкция «использовать `make`-таргеты»

### 4.3 `.claude/skills/<name>/SKILL.md` — скиллы

> Custom commands merged into skills. Создавать новые как скиллы.

```
.claude/skills/<name>/
├── SKILL.md              # required, ≤ 500 строк
├── reference.md          # supporting files — load on demand
└── scripts/helper.sh
```

**Фронтматтер**:
```yaml
---
name: prepare-pr                       # /skill-name; lowercase+hyphens, max 64
description: When Claude should use this skill  # обрезается на 1536 симв; front-load кейс
when_to_use: Дополнительные триггеры
argument-hint: "[issue-number]"
arguments: [issue, branch]
disable-model-invocation: false        # true = только пользователь
user-invocable: true                   # false = только Claude
allowed-tools: Bash(git *) Read Grep
model: inherit
effort: medium
context: fork                          # запуск в форк-сабагенте
agent: Explore
paths: ["src/api/**/*.ts"]
hooks: { ... }
shell: bash
---
```

Подстановки: `$ARGUMENTS`, `$0..$9`, `$name`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`. Бэш-инжекция: inline-форма (бэктик + восклицательный знак + бэктик-команда-бэктик) или fenced-блок с маркером `!` после открывающих трёх бэктиков. Выполняется ДО отправки в LLM. **В этом SKILL.md примеры приведены прозой, чтобы не триггерить инжекцию при загрузке.**

**Когда оправдан**: процедура (а) повторяется, (б) нетривиальна, (в) не помещается в 1–2 строки CLAUDE.md.

Кандидаты: `new-feature-branch`, `prepare-pr` (с `disable-model-invocation: true`), `release-checklist`, доменные.

### 4.4 `.claude/commands/*.md` — legacy

Не плодить новых. Существующие можно мигрировать в skills.

### 4.5 `.mcp.json` (project) — опционально

Только специфичные для проекта. Команды:
```bash
claude mcp add --transport http <name> <url>
claude mcp add --transport stdio --env KEY=VAL <name> -- npx -y <package>
```
При первом обнаружении — approval-диалог; явно перечислить серверы в `enabledMcpjsonServers`.

### 4.6 `.claude/settings.json` (командный, коммитится)

**Hierarchy**: managed → CLI → `.claude/settings.local.json` (gitignored) → `.claude/settings.json` (project) → `~/.claude/settings.json`. Массивы **мерджатся**.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(make *)",
      "Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)",
      "Read", "Grep", "Glob"
    ],
    "ask":  ["Bash(git push *)"],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force*)",
      "Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)"
    ],
    "defaultMode": "default"
  },
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": []
}
```

Eval order: deny → ask → allow (first match wins). `Bash(make *)` — приоритет.

`settings.local.json` — **в `.gitignore`** обязательно.

### 4.7 `Makefile` — обязательная часть деливерэбла

Если нет — создать. Если неполный — дополнить. **Все агенты, скиллы, команды используют только `make`-таргеты**.

```makefile
SHELL = /bin/bash
### https://makefiletutorial.com/

.PHONY: help create-local-files up down restart logs ps shell test lint fix migrate seed deploy clean
.DEFAULT_GOAL := help

##@ Help
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-@]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Init
create-local-files: ## Init local config (.env.local и т.п.)

##@ Dockers
up:        ## Docker UP
down:      ## Docker DOWN
restart:   ## Docker restart
logs:      ## Tail logs
ps:        ## Status
shell:     ## Shell в основной контейнер

##@ Dev
test:      ## Tests
lint:      ## Linters
fix:       ## Auto-fix

##@ DB
migrate:   ## Migrations
seed:      ## Seed

##@ Release
deploy:    ## Deploy
clean:     ## Clean caches/artifacts
```

Требования:
- Группы `##@ Section`, описание `## ...` у каждого таргета
- `.PHONY` для не-файловых, `.DEFAULT_GOAL := help`
- Параметры через `include .env` + `export`, не хардкод
- В `CLAUDE.md`: «если нужной операции нет — добавь таргет, затем используй»

### 4.8 Хуки — запрос у пользователя (обязательный шаг)

После Discovery — **спросить, какие хуки включить**. Без явного «да» — не добавлять.

**События**: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `PermissionRequest`, `PermissionDenied`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`.

**Handler-ы**: `command`, `http`, `mcp_tool`, `prompt`, `agent`. Поля: `matcher`, `if`, `timeout`, `async`, `asyncRewake`, `shell`, `once`, `statusMessage`.

**Exit-коды (command)**: `0` = OK + парс stdout JSON; `2` = blocking, stderr → Claude; **other** = non-blocking. (`WorktreeCreate` блокирует на любом ненулевом.)

**Matcher**: `*`/пусто = все; буквы+цифры+`_`+`|` = exact или OR; иные символы = JS regex.

**Кандидаты** (предложить пользователю с явным выбором):
```
[ ] PreToolUse + Bash: блок rm -rf, git push --force, прямых docker/npm в обход make  — низкий риск
[ ] PreToolUse + Edit|Write: блок записи в .env*, vendor/, node_modules/, дампы БД  — низкий риск
[ ] PostToolUse + Edit|Write: make lint после правок  — средний риск (правит код)
[ ] UserPromptSubmit: инъекция `git status --short`  — низкий риск, +токены
[ ] Stop / SubagentStop: уведомление в Telegram/Slack для долгих задач  — низкий риск
[ ] SessionStart matcher=startup: инъекция `make help`  — средний риск (+токены)
[ ] InstructionsLoaded: лог какие CLAUDE.md/rules загрузились  — нулевой риск
Включить: <номера через запятую> / none
```

**Безопасность**: hooks из project-settings шарятся через git → не коммитить кредениалы. Использовать `$CLAUDE_PROJECT_DIR`. Валидировать `tool_input` через `jq`. HTTP-хуки: только `allowedEnvVars` интерполируются. По умолчанию — **никаких хуков**.

## 5. Принципы экономии токенов

1. **Hierarchy CLAUDE.md** — общее в `~/.claude/CLAUDE.md`, специфика — в `./CLAUDE.md`. Не дублировать.
2. **Импорт, не копия** — `@path/to/file.md` (макс 5 hops; не уменьшает контекст, но удобнее).
3. **`.claude/rules/` с `paths:`** — грузятся только при матче.
4. **Узкие сабагенты** — основной контекст чище.
5. **Skills с `disable-model-invocation: true`** — описание не висит в контексте.
6. **Лимиты**: `CLAUDE.md` ≤ 200 строк, `SKILL.md` ≤ 500 строк, `description+when_to_use` ≤ 1536 симв.
7. **Lazy loading** — supporting files скилла грузятся on-demand.
8. **Reference-стиль** — «роуты в `X`, читай при необходимости».
9. **Явные «не читать» зоны** в CLAUDE.md.
10. **Единая точка входа — `Makefile`** — агенты не воспроизводят рецепты.
11. **HTML-комментарии** в CLAUDE.md для maintainer-заметок без расхода токенов.
12. **Auto memory** (v2.1.59+) — встроенный механизм; не дублировать в CLAUDE.md.

## 6. Безопасность и git

- `.gitignore`: `CLAUDE.local.md`, `.claude/settings.local.json`, секреты (`.env*`, `*credentials*`)
- При первом `@import` внешних файлов / `.mcp.json` — approval-диалог Claude Code
- Hooks из project-settings шарятся → не класть туда токены/ключи
- Все деливерэблы — один коммит со стилем из `git log`, **только когда пользователь явно попросит коммит**

## 7. Definition of Done

- [ ] Все фронтматтер-поля валидны по докам
- [ ] Проектный `CLAUDE.md` ≤ 200 строк, не дублирует родительские
- [ ] У сабагентов — `name` + `description` обязательны, `tools:` явный
- [ ] Скиллы используют `.claude/skills/<name>/SKILL.md`; legacy `.claude/commands/` не плодим
- [ ] `settings.json` коммитится; `settings.local.json`, `CLAUDE.local.md` в `.gitignore`
- [ ] **`Makefile` существует, `make help` работает с группами**
- [ ] CLAUDE.md обязывает использовать `make`-таргеты
- [ ] **Хуки согласованы с пользователем**
- [ ] Тестовый прогон: типовой вопрос ≤ 5 tool-вызовов
- [ ] Никаких чтений `vendor/`, `node_modules/`, дампов БД во время настройки
- [ ] Финальный отчёт: список файлов, размер в строках, добавленные `make`-таргеты, включённые хуки

## 8. Что **не** делать

- Не создавать «универсальных» агентов (есть `Explore`, `Plan`, `general-purpose`)
- Не переносить README/Makefile/доки в CLAUDE.md
- Не добавлять MCP, скиллы, агенты «на всякий случай»
- Не включать хуки без явного согласия
- Не вызывать команды стека напрямо, если есть/можно добавить `make`-таргет
- Не плодить новые `.claude/commands/*.md` (использовать skills)
- Не писать `docs/architecture.md` ради документации
- Не вносить правки в код проекта (только конфигурация Claude Code + `Makefile`)
