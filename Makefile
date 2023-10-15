# {{{ globals

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

ARGS ?=

# }}}

# {{{ build

.PHONY: result
result:
	nix build --file default.nix --out-link $@

NAME ?= $(shell basename $(CURDIR))

.PHONY: push
push: result
	grep -q $(NAME).cachix.org ~/.config/nix/nix.conf || cachix use $(NAME)
	cachix push $(NAME) $<

# }}}

# {{{ lint

.PHONY: lint
lint:
	pre-commit run -a $(ARGS)

DMYPY_JSON = .dmypy.json

.PHONY: mypy
ifeq ($(ARGS),)
mypy: override ARGS = .
endif
mypy:
# dmypy is flaky af so make this a fresh run
ifneq ($(wildcard $(DMYPY_JSON)),)
	-kill $$(jq '.["pid"]' $(DMYPY_JSON))
endif
	dmypy run $(ARGS)

.PHONY: ruff
ruff: override ARGS += .
ruff:
	ruff check $(ARGS)

WHITELIST = tests/whitelist.py

.PHONY: $(WHITELIST)
$(WHITELIST):
	echo > $@ "# whitelist for vulture"
	echo >> $@ "# ruff: noqa"
	echo >> $@ "# type: ignore"
	-vulture --make-whitelist . >> $@

.PHONY: whitelist
whitelist: $(WHITELIST)

# }}}

# {{{ test

SITE_CUSTOMIZE = tests/sitecustomize.py
$(SITE_CUSTOMIZE):
	echo > $@ "import coverage; coverage.process_startup()"

export PYTHONPATH := $(CURDIR)/tests:$(PYTHONPATH)

COV_REPORT ?= html

COV_CFG = pyproject.toml

COV_ARGS = --cov \
		   --cov-config=$(COV_CFG) \
		   --cov-context=test \
		   --no-cov-on-fail \
		   --cov-report=term-missing:skip-covered \
		   $(addprefix --cov-report=,$(COV_REPORT))

.covcfg-%.toml: covcfg.py pyproject.toml covcfg-%.toml
	./$^ > $@

EXPR ?=

define TEST
.PHONY: .test-$1

.test-$1: override ARGS += -k "$1$(if $(EXPR), and $(EXPR))"
.test-$1: $(SITE_CUSTOMIZE)
	pytest $$(COV_ARGS) $$(ARGS)

ifneq ($(wildcard covcfg-$1.toml),)
.test-$1: .covcfg-$1.toml
.test-$1: COV_CFG = .covcfg-$1.toml
.test-$1: export COVERAGE_PROCESS_START = $$(CURDIR)/$$(COV_CFG)
endif

.PHONY: $1
test-$1: .test-$1
endef

$(eval $(call TEST,unit))
$(eval $(call TEST,functional))
$(eval $(call TEST,acceptance))

.PHONY: test
test: .test-unit .test-functional .test-acceptance
	coverage combine --keep $(addprefix .coverage-,$(patsubst .test-%,%,$^))
	coverage report --show-missing
	for report in $(COV_REPORT); do coverage $$report; done

# }}}

# {{{ setup

SKEL_DIR = $(dir $(lastword $(MAKEFILE_LIST)))

ifneq ($(SKEL_DIR),./)

SKEL_FILES = $(shell git -C $(SKEL_DIR) ls-files | grep -Ev "README.md|action.yml")

$(SKEL_FILES):
	ln -sf $(SKEL_DIR)$@

.PHONY: setup
setup: $(SKEL_FILES)

endif

# }}}
