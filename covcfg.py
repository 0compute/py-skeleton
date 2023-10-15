#!/usr/bin/env python
from __future__ import annotations

import sys
from pathlib import Path

import deepmerge
import toml
from box import Box

if __name__ == "__main__":
    # used by Makefile: read coverage config from pyproject.toml, merge
    # covcfg-[unit,functional,acceptance].toml on to it, then munge and dump

    pyproject, covcfg = sys.argv[1:]

    coverage = Box(toml.load(pyproject)).tool.coverage
    deepmerge.always_merger.merge(coverage, toml.load(covcfg))

    name = covcfg.split("-")[1].split(".")[0]

    coverage.run.data_file += f"-{name}"

    coverage.html.directory += f"-{name}"
    coverage.html.title = f"{name.capitalize()} Test Coverage Report"

    xml = Path(coverage.xml.output)
    coverage.xml.output = f"{xml.stem}-{name}{xml.suffix}"

    for conf in coverage.values():
        for value in conf.values():
            if isinstance(value, list):
                value.sort()

    toml.dump(dict(tool=dict(coverage=coverage)), sys.stdout)
