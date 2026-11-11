SHELL = /bin/bash

# Lint the Markdown files of the root too: the shell does not expand "**" without
# globstar, so an unquoted pattern would skip them (it is expanded by markdownlint)
MARKDOWN_LINT_GLOB := '**/*.md'

# There is no *.mk file in the root: the unmatched glob made checkmake fail
MAKEFILE_FORMAT_FILES := Makefile
MAKEFILE_LINT_FILES := Makefile

include .make/help.mk
include .make/makefile.mk
include .make/markdown.mk
include .make/self.mk
include .make/shell.mk
include .make/toml.mk
include .make/uv.mk
include .make/yaml.mk

.DEFAULT_GOAL := help

.PHONY: format
format: format-yaml format-makefile format-shell format-toml format-markdown ## Format all files

.PHONY: lint
lint: lint-yaml lint-makefile lint-shell lint-markdown lint-bats ## Lint all files

.PHONY: lint-bats
lint-bats: ## Check that the bats assertions do not pass vacuously on bash 3.2
	./dev/check_bats_assertions.sh tests

.PHONY: mutation-check
mutation-check: ## Check that the bats tests detect deliberate breakages of the script
	./dev/mutation_check.sh

.PHONY: test
test: ## Run the bats tests
	bats --recursive tests

.PHONY: all
all: format lint test ## Format, lint and test

.PHONY: clean
clean: ## Remove the temporary files (see .gitignore)
	rm -f ./*.tmp ./*.bak ./*.log
