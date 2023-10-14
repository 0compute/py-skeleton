# {{{ globals

SHELL = bash -eu -o pipefail

override MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

.DELETE_ON_ERROR:

export CLICOLOR_FORCE = 1

export FORCE_COLOR = 1

ARGS ?=

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

TEST_PATH ?=

EXPRESSION ?=

COV_REPORT ?= html

COV_CFG = pyproject.toml

COV_ARGS = --cov \
		   --cov-context test \
		   --no-cov-on-fail \
		   --cov-report term-missing:skip-covered \
		   --cov-report $(COV_REPORT)

.covcfg-%.toml: covcfg.py pyproject.toml covcfg-%.toml
	./$^ > $@

_NOOP =
_SPACE = $(_NOOP) $(_NOOP)

define TEST
.PHONY: $1
$1: TEST_PATH = tests/$2
$1: export PYTHONPATH := $(CURDIR)/tests:$$(PYTHONPATH)
$1: export COVERAGE_PROCESS_START = $(CURDIR)/$$(COV_CFG)
ifneq ($(EXPRESSION),)
$1: override ARGS += $$(addprefix -k$(_SPACE),$(EXPRESSION))
endif
$1: $$(SITE_CUSTOMIZE)
ifneq ($(wildcard covcfg-$1.toml),)
$1: COV_CFG = .covcfg-$1.toml
$1: override COV_ARGS += --cov-config=$$(COV_CFG)
$1: .covcfg-$1.toml
endif
$1:
	pytest $$(COV_ARGS) $$(ARGS) $$(TEST_PATH)
endef

$(eval $(call TEST,utest,unit))
$(eval $(call TEST,ftest,functional))
$(eval $(call TEST,atest,acceptance))

.PHONY: test
test: utest ftest atest coverage-combined

.PHONY: coverage-combined
coverage-combined:
	coverage combine --keep .coverage-[u,f,a]test
	coverage report --skip-covered
	coverage $(COV_REPORT)

# }}}

# {{{ setup

# called as `make -f .skel/Makefile setup`

SKEL_DIR = $(dir $(lastword $(MAKEFILE_LIST)))

ifneq ($(SKEL_DIR),./)

SKEL_FILES = $(shell git -C $(SKEL_DIR) ls-files | grep -Ev "README.md|action.yml")

$(SKEL_FILES):
	ln -s $(SKEL_DIR)$@

.PHONY: setup
setup: $(SKEL_FILES)

endif

# }}}
