"""Debian package version comparison.

Follows the algorithm in Debian Policy 5.6.12 and dpkg's verrevcmp().
"""

import re
from dataclasses import dataclass

_DIGITS = "0123456789"
_UPSTREAM = re.compile(r"[0-9][A-Za-z0-9.+~-]*")
_REVISION = re.compile(r"[A-Za-z0-9.+~]+")


@dataclass(frozen=True)
class Version:
    epoch: int
    upstream: str
    revision: str


def parse(text: str) -> Version:
    """Split a version string into epoch, upstream version and revision."""
    rest = text
    epoch = 0
    if ":" in rest:
        epoch_text, rest = rest.split(":", 1)
        if not epoch_text.isdigit():
            raise ValueError(f"invalid epoch in version {text!r}")
        epoch = int(epoch_text)

    revision = ""
    if "-" in rest:
        rest, revision = rest.rsplit("-", 1)
        if not _REVISION.fullmatch(revision):
            raise ValueError(f"invalid revision in version {text!r}")

    if not _UPSTREAM.fullmatch(rest):
        raise ValueError(f"invalid upstream version in version {text!r}")
    return Version(epoch, rest, revision)


def compare(a: str, b: str) -> int:
    """Return a negative number, zero or a positive number when a < b, a == b or a > b."""
    va, vb = parse(a), parse(b)
    if va.epoch != vb.epoch:
        return va.epoch - vb.epoch
    return _verrevcmp(va.upstream, vb.upstream) or _verrevcmp(va.revision, vb.revision)


def _order(s: str, i: int) -> int:
    if i >= len(s):
        return 0
    c = s[i]
    if c == "~":
        return -1
    if c in _DIGITS:
        return 0
    if c.isascii() and c.isalpha():
        return ord(c)
    return ord(c) + 256


def _is_digit(s: str, i: int) -> bool:
    return i < len(s) and s[i] in _DIGITS


def _verrevcmp(a: str, b: str) -> int:
    i = j = 0
    while i < len(a) or j < len(b):
        while (i < len(a) and not _is_digit(a, i)) or (j < len(b) and not _is_digit(b, j)):
            diff = _order(a, i) - _order(b, j)
            if diff:
                return diff
            i += 1
            j += 1

        while i < len(a) and a[i] == "0":
            i += 1
        while j < len(b) and b[j] == "0":
            j += 1

        first_diff = 0
        while _is_digit(a, i) and _is_digit(b, j):
            if not first_diff:
                first_diff = ord(a[i]) - ord(b[j])
            i += 1
            j += 1
        if _is_digit(a, i):
            return 1
        if _is_digit(b, j):
            return -1
        if first_diff:
            return first_diff
    return 0
