# {{{ globals

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

HERE = $(patsubst %/,%,$(dir $(lastword \
	   $(shell realpath --relative-to $(CURDIR) $(MAKEFILE_LIST)))))

ARGV ?=

PYPROJECT = pyproject.toml

# }}}

# {{{ help

define _HELP
Pyproject Env

Global:
  ARGV: Append to target command line

Targets:

  build: Build with `nix build`

  push: Push to cachix

  lint: Run pre-commit lint

  mypy: Run mypy

  check: Run ruff check

  format: Run ruff format

  whitelist: Write whitelist to $(WHITELIST)

  test: Run pytest
    EXPR: Filter tests by substring expression, passed as "-k"
    TEST_PATH: Path to test file or directory

  test-cov: Run pytest with coverage
    EXPR/TEST_PATH: As above
    COV_REPORT: Coverage report types (current: $(COV_REPORT)) - see `pytest --help /--cov-report`
endef

.PHONY: help
help:
	$(info $(_HELP))
	@true

# }}}

# {{{ build

GIT_UNTRACKED != git ls-files --others --exclude-standard

.PHONY: build
build: result

.PHONY: result
result: override ARGV += --out-link $@
result:
	$(if $(GIT_UNTRACKED),$(error Untracked files: [ $(GIT_UNTRACKED) ]))
	nix build $(ARGV)

NAME ?= $(shell grep "^name" $(PYPROJECT) | cut -d\" -f2)

.PHONY: push
push: override ARGV += $<
push: result
	cachix push $(NAME) $(ARGV)

# }}}

# {{{ lint

.PHONY: lint
lint:
	pre-commit run -a $(ARGV)

.PHONY: mypy
ifeq ($(ARGV),)
mypy: override ARGV = .
endif
mypy:
	dmypy run $(ARGV)

.PHONY: check
check: override ARGV += .
check:
	ruff check $(ARGV)

.PHONY: format
format: override ARGV += .
format:
	ruff format $(ARGV)

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
	$(addprefix --cov-report=,$(COV_REPORT))

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

# }}}

# {{{ subtest

SUBTEST_TEST = test-$1
SUBTEST_COV = test-$1-cov
SUBTEST_TARGETS = $(SUBTEST_TEST) $(SUBTEST_COV)

NUM_PROCESSES ?= logical

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

# }}}

# {{{ admin

.PHONY: fu
fu:
	nix flake update $(ARGV)

ifneq ($(HERE),.)

SKEL_FILES = Makefile .envrc .taplo.toml .yamllint.yml

$(SKEL_FILES):
	ln --symbolic --force --relative $(HERE)/$@ $@

.PHONY: setup
setup: $(SKEL_FILES)

define _HELP :=
$(_HELP)

  setup: Link skeleton files ($(SKEL_FILES)) to $(CURDIR)
endef

endif

# }}}
