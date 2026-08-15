SHELL = /bin/bash

INSTALL_DIR ?= $(HOME)/.claude/plugins/cache/ai-agents-skills/ai-agents-skills/$(shell awk '/^version:/{gsub(/"/,"",$$2);print $$2}' plugin.yaml)
ACT        ?= skills/agent-config-test

.PHONY: help test test-hooks test-lint sync install-path
.DEFAULT_GOAL := help

##@ Help
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Test
test: test-hooks test-lint  ## Full gate: hook behaviour + settings lint

test-hooks:  ## Assert guard-bash blocks/allows the right commands
	$(ACT)/test-hooks.sh hooks/guard-bash.sh $(ACT)/cases/guard-bash.tsv

test-lint:  ## Lint settings of a project: make test-lint DIR=/path
	$(ACT)/lint-settings.sh $(or $(DIR),$(CURDIR))

##@ Plugin
install-path:  ## Print the dir the running plugin loads from
	@echo $(INSTALL_DIR)

# Overlay only, never --delete: the install dir is ahead of the checkout whenever
# autoUpdate pulled a pushed commit this checkout lacks, and --delete would drop
# those skills. Test-only path; the durable one is commit+push.
sync:  ## Overlay hooks+skills onto the install dir to test before commit
	@test -d "$(INSTALL_DIR)" || { echo "not found: $(INSTALL_DIR)"; exit 1; }
	rsync -a hooks/ "$(INSTALL_DIR)/hooks/"
	rsync -a skills/ "$(INSTALL_DIR)/skills/"
	@echo "synced -> $(INSTALL_DIR)  (open a NEW session to load it)"
