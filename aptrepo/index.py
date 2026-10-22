"""The Packages index of a flat APT repository stored as GitHub release assets.

Published package versions are immutable: an incoming entry whose package,
version and architecture are already in the index is ignored, so clients never
see the checksum of a published version change.
"""

import functools
import os
import re
from collections import defaultdict
from dataclasses import dataclass

from aptrepo import debversion

_REQUIRED_FIELDS = ("Package", "Version", "Architecture", "Filename")

# GitHub replaces these characters in release asset names with dots.
_UNSAFE_ASSET_CHARS = re.compile(r"[^A-Za-z0-9._-]")


class RepoIndexError(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    package: str
    version: str
    architecture: str
    asset: str
    text: str

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.package, self.version, self.architecture)


@dataclass(frozen=True)
class UpdateResult:
    entries: list[Entry]
    upload: list[str]
    remove: list[str]


def asset_name(path: str) -> str:
    """Return the name GitHub gives to a release asset uploaded from path."""
    return _UNSAFE_ASSET_CHARS.sub(".", os.path.basename(path))


def parse_packages(text: str) -> list[Entry]:
    paragraphs = [p.strip("\n") for p in re.split(r"\n{2,}", text)]
    return [_parse_entry(p + "\n") for p in paragraphs if p]


def format_packages(entries: list[Entry]) -> str:
    return "\n".join(e.text for e in entries)


def update(current: str, incoming: str, keep: int) -> UpdateResult:
    """Merge incoming entries into the current index and keep the newest versions.

    keep is the number of versions kept for each package and architecture.
    """
    if keep < 1:
        raise ValueError("keep must be at least 1")

    current_entries = parse_packages(current)
    incoming_entries = parse_packages(incoming)
    _check_unique_keys(current_entries)
    _check_unique_keys(incoming_entries)

    published = {e.key for e in current_entries}
    added = [e for e in incoming_entries if e.key not in published]
    merged = current_entries + added
    _check_unique_assets(merged)

    kept = _newest(merged, keep)
    kept_keys = {e.key for e in kept}
    added_keys = {e.key for e in added}
    return UpdateResult(
        entries=kept,
        upload=[e.asset for e in kept if e.key in added_keys],
        remove=[e.asset for e in current_entries if e.key not in kept_keys],
    )


def _parse_entry(paragraph: str) -> Entry:
    fields = {}
    for line in paragraph.splitlines():
        if line[:1] in (" ", "\t"):
            continue
        name, sep, value = line.partition(":")
        if not sep:
            raise RepoIndexError(f"malformed line in Packages: {line!r}")
        fields[name] = value.strip()

    missing = [f for f in _REQUIRED_FIELDS if f not in fields]
    if missing:
        raise RepoIndexError(f"Packages entry without {', '.join(missing)}: {paragraph!r}")

    asset = os.path.basename(fields["Filename"])
    if asset != asset_name(asset):
        raise RepoIndexError(f"file name is not a valid release asset name: {asset}")
    debversion.parse(fields["Version"])
    return Entry(
        package=fields["Package"],
        version=fields["Version"],
        architecture=fields["Architecture"],
        asset=asset,
        text=paragraph,
    )


def _check_unique_keys(entries: list[Entry]) -> None:
    seen = set()
    for e in entries:
        if e.key in seen:
            raise RepoIndexError(f"duplicate entry: {e.package} {e.version} {e.architecture}")
        seen.add(e.key)


def _check_unique_assets(entries: list[Entry]) -> None:
    owners = {}
    for e in entries:
        other = owners.setdefault(e.asset, e)
        if other.key != e.key:
            raise RepoIndexError(
                f"{other.package} {other.version} and {e.package} {e.version} "
                f"both use the asset name {e.asset}"
            )


def _newest(entries: list[Entry], keep: int) -> list[Entry]:
    groups = defaultdict(list)
    for e in entries:
        groups[(e.package, e.architecture)].append(e)

    newest_first = functools.cmp_to_key(lambda a, b: debversion.compare(b.version, a.version))
    kept = []
    for group in sorted(groups):
        kept.extend(sorted(groups[group], key=newest_first)[:keep])
    return kept
