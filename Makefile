SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help
PROJECT_NAME = "obsidian.nvim"
TEST = test/obsidian
LUARC = $(shell readlink -f .luarc.json)

# Depending on your setup you have to override the locations at runtime. E.g.:
#   make test PLENARY=~/path/to/plenary.nvim
#   make user-docs PANVIMDOC_PATH=~/path/to/panvimdoc/panvimdoc.sh
PLENARY = ~/.local/share/nvim/lazy/plenary.nvim/
MINIDOC = ~/.local/share/nvim/lazy/mini.doc/
PANVIMDOC_PATH = ../panvimdoc/panvimdoc.sh

################################################################################
##@ Start here
.PHONY: chores
chores: style lint types test ## Run develoment tasks (lint, style, types, test); PRs must pass this.

################################################################################
##@ Developmment
.PHONY: lint
lint: ## Lint the code with luacheck
	luacheck .

.PHONY: style
style:  ## Format the code with stylua
	stylua --check .

# TODO: add type checking with lua-ls
types: ## Type check with lua-ls
	lua-language-server --configpath $(LUARC) --check lua/obsidian/

.PHONY: test
test: $(PLENARY) ## Run unit tests
	PLENARY=$(PLENARY) nvim \
		--headless \
		--noplugin \
		-u test/minimal_init.vim \
		-c "PlenaryBustedDirectory $(TEST) { minimal_init = './test/minimal_init.vim' }"

$(PLENARY):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git $(PLENARY)

.PHONY: user-docs
user-docs: ## Generate user documentation with panvimdoc
	@if [ ! -f "$(PANVIMDOC_PATH)" ]; then \
		echo "panvimdoc.sh not found at '$(PANVIMDOC_PATH)'. Make sure it is installed and check the path."; \
		exit 1; \
	fi
	$(PANVIMDOC_PATH) \
		--project-name obsidian \
		--input-file README.md \
		--toc false \
		--description 'a plugin for writing and navigating an Obsidian vault' \
		--vim-version 'NVIM v0.10.0' \
		--demojify false \
		--dedup-subheadings false \
		--shift-heading-level-by -1 \
		--ignore-rawblocks true \
		&& mv doc/obsidian.txt /tmp/

.PHONY: api-docs
api-docs: $(MINIDOC) ## Generate API documentation with mini.doc
	MINIDOC=$(MINIDOC) nvim \
		--headless \
		--noplugin \
		-u scripts/minimal_init.vim \
		-c "luafile scripts/generate_api_docs.lua" \
		-c "qa!"

$(MINIDOC):
	git clone --depth 1 https://github.com/echasnovski/mini.doc $(MINIDOC)


################################################################################
##@ Helpers
.PHONY: version
version:  ## Print the obsidian.nvim version
	@nvim --headless -c 'lua print("v" .. require("obsidian").VERSION)' -c q 2>&1

.PHONY: help
help:  ## Display this help
	@echo "Welcome to $$(tput bold)${PROJECT_NAME}$$(tput sgr0) 🥳📈🎉"
	@echo ""
	@echo "To get started:"
	@echo "  >>> $$(tput bold)make chores$$(tput sgr0)"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
