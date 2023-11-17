# {{{ globals

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

HERE = $(patsubst %/,%,$(dir $(lastword \
	   $(shell realpath --relative-to $(CURDIR) $(MAKEFILE_LIST)))))

ARGS ?=

PYPROJECT = pyproject.toml

# }}}

# {{{ help

define _HELP
Pyproject Env

Global:
  ARGS: Append to target command line

Targets:

  build: Build with `nix build`

  push: Push to cachix

  lint: Run pre-commit lint

  mypy: Run mypy

  ruff: Run ruff

  whitelist: Write whitelist to $(WHITELIST)

  test: Run pytest
    EXPR: Filter tests by substring expression, passed as "-k"

  test-cov: Run pytest with coverage
    EXPR: As above
    COV_REPORT: Coverage report types (current: $(COV_REPORT)) - see `pytest --help /--cov-report`
endef

.PHONY: help
help:
	$(info $(_HELP))
	@true

# }}}

# {{{ build

.PHONY: build
build: result

.PHONY: result
result: override ARGS += --out-link $@
result:
	nix build $(ARGS)

NAME ?= $(shell grep "^name" $(PYPROJECT) | cut -d\" -f2)

.PHONY: push
result: override ARGS += $<
push: result
	cachix push $(NAME) $(ARGS)

# }}}

# {{{ lint

.PHONY: lint
lint:
	pre-commit run -a $(ARGS)

.PHONY: mypy
ifeq ($(ARGS),)
mypy: override ARGS = .
endif
mypy:
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

EXPR ?=

TEST_PATH ?=

_EMPTY :=
_SPACE := $(_EMPTY) $(_EMPTY)

.PHONY: test
test: override ARGS += $(if $(EXPR),-k "$(subst $(_SPACE), and ,$(strip $(EXPR)))")
test:
	pytest $(strip $(ARGS) $(TEST_PATH))

# }}}

# {{{ coverage

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
test-cov: override ARGS += $(COV_ARGS)
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
$(SUBTEST_TARGETS): override ARGS += $$(file < tests/$1/pytest)
endif

ifneq ($(wildcard tests/$1/xdist),)
$(SUBTEST_TARGETS): override ARGS += --numprocesses=$(NUM_PROCESSES)
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
	$(shell find tests -mindepth 1 -maxdepth 1 -type d \
		-not -name .\* -and -not -name __pycache__ -and -not -name coverage\* | sort), \
	$(eval $(call SUBTEST,$(notdir $(test)))))

# }}}

# }}}

# {{{ setup

ifneq ($(HERE),.)

SKEL_FILES = Makefile .envrc .pre-commit-config.yaml

$(SKEL_FILES):
	ln -sf $(HERE)$@

.PHONY: setup
setup: $(SKEL_FILES)

define _HELP :=
$(_HELP)

  setup: Link skeleton files ($(SKEL_FILES)) to $(CURDIR)
endef

endif

# }}}
