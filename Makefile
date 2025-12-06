SHELL=/bin/bash

.PHONY : format
format :
	shellcheck **/*.sh
	shfmt -l -w **/*.sh
