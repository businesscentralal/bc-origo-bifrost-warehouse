"""Regression fixtures for the independent build input guard."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("guard", Path(__file__).parents[1] / "check_build_inputs.py")
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class BuildInputsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.manifest = {"id": "app-id", "idRanges": [{"from": 100, "to": 199}], "dependencies": []}

    def check(self, *sources):
        (self.root / "app.json").write_text(json.dumps(self.manifest))
        for i, source in enumerate(sources):
            (self.root / f"{i}.al").write_text(source)
        return GUARD.check_project(self.root)

    def test_clean_per_type_allocation_and_enum_boundaries(self):
        self.assertEqual([], self.check('table 100 "A" {}', 'codeunit 100 "B" {}',
                                       'enumextension 199 "E" extends "Base" { value(100; First) {} value(199; Last) {} }'))

    def test_duplicate_codeunit_is_rejected_without_any_symbol_package(self):
        self.assertTrue(any("duplicate codeunit 121" in x for x in self.check('codeunit 121 A {}', 'codeunit 121 B {}')))

    def test_duplicate_enum_ordinal_across_extensions_is_rejected(self):
        self.assertTrue(any("duplicate enum value base/119" in x for x in self.check(
            'enumextension 101 A extends "Base" { value(119; First) {} }',
            'enumextension 102 B extends "Base" { value(119; Second) {} }')))

    def test_same_ordinal_on_unrelated_enums_is_valid(self):
        self.assertEqual([], self.check('enumextension 101 A extends BaseA { value(119; First) {} }',
                                       'enumextension 102 B extends BaseB { value(119; Second) {} }'))

    def test_unallocated_object_and_enum_value_are_rejected(self):
        errors = self.check('codeunit 200 A {}', 'enumextension 101 B extends Base { value(99; First) {} }')
        self.assertEqual(2, len(errors))

    def test_comments_strings_and_quoted_identifiers_do_not_create_objects(self):
        self.assertEqual([], self.check('codeunit 100 "enum" { procedure P() begin Message(\'codeunit 100 X {}\'); end; } // codeunit 100 A {}\n/* codeunit 100 B {} */'))

    def test_self_dependency_is_rejected(self):
        self.manifest["dependencies"] = [{"id": "APP-ID"}]
        self.assertEqual(["manifest declares its own app as a dependency"], self.check())

    def test_foundation_floor_and_identity_are_checked(self):
        self.manifest["dependencies"] = [{"id": GUARD.FOUNDATION_ID, "name": "Bifrost Foundation", "publisher": "Origo", "version": "28.0.3.529"}]
        self.assertEqual(["Foundation dependency is below 28.0.3.530"], self.check())
        self.manifest["dependencies"][0]["version"] = "28.0.3.530"
        self.assertEqual([], self.check())
        self.manifest["dependencies"][0]["name"] = "Wrong App"
        self.assertEqual(["Foundation dependency identity does not match its AppId"], self.check())


if __name__ == "__main__":
    unittest.main()
