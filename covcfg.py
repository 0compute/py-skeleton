#!/usr/bin/env python
from __future__ import annotations

import sys
from pathlib import Path

import deepmerge
import toml
from box import Box

if __name__ == "__main__":
    # used by Makefile: read coverage config from pyproject.toml, merge
    # covcfg-[ufpa]test.toml on to it, then munge and dump

    pyproject, covcfg = sys.argv[1:]

    coverage = Box(toml.load(pyproject)).tool.coverage
    deepmerge.always_merger.merge(coverage, toml.load(covcfg))

    name = covcfg.split("-")[1].split(".")[0]
    coverage.html.directory += f"-{name}"
    coverage.run.data_file += f"-{name}"
    xml = Path(coverage.xml.output)
    coverage.xml.output = f"{xml.stem}-{name}{xml.suffix}"

    toml.dump(dict(tool=dict(coverage=coverage)), sys.stdout)
