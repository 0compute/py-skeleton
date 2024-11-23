# {{{ globals

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

PYPROJECT = pyproject.toml

ARGV ?=

# }}}

# {{{ help

.PHONY: help
help:
	$(info $(_HELP))
	@true

define _HELP
PyProject Dev

variables:

  ARGV: Append to target command line

targets:

  fs: `nix flake show`

  fu: `nix flake update`

  package: `nix build`

  push: `cachix push`

  lint: `pre-commit run`
endef

# }}}

# {{{ nix

NIX ?= nix

NIX_ARGV ?= --show-trace

nix = $(strip $(NIX) $(NIX_ARGV) $1 $(ARGV))

.PHONY: nix-%
.flake-%:
	$(call nix,flake $(subst _,-,$(subst -, ,$*)))

.PHONY: fs fu fm
fs: .flake-show
fu: .flake-update
fm: .flake-metadata

# }}}

# {{{ build

OUTPUTS = package dev-shell

.PHONY: $(OUTPUTS)
$(OUTPUTS): override ARGV += --out-link $@
$(OUTPUTS):
	$(call nix,build)

dev-shell: SYSTEM ?= $(shell $(NIX) eval --impure --raw --expr builtins.currentSystem)
dev-shell: override ARGV += .\#devShells.$(SYSTEM).default

push: NAME = $(shell python -c "print(__import__('tomllib').load(open('$(PYPROJECT)', 'rb'))['project']['name'])")
push: $(OUTPUTS)
	cachix push $(NAME) $^ $(ARGV)

# }}}

# {{{ lint

.PHONY: lint
lint:
	pre-commit run --all-files $(ARGV)

# }}}

# {{{ test

ifneq ($(wildcard tests),)

# {{{ whitelist

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

# {{{ basic

EXPR ?=

TEST_PATH ?=

_EMPTY :=
_SPACE := $(_EMPTY) $(_EMPTY)

.PHONY: test
test: override ARGV += $(if $(EXPR),-k "$(subst $(_SPACE), and ,$(strip $(EXPR)))")
test:
	pytest $(strip $(ARGV) $(TEST_PATH))

# }}}

# {{{ coverage

COV_REPORT ?= term-missing:skip-covered html
COV_CFG =
# conf `coverage.run.dynamic_context` breaks with pytest-cov so we set --cov-context=test
# https://github.com/pytest-dev/pytest-cov/issues/604
COV_ARGV = \
	--cov \
	--cov-context=test \
	$(addprefix --cov-report=,$(COV_REPORT)) \
	--no-cov-on-fail

# needed for subprocess coverage
SITE_CUSTOMIZE = .site/sitecustomize.py
$(SITE_CUSTOMIZE):
	mkdir -p $(@D)
	echo > $@ "import coverage; coverage.process_startup()"

# define if not set to silence warning
NIX_PYTHONPATH ?=

.PHONY: test-cov
test-cov: export COVERAGE_PROCESS_START = $(CURDIR)/$(if $(COV_CFG),$(COV_CFG),$(PYPROJECT))
# use NIX_PYTHONPATH as this sets the contents as site dirs, which is needed to pick
# up sitecustomize
test-cov: export NIX_PYTHONPATH := $(CURDIR)/$(patsubst %/,%,$(dir $(SITE_CUSTOMIZE))):$(NIX_PYTHONPATH)
test-cov: override ARGV += $(COV_ARGV)
test-cov: $(SITE_CUSTOMIZE) test

define _HELP :=
	$(_HELP)

  whitelist: write vulture whitelist

  test: run tests
    EXPR: Filter tests by substring expression
    TEST_PATH: Path to test file or directory

  test-cov: run tests with coverage
    EXPR/TEST_PATH: As above
    COV_REPORT: Coverage report types (current: $(COV_REPORT))
                see `pytest --help /--cov-report`
endef

# }}}

# {{{ subtest

SUBTEST_TEST = test-$1
SUBTEST_COV = test-$1-cov
SUBTEST_TARGETS = $(SUBTEST_TEST) $(SUBTEST_COV)

NUM_PROCESSES ?= logical

HERE = $(patsubst %/,%,$(dir $(lastword \
			 $(shell realpath --relative-to $(CURDIR) $(MAKEFILE_LIST)))))

tests/.covcfg-%.toml: $(HERE)/covcfg.py $(PYPROJECT)
	./$^ $* > $@

define SUBTEST
.PHONY: test-$1

define _HELP :=
$(_HELP)

  $(SUBTEST_TARGETS): Sub test and coverage
endef

ifneq ($(shell find tests -path \*$1\*.py),)
$(SUBTEST_TARGETS): TEST_PATH = tests/$1
endif

ifneq ($(wildcard tests/$1/pytest),)
$(SUBTEST_TARGETS): override ARGV += $$(file < tests/$1/pytest)
endif

ifneq ($(wildcard tests/$1/xdist),)
$(SUBTEST_TARGETS): override ARGV += --numprocesses=$(NUM_PROCESSES)
endif

ifneq ($(wildcard tests/$1/covcfg.toml),)
tests/.covcfg-$1.toml: tests/$1/covcfg.toml
$(SUBTEST_COV): COV_CFG = tests/.covcfg-$1.toml
$(SUBTEST_COV): tests/.covcfg-$1.toml
$(SUBTEST_COV): override COV_ARGV += --cov-config=$$(COV_CFG)
endif

$(SUBTEST_TEST): test
$(SUBTEST_COV): test-cov

endef

$(foreach test, \
	$(shell find tests -mindepth 1 -maxdepth 1 -type d \
		-not -name .\* -and -not -name __pycache__ -and -not -name coverage\* | sort), \
	$(eval $(call SUBTEST,$(notdir $(test)))))

# }}}

endif

# }}}
