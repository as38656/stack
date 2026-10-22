import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from aptrepo.__main__ import main


def stanza(package, version, asset):
    return (
        f"Package: {package}\nVersion: {version}\nArchitecture: amd64\n"
        f"Filename: ./{asset}\n"
    )


class CliTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def test_asset_name(self):
        out = io.StringIO()
        with redirect_stdout(out):
            main(["asset-name", "out/vpp_1.0-1~gabc_amd64.deb", "zebra-rs_1+a_amd64.deb"])
        self.assertEqual(out.getvalue(), "vpp_1.0-1.gabc_amd64.deb\nzebra-rs_1.a_amd64.deb\n")

    def test_update_writes_index_and_asset_lists(self):
        current = self.dir / "current"
        incoming = self.dir / "incoming"
        current.write_text(stanza("vpp", "1.0", "vpp_1.0_amd64.deb"))
        incoming.write_text(stanza("vpp", "2.0", "vpp_2.0_amd64.deb"))

        main([
            "update",
            "--current", str(current),
            "--incoming", str(incoming),
            "--keep", "1",
            "--packages", str(self.dir / "Packages"),
            "--upload", str(self.dir / "upload"),
            "--remove", str(self.dir / "remove"),
        ])

        self.assertEqual(
            (self.dir / "Packages").read_text(),
            stanza("vpp", "2.0", "vpp_2.0_amd64.deb"),
        )
        self.assertEqual((self.dir / "upload").read_text(), "vpp_2.0_amd64.deb\n")
        self.assertEqual((self.dir / "remove").read_text(), "vpp_1.0_amd64.deb\n")

    def test_empty_lists_are_empty_files(self):
        current = self.dir / "current"
        current.write_text(stanza("vpp", "1.0", "vpp_1.0_amd64.deb"))

        main([
            "update",
            "--current", str(current),
            "--incoming", str(current),
            "--keep", "1",
            "--packages", str(self.dir / "Packages"),
            "--upload", str(self.dir / "upload"),
            "--remove", str(self.dir / "remove"),
        ])

        self.assertEqual((self.dir / "upload").read_text(), "")
        self.assertEqual((self.dir / "remove").read_text(), "")


if __name__ == "__main__":
    unittest.main()
