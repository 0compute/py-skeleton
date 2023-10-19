# {{{ globals

ifdef IN_NIX_SHELL

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

HERE = $(dir $(lastword $(MAKEFILE_LIST)))

ARGS ?=

PYPROJECT = pyproject.toml

# }}}

# {{{ build

.PHONY: result
result:
	nix build --file default.nix --out-link $@

NAME ?= $(shell grep "^name" $(PYPROJECT) | sed "s/  */ /g" | cut -d\" -f2)

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

# {{{ basic

.PHONY: test
test:
	pytest $(ARGS)

# }}}

# {{{ coverage

COV ?=
COV_REPORT ?= term-missing:skip-covered html
COV_CFG =
# conf `coverage.run.dynamic_context` breaks with pytest-cov so we set --cov-context=test
# https://github.com/pytest-dev/pytest-cov/issues/604
COV_ARGS = \
	--cov \
	--cov-context=test \
	$(addprefix --cov-report=,$(COV_REPORT))

# needed for subprocess coverage
SITE_CUSTOMIZE = tests/sitecustomize.py
$(SITE_CUSTOMIZE):
	echo > $@ "import coverage; coverage.process_startup()"

.PHONY: test-cov
test-cov: export COVERAGE_PROCESS_START = $(CURDIR)/$(if $(COV_CFG),$(COV_CFG),$(PYPROJECT))
test-cov: export PYTHONPATH := $(CURDIR)/tests:$(PYTHONPATH)
test-cov: $(SITE_CUSTOMIZE)
	pytest $(COV_ARGS) $(ARGS)

# }}}

# {{{ subtest

SUBTEST_TEST = test-$1
SUBTEST_COV = test-$1-cov
SUBTEST_TARGETS = $(SUBTEST_TEST) $(SUBTEST_COV)

XDIST_PROCESSES ?= logical

tests/.covcfg-%.toml: $(HERE)covcfg.py $(PYPROJECT)
	./$^ $* > $@

define SUBTEST
.PHONY: test-$1

ifneq ($(shell find tests -path \*$1\*.py),)
$(SUBTEST_TARGETS): override ARGS += -k $1
endif

ifneq ($(wildcard tests/$1/pytest),)
$(SUBTEST_TARGETS): override ARGS += $$(file < tests/$1/pytest)
endif

ifneq ($(wildcard tests/$1/xdist),)
$(SUBTEST_TARGETS): override ARGS += --numprocesses=$(XDIST_PROCESSES)
endif

ifneq ($(wildcard tests/$1/covcfg.toml),)
tests/.covcfg-$1.toml: tests/$1/covcfg.toml
$(SUBTEST_COV): COV_CFG = tests/.covcfg-$1.toml
$(SUBTEST_COV): tests/.covcfg-$1.toml
$(SUBTEST_COV): override COV_ARGS += --cov-config=$$(COV_CFG)
endif

$(SUBTEST_TEST): test
$(SUBTEST_COV): test-cov

endef

$(foreach test, \
	$(shell find tests -mindepth 1 -maxdepth 1 -type d), \
	$(eval $(call SUBTEST,$(notdir $(test)))))

# }}}

# }}}

# {{{ setup

ifneq ($(HERE),./)

SKEL_FILES = .envrc .pre-commit-config.yaml

$(SKEL_FILES):
	ln -sf $(HERE)$@

.PHONY: setup
setup: $(SKEL_FILES)

endif

endif

# }}}
