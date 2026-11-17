SHELL = /bin/bash

include .make/all.mk

.PHONY: lint-bats
lint-bats: ## Check that the bats assertions do not pass vacuously on bash 3.2
	./dev/check_bats_assertions.sh tests

.PHONY: mutation-check
mutation-check: ## Check that the bats tests detect deliberate breakages of the script
	./dev/mutation_check.sh

.PHONY: check-export
check-export: ## Check that the exported files are the files the action needs
	./dev/check_export.sh

.PHONY: test
test: ## Run the bats tests
	bats --recursive tests

.PHONY: all
all: format lint test ## Format, lint and test

.PHONY: clean
clean: ## Remove the temporary files (see .gitignore)
	rm -f ./*.tmp ./*.bak ./*.log
