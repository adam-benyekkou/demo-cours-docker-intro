#!/usr/bin/env python3
"""Parse every YAML file of the repository with the Compose tag extensions.

`docker compose config` validates the compose files, but not the workflows nor
cloud-init. PyYAML rejects `!override` / `!reset`, hence the custom loader: it
keeps the tagged node as plain data, the goal here is syntax only.
"""

from __future__ import annotations

import glob
import sys

import yaml


class ComposeLoader(yaml.SafeLoader):
    pass


def any_tag(loader: ComposeLoader, suffix: str, node: yaml.Node) -> object:
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    return loader.construct_scalar(node)


ComposeLoader.add_multi_constructor("!", any_tag)

PATTERNS = (
    "stack/**/*.yml",
    ".github/workflows/*.yml",
    ".github/*.yml",
    "infra/cloud-init.yml",
    ".trivyignore.yaml",
)


def main() -> int:
    paths = sorted({p for pattern in PATTERNS for p in glob.glob(pattern, recursive=True)})
    bad = 0
    for path in paths:
        try:
            with open(path, encoding="utf-8") as handle:
                list(yaml.load_all(handle, Loader=ComposeLoader))
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"{path}: {exc}")
            bad = 1
    print(f"yaml: {len(paths)} file(s) parsed, {bad} error(s)")
    return bad


if __name__ == "__main__":
    sys.exit(main())
