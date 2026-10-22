import unittest

from aptrepo.index import (
    RepoIndexError,
    asset_name,
    format_packages,
    parse_packages,
    update,
)


def stanza(package, version, arch="amd64", extra=""):
    filename = asset_name(f"{package}_{version}_{arch}.deb")
    return (
        f"Package: {package}\n"
        f"Version: {version}\n"
        f"Architecture: {arch}\n"
        f"Filename: ./{filename}\n"
        f"Size: 1\n"
        f"{extra}"
    )


def index(*stanzas):
    return "\n".join(stanzas)


class AssetNameTest(unittest.TestCase):
    def test_keeps_safe_names(self):
        self.assertEqual(asset_name("vpp_26.06.0_amd64.deb"), "vpp_26.06.0_amd64.deb")

    def test_replaces_unsafe_characters_with_dots(self):
        self.assertEqual(
            asset_name("vpp_26.06.0-4~gf6ae22b_amd64.deb"),
            "vpp_26.06.0-4.gf6ae22b_amd64.deb",
        )
        self.assertEqual(
            asset_name("zebra-rs_26.10.3+as38656.1.gabc_amd64.deb"),
            "zebra-rs_26.10.3.as38656.1.gabc_amd64.deb",
        )

    def test_uses_the_base_name(self):
        self.assertEqual(asset_name("out/trixie/vpp/vpp_1_amd64.deb"), "vpp_1_amd64.deb")


class ParseTest(unittest.TestCase):
    def test_round_trip_keeps_text(self):
        text = index(
            stanza("vpp", "1.0", extra="Description: VPP\n multi line\n .\n end\n"),
            stanza("zebra-rs", "2.0"),
        )
        entries = parse_packages(text)
        self.assertEqual([e.package for e in entries], ["vpp", "zebra-rs"])
        self.assertEqual(entries[0].version, "1.0")
        self.assertEqual(entries[0].architecture, "amd64")
        self.assertEqual(entries[0].asset, "vpp_1.0_amd64.deb")
        self.assertEqual(format_packages(entries), text)

    def test_empty_index(self):
        self.assertEqual(parse_packages(""), [])
        self.assertEqual(format_packages([]), "")

    def test_missing_field_is_an_error(self):
        with self.assertRaises(RepoIndexError):
            parse_packages("Package: vpp\nVersion: 1.0\nArchitecture: amd64\n")


class UpdateTest(unittest.TestCase):
    def test_first_publish(self):
        result = update(current="", incoming=index(stanza("vpp", "1.0")), keep=3)
        self.assertEqual([e.version for e in result.entries], ["1.0"])
        self.assertEqual(result.upload, ["vpp_1.0_amd64.deb"])
        self.assertEqual(result.remove, [])

    def test_adds_new_versions_next_to_old_ones(self):
        result = update(
            current=index(stanza("vpp", "1.0")),
            incoming=index(stanza("vpp", "1.1")),
            keep=3,
        )
        self.assertEqual([e.version for e in result.entries], ["1.1", "1.0"])
        self.assertEqual(result.upload, ["vpp_1.1_amd64.deb"])
        self.assertEqual(result.remove, [])

    def test_published_versions_are_not_replaced(self):
        old = stanza("vpp", "1.0", extra="SHA256: old\n")
        new = stanza("vpp", "1.0", extra="SHA256: new\n")
        result = update(current=index(old), incoming=index(new), keep=3)
        self.assertEqual(format_packages(result.entries), old)
        self.assertEqual(result.upload, [])
        self.assertEqual(result.remove, [])

    def test_prunes_oldest_versions_per_package_and_arch(self):
        current = index(
            stanza("vpp", "26.06.0-4~gaaaaaaa"),
            stanza("vpp", "26.06.0-5~gbbbbbbb"),
            stanza("vpp", "26.06.0-5~gbbbbbbb", arch="arm64"),
            stanza("zebra-rs", "26.10.3+as38656.1.gccc"),
        )
        incoming = index(
            stanza("vpp", "26.06.0-6~gccccccc"),
            stanza("zebra-rs", "26.10.3+as38656.2.gddd"),
        )
        result = update(current=current, incoming=incoming, keep=2)
        self.assertEqual(
            [(e.package, e.architecture, e.version) for e in result.entries],
            [
                ("vpp", "amd64", "26.06.0-6~gccccccc"),
                ("vpp", "amd64", "26.06.0-5~gbbbbbbb"),
                ("vpp", "arm64", "26.06.0-5~gbbbbbbb"),
                ("zebra-rs", "amd64", "26.10.3+as38656.2.gddd"),
                ("zebra-rs", "amd64", "26.10.3+as38656.1.gccc"),
            ],
        )
        self.assertEqual(
            result.upload,
            ["vpp_26.06.0-6.gccccccc_amd64.deb", "zebra-rs_26.10.3.as38656.2.gddd_amd64.deb"],
        )
        self.assertEqual(result.remove, ["vpp_26.06.0-4.gaaaaaaa_amd64.deb"])

    def test_an_old_incoming_version_can_be_pruned_at_once(self):
        result = update(
            current=index(stanza("vpp", "2.0")),
            incoming=index(stanza("vpp", "1.0")),
            keep=1,
        )
        self.assertEqual([e.version for e in result.entries], ["2.0"])
        self.assertEqual(result.upload, [])
        self.assertEqual(result.remove, [])

    def test_keep_must_be_positive(self):
        with self.assertRaises(ValueError):
            update(current="", incoming="", keep=0)

    def test_duplicate_incoming_entries_are_an_error(self):
        with self.assertRaises(RepoIndexError):
            update(
                current="",
                incoming=index(stanza("vpp", "1.0"), stanza("vpp", "1.0")),
                keep=3,
            )

    def test_asset_name_collision_is_an_error(self):
        with self.assertRaises(RepoIndexError):
            update(
                current=index(stanza("vpp", "1.0~a")),
                incoming=index(stanza("vpp", "1.0+a")),
                keep=3,
            )


if __name__ == "__main__":
    unittest.main()
