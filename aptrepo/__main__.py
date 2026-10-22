"""Command line interface for the flat APT repository helpers.

  python3 -m aptrepo asset-name PATH...
  python3 -m aptrepo update --current FILE --incoming FILE --keep N
                            --packages FILE --upload FILE --remove FILE
"""

import argparse
import sys
from pathlib import Path

from aptrepo.index import asset_name, format_packages, update


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(prog="aptrepo")
    commands = parser.add_subparsers(dest="command", required=True)

    names = commands.add_parser("asset-name", help="print the release asset name of each file")
    names.add_argument("paths", nargs="+")

    upd = commands.add_parser("update", help="merge new packages into the Packages index")
    upd.add_argument("--current", type=Path, required=True, help="Packages index now published")
    upd.add_argument("--incoming", type=Path, required=True, help="Packages index of new files")
    upd.add_argument("--keep", type=int, required=True, help="versions kept per package and arch")
    upd.add_argument("--packages", type=Path, required=True, help="output: new Packages index")
    upd.add_argument("--upload", type=Path, required=True, help="output: assets to upload")
    upd.add_argument("--remove", type=Path, required=True, help="output: assets to delete")

    args = parser.parse_args(argv)
    if args.command == "asset-name":
        for path in args.paths:
            print(asset_name(path))
    elif args.command == "update":
        result = update(args.current.read_text(), args.incoming.read_text(), args.keep)
        args.packages.write_text(format_packages(result.entries))
        args.upload.write_text("".join(f"{name}\n" for name in result.upload))
        args.remove.write_text("".join(f"{name}\n" for name in result.remove))


if __name__ == "__main__":
    main(sys.argv[1:])
