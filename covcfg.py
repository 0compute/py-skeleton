#!/usr/bin/env python
from __future__ import annotations

import sys
from pathlib import Path

import deepmerge
import toml
from box import Box

if __name__ == "__main__":
    # read coverage config from pyproject.toml
    # merge covcfg.toml on to it if extant
    # munge and dump

    # 1st arg is pyproject.toml, 2nd is either a path to covcfg or a name
    pyproject, covcfg = sys.argv[1:3]

    coverage = Box(toml.load(pyproject)).tool.coverage

    if (covcfg_path := Path(covcfg)).exists():
        deepmerge.always_merger.merge(coverage, toml.load(covcfg))
        name = covcfg_path.parent.name
    else:
        name = covcfg

    coverage.run.data_file += f"-{name}"

    coverage.html.directory += f"-{name}"
    coverage.html.title = f"{name.capitalize()} Test Coverage Report"

    xml = Path(coverage.xml.output)
    coverage.xml.output = f"{xml.parent}/{xml.stem}-{name}{xml.suffix}"

    for conf in coverage.values():
        for value in conf.values():
            if isinstance(value, list):
                value.sort()

    toml.dump(dict(tool=dict(coverage=coverage)), sys.stdout)
