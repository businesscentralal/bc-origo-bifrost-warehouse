"""Compiler-catalog alias regressions. The app cache stays fail-closed."""
import io
import shutil
import struct
import tempfile
import unittest
import zipfile
from unittest.mock import patch
from pathlib import Path
from xml.etree import ElementTree as ET

from test_ready_to_run import wrap
from test_symbol_policy import G, fixture


def repack(path, extra=(), edit=None):
    """Rewrite a fixture NAVX. Zip metadata may change; entry bytes stay unless edited."""
    data = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(data[40:])) as archive:
        entries = [(name, archive.read(name)) for name in archive.namelist()]
    if edit:
        entries = edit(entries)
    entries.extend(extra)
    payload = io.BytesIO()
    with zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries:
            archive.writestr(name, content)
    header = bytearray(data[:40])
    struct.pack_into("<Q", header, 28, len(payload.getvalue()))
    path.write_bytes(bytes(header) + payload.getvalue())


class CompilerSymbolAliases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.catalog = Path(self.temp.name) / "catalog"
        self.cache = Path(self.temp.name) / "cache"
        self.catalog.mkdir()
        self.cache.mkdir()

    def test_byte_identical_and_same_content_aliases_are_one_package(self):
        identity = fixture(self.catalog / "Microsoft_Library.app")
        shutil.copyfile(self.catalog / "Microsoft_Library.app",
                        self.catalog / "Microsoft_Library_29.0.1.0.app")
        data = (self.catalog / "Microsoft_Library.app").read_bytes()
        (self.catalog / "Microsoft_Library_tail.app").write_bytes(data + b"signature-tail")
        fixture(self.catalog / "Microsoft_Library_repacked.app", identity)
        original = G.package_info(self.catalog / "Microsoft_Library.app")
        tailed = G.package_info(self.catalog / "Microsoft_Library_tail.app")
        self.assertNotEqual(original["sha256"], tailed["sha256"])
        self.assertEqual(original["contentSha256"], tailed["contentSha256"])
        self.assertEqual(original["identity"], tailed["identity"])
        with self.assertRaisesRegex(G.GateError, "Duplicate symbol identity/version"):
            G.symbol_inventory(self.catalog, "compilerCatalog")
        removals = G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertEqual(["Microsoft_Library_29.0.1.0.app"], sorted(p.name for p in self.catalog.glob("*.app")))
        self.assertEqual(3, len(removals))
        self.assertTrue(all(item["retained"] == "Microsoft_Library_29.0.1.0.app" for item in removals))
        self.assertEqual(1, len(G.symbol_inventory(self.catalog, "compilerCatalog")))
        self.assertEqual([], G.collapse_equivalent_compiler_symbols(self.catalog))

    def test_conflicting_content_or_version_fails_without_removing_aliases(self):
        identity = fixture(self.catalog / "A.app")
        shutil.copyfile(self.catalog / "A.app", self.catalog / "A-copy.app")
        other = fixture(self.catalog / "B.app")
        fixture(self.catalog / "B-other.app", other, content=b"conflicting symbols")
        with self.assertRaisesRegex(G.GateError, "conflicting content"):
            G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertEqual(4, len(list(self.catalog.glob("*.app"))))

        for path in self.catalog.glob("*.app"):
            path.unlink()
        identity = fixture(self.catalog / "One.app")
        shutil.copyfile(self.catalog / "One.app", self.catalog / "One-copy.app")
        fixture(self.catalog / "Two.app", dict(identity, version="30.0.0.0"))
        with self.assertRaisesRegex(G.GateError, "conflicting version"):
            G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertTrue((self.catalog / "One-copy.app").is_file())
        self.assertTrue((self.catalog / "Two.app").is_file())

    def test_ready_to_run_and_repacked_symbol_aliases_are_one_package(self):
        identity = fixture(self.catalog / "Microsoft_Library.app")
        plain = (self.catalog / "Microsoft_Library.app").read_bytes()
        wrap(self.catalog / "Microsoft_Library_29.0.1.0.app", plain, identity)
        repack(self.catalog / "Microsoft_Library.app", extra=(("Translation.txt", b"not a compiler input"),))
        original = G.package_info(self.catalog / "Microsoft_Library.app")
        wrapped = G.package_info(self.catalog / "Microsoft_Library_29.0.1.0.app", allow_ready_to_run=True)
        self.assertNotEqual(original["sha256"], wrapped["sha256"])
        self.assertNotEqual(original["contentSha256"], wrapped["contentSha256"])
        self.assertEqual(original["symbolReferenceSha256"], wrapped["symbolReferenceSha256"])
        removals = G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertEqual(["Microsoft_Library_29.0.1.0.app"], sorted(p.name for p in self.catalog.glob("*.app")))
        self.assertEqual(1, len(removals))
        self.assertEqual(original["symbolReferenceSha256"], removals[0]["symbolReferenceSha256"])

    def test_translation_flags_are_not_conflicts_and_other_metadata_is(self):
        identity = fixture(self.catalog / "Microsoft_Library_29.0.1.0.app")
        shutil.copyfile(self.catalog / "Microsoft_Library_29.0.1.0.app", self.catalog / "Microsoft_Library.app")
        namespace = "{http://schemas.microsoft.com/navx/2015/manifest}"

        def add_metadata(flag, timestamp):
            def edit(entries):
                updated = []
                for name, content in entries:
                    if name == "NavxManifest.xml":
                        root = ET.fromstring(content)
                        ET.SubElement(ET.SubElement(root, namespace + "Features"), namespace + "Feature").text = flag
                        ET.SubElement(root, namespace + "Build", {"Timestamp": timestamp})
                        content = ET.tostring(root)
                    updated.append((name, content))
                return updated
            return edit

        repack(self.catalog / "Microsoft_Library.app", edit=add_metadata("LCGTRANSLATIONFILE", "time-one"))
        repack(self.catalog / "Microsoft_Library_29.0.1.0.app", edit=add_metadata("TRANSLATIONFILE", "time-two"))
        removals = G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertEqual(1, len(removals))
        self.assertNotEqual(removals[0]["sha256"], removals[0]["removedSha256"])

        for path in self.catalog.glob("*.app"):
            path.unlink()
        fixture(self.catalog / "Microsoft_Library_29.0.1.0.app", identity)
        fixture(self.catalog / "Microsoft_Library.app", identity)

        def add_runtime(entries):
            updated = []
            for name, content in entries:
                if name == "NavxManifest.xml":
                    root = ET.fromstring(content)
                    root.find(namespace + "App").set("Runtime", "different")
                    content = ET.tostring(root)
                updated.append((name, content))
            return updated

        repack(self.catalog / "Microsoft_Library.app", edit=add_runtime)
        with self.assertRaisesRegex(G.GateError, "compiler manifest"):
            G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertEqual(2, len(list(self.catalog.glob("*.app"))))

    def test_profiled_wrapper_lifts_the_embedded_entry_bound(self):
        inner = self.catalog / "inner-source.app"
        identity = fixture(inner)
        outer = self.catalog / "wrapper.app"
        wrap(outer, inner.read_bytes(), identity)
        profile = {"identity": identity, "maxEntries": 16384, "maxExpandedBytes": 512 * 1024 * 1024}
        with patch.dict(G.MEASURED_PACKAGE_PROFILES, {G.file_hash(outer): profile}), patch.object(G, "PACKAGE_ENTRIES", 1):
            info = G.package_info(outer, allow_ready_to_run=True)
        self.assertEqual(identity, info["identity"])
        self.assertEqual(G.file_hash(inner), info["readyToRun"]["embeddedSha256"])

    def test_catalog_copy_is_not_charged_twice_against_the_cache_expanded_bound(self):
        identity = fixture(self.catalog / "Microsoft_Base Application_28.5.54151.55751.app")
        catalog = G.symbol_inventory(self.catalog, "compilerCatalog")
        shutil.copyfile(self.catalog / "Microsoft_Base Application_28.5.54151.55751.app",
                        self.cache / "Microsoft_Base Application_28.5.54151.55751.app")
        sha = catalog[0]["sha256"]
        real = G.package_info

        def inflate(path, deadline=None, allow_ready_to_run=False, measured_profile=None):
            info = real(path, deadline, allow_ready_to_run=allow_ready_to_run, measured_profile=measured_profile)
            if path.name.startswith("Microsoft_Base Application"):
                info = dict(info, expandedBytes=600 * 1024 * 1024)
            return info

        def inflate_catalog(path, deadline=None, allow_ready_to_run=False, measured_profile=None):
            info = real(path, deadline, allow_ready_to_run=allow_ready_to_run, measured_profile=measured_profile)
            if path.name.startswith("Microsoft_Base Application"):
                info = dict(info, expandedBytes=5 * 1024 * 1024 * 1024)
            return info

        with patch.object(G, "package_info", inflate):
            with self.assertRaisesRegex(G.GateError, "Symbol aggregate expanded-byte bound exceeded"):
                G.symbol_inventory(self.cache)
            self.assertEqual(1, len(G.symbol_inventory(self.cache, expanded_exemptions={sha})))
        with patch.object(G, "package_info", inflate_catalog):
            with self.assertRaisesRegex(G.GateError, "Symbol aggregate expanded-byte bound exceeded"):
                G.symbol_inventory(self.catalog, "compilerCatalog", expanded_exemptions={sha})
        fixture(self.cache / "Local.app")

        def inflate_local(path, deadline=None, allow_ready_to_run=False, measured_profile=None):
            info = real(path, deadline, allow_ready_to_run=allow_ready_to_run, measured_profile=measured_profile)
            if path.name == "Local.app":
                info = dict(info, expandedBytes=600 * 1024 * 1024)
            return info

        with patch.object(G, "package_info", inflate_local):
            with self.assertRaisesRegex(G.GateError, "Symbol aggregate expanded-byte bound exceeded"):
                G.symbol_inventory(self.cache, expanded_exemptions={sha})
        tight = dict(G.SYMBOL_POLICIES["appCache"], bytes=10)
        with patch.dict(G.SYMBOL_POLICIES, {"appCache": tight}):
            with self.assertRaisesRegex(G.GateError, "Symbol aggregate-byte bound exceeded"):
                G.symbol_inventory(self.cache, expanded_exemptions={sha})
        self.assertEqual(identity["id"], catalog[0]["identity"]["id"])

    def test_app_cache_still_rejects_a_byte_identical_duplicate(self):
        fixture(self.cache / "One.app")
        shutil.copyfile(self.cache / "One.app", self.cache / "Two.app")
        with self.assertRaisesRegex(G.GateError, "Duplicate symbol identity/version"):
            G.symbol_inventory(self.cache)
        self.assertEqual(2, len(list(self.cache.glob("*.app"))))


if __name__ == "__main__":
    unittest.main(verbosity=2)
