SHELL=/bin/bash

.PHONY : format
format :
	markdownlint **/*.md
	shellcheck **/*.sh
	shfmt -l -w **/*.sh
	prettier --write .
	yamllint -f colored .
