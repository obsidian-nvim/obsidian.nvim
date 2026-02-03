SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help
PROJECT_NAME = "obsidian.nvim"
TEST = test/obsidian
LUARC = $(shell readlink -f .luarc.json)

# Depending on your setup you have to override the locations at runtime. E.g.:
#   make user-docs
MINITEST = deps/mini.test
MINIDOC = deps/mini.doc
# PANVIMDOC_PATH = ../panvimdoc/panvimdoc.sh
MARKDOC = deps/markdoc.nvim
NVIM_TREESITTER = deps/nvim-treesitter

NVIM ?= nvim
VIMRUNTIME ?= $(shell $(NVIM) --clean --headless +'lua io.write(vim.env.VIMRUNTIME)' +q 2>/dev/null)

################################################################################
##@ Start here
.PHONY: chores
chores: style lint types test ## Run development tasks (lint, style, types, test); PRs must pass this.

################################################################################
##@ Developmment
.PHONY: lint
lint: ## Lint the code with selene and typos
	selene --config selene/config.toml lua/ tests/
	typos lua

.PHONY: style
style:  ## Format the code with stylua
	stylua --check .

.PHONY: types
types: ## Type check with lua-ls
	lua-language-server --configpath "$(LUARC)" --check lua/obsidian/

.PHONY: checklua
checklua:
	VIMRUNTIME=$(VIMRUNTIME) emmylua_check ./lua/obsidian/

.PHONY: test
test: $(MINITEST)
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

$(MINITEST):
	mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $(MINITEST)

$(MARKDOC):
	mkdir -p deps
	git clone --filter=blob:none https://github.com/OXY2DEV/markdoc.nvim $(MARKDOC)

$(NVIM_TREESITTER):
	mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-treesitter/nvim-treesitter $(NVIM_TREESITTER) --branch main

.PHONY: user-docs
user-docs: $(MARKDOC) $(NVIM_TREESITTER) ## Generate user documentation with markdoc
	nvim \
		--headless \
		--clean \
		-u "scripts/markdoc.lua" \
		-c "qa!"

.PHONY: api-docs
api-docs: $(MINIDOC) ## Generate API documentation with mini.doc
	MINIDOC=$(MINIDOC) nvim \
		--headless \
		--noplugin \
		-c "luafile scripts/generate_api_docs.lua" \
		-c "qa!"

$(MINIDOC):
	git clone --depth 1 https://github.com/echasnovski/mini.doc $(MINIDOC)


################################################################################
##@ Helpers
.PHONY: version
version:  ## Print the obsidian.nvim version
	@nvim --headless -c 'lua io.write("v" .. require("obsidian").VERSION)' -c q 2>&1

.PHONY: help
help:  ## Display this help
	@echo "Welcome to $$(tput bold)${PROJECT_NAME}$$(tput sgr0) 🥳📈🎉"
	@echo ""
	@echo "To get started:"
	@echo "  >>> $$(tput bold)make chores$$(tput sgr0)"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


