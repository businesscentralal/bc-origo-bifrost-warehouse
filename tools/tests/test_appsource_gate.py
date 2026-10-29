"""Gate regressions: fixture results never certify product/analyzers/signature trust."""

import copy
import importlib.util
import io
import json
import os
import shutil
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("appsource_gate", Path(__file__).parents[1] / "appsource_gate.py")
G = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(G)


def log(project="Gate Fixture ori", count=1):
    return ("Microsoft (R) AL Compiler version 30.0.42.60748\n"
            f"Compilation started for project '{project}' containing '{count}' files at '09:50:29.018'.\n"
            "Compilation ended at '09:50:30.981'.\n")


def params():
    # Explicit unit fixture for the collector contract, not analyzer invocation proof.
    return dict(enableCodeCop=True, enableUICop=True, enableAppSourceCop=True, failOn="warning",
                escapeFromCops=False, workspaceCompilation=False, rulesetValidated=True,
                compilerVersion="30.0.42.60748", tools={n: {"sha256": "a" * 64} for n in
                ("compiler", "CodeCop", "UICop", "AppSourceCop", "Analyzers.Common", "helper", "alpacaOverride")})


class Logs(unittest.TestCase):
    def test_actual_failed_ci_format_is_rejected(self):
        path = Path(__file__).parents[1] / "fixtures/AppSourceGate/failed-main-output.json"
        fixture = json.loads(path.read_text())
        self.assertEqual("b42ad90eaee2803205408a1cac8b0d9752b91c0e", fixture["sourceSha"])
        self.assertTrue(any("AL0659" in line for line in fixture["lines"]))
        with self.assertRaises(G.GateError):
            G.compile_spans("\n".join(fixture["lines"]))

    def test_clean_default_and_test(self):
        self.assertEqual(1, len(G.compile_spans(log())))
        self.assertEqual(2, len(G.compile_spans(log() + log("Bifrost Warehouse - Tests"))))

    def test_all_old_missing_and_incomplete_cases(self):
        lines = log().splitlines(True)
        for value in ("", "".join(lines[:2]), log() + "".join(lines[:2]), lines[2], "".join(lines[1:]), log(count=0)):
            with self.subTest(value=value), self.assertRaises(G.GateError):
                G.compile_spans(value)

    def test_raw_actions_rendered_and_vso_diagnostics(self):
        for line in ("app/Foo.al(12,4): warning AA0021: unused", "warning AL0659: too long",
                     "error AL0185: missing", "::warning file=Foo.al::AA0021 unused", "::Error::failed",
                     "##[warning]AL0659 identifier", "##[error]failed",
                     "##vso[task.logissue type=warning;code=AA0021;]unused",
                     "##vso[task.logissue type=error;code=AL0185;]missing",
                     "##vso[task.complete result=Failed;]Failed.",
                     "App generation failed with exit code 1", "Retrying without Cops"):
            with self.subTest(line=line), self.assertRaises(G.GateError):
                G.compile_spans(log() + line)

    def test_ansi_actions_timestamps_bom_utf16(self):
        text = "\n".join("2026-10-07T09:50:29.0000000Z \x1b[33m" + line + "\x1b[0m" for line in log().splitlines())
        self.assertEqual(1, len(G.compile_spans(G.read_log(text.encode("utf-8-sig")))))
        self.assertEqual(1, len(G.compile_spans(G.read_log(text.encode("utf-16")))))
        with self.assertRaises(G.GateError):
            G.read_log(b"\x80")

    def test_unpaired_banner_nested_start_and_translation_only_are_not_final_evidence(self):
        lines = log().splitlines(True)
        for text in (lines[0] + log(), log() + lines[0], "".join(lines[:2]) + log()):
            with self.subTest(text=text), self.assertRaises(G.GateError):
                G.compile_spans(text)
        self.assertEqual("Translation fixture", G.compile_spans(log("Translation fixture"))[-1]["project"])


class Parameters(unittest.TestCase):
    def test_committed_settings_and_supported_hook_entrypoints(self):
        root = Path(__file__).parents[2]
        settings = json.loads((root / ".AL-Go/settings.json").read_text())
        foundation_probing = settings["appDependencyProbingPaths"]
        self.assertEqual(1, len(foundation_probing))
        self.assertEqual("https://github.com/OrigoSoftwareSolutions/bc-origo-bifrost-core", foundation_probing[0]["repo"])
        self.assertEqual("release", foundation_probing[0]["release_status"])
        self.assertEqual("28.0.3", foundation_probing[0]["version"])
        for key in ("enableCodeCop", "enableUICop", "enableCodeAnalyzersOnTestApps"):
            self.assertIs(True, settings[key])
        self.assertEqual("warning", settings["failOn"])
        for key in ("enableCodeCopForTestApps", "enableUICopForTestApps", "enableAppSourceCopForTestApps"):
            self.assertIs(True, settings["alpaca"][key])
        self.assertIn(".AL-Go/**", settings["fullBuildPatterns"])
        self.assertIn("tools/**", settings["fullBuildPatterns"])
        for file in ("PipelineInitialize.ps1", "CompileAppWithBcCompilerFolder.ps1", "PostCompileApp.ps1", "PipelineFinalize.ps1"):
            self.assertTrue((root / ".AL-Go" / file).is_file())
        initialize = (root / ".AL-Go/PipelineInitialize.ps1").read_text()
        self.assertIn("Set-AppSourceCompilerCallback", initialize)
        self.assertIn("-Name 'CompileAppWithBcCompilerFolder' -Value $callback -Scope 2", initialize)

    def test_final_intended_settings(self):
        G.validate_parameters(params())

    def test_missing_disabled_string_cop_fallback_warning_and_ruleset(self):
        for key, value in [("enableCodeCop", False), ("enableUICop", "true"), ("enableAppSourceCop", None),
                           ("failOn", "error"), ("escapeFromCops", True), ("workspaceCompilation", True),
                           ("rulesetValidated", False), ("compilerVersion", "")]:
            p = params()
            p[key] = value
            with self.subTest(key=key), self.assertRaises(G.GateError):
                G.validate_parameters(p)
        for name in params()["tools"]:
            p = params()
            del p["tools"][name]
            with self.subTest(name=name), self.assertRaises(G.GateError):
                G.validate_parameters(p)


class GenuinePackages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Missing real fixtures is a FAILURE, never a skipped/passing test.
        cls.fixtures = Path(os.environ["APPSOURCE_GATE_FIXTURES"])
        cls.foundation = Path(os.environ["APPSOURCE_GATE_FOUNDATION"])
        cls.foundation_candidate = Path(os.environ["APPSOURCE_GATE_FOUNDATION632"])
        G.check_foundation_candidate(G.package_info(cls.foundation_candidate))
        for name in ("default", "friend", "wrongFriend", "testApp"):
            G.package_info(cls.fixtures / (name + ".app"))
        cls.default = G.package_info(cls.fixtures / "default.app")
        cls.friend = {"id": "6ae41d19-d457-4d62-bd87-0413ff18de75", "name": "Bifrost Warehouse - Tests", "publisher": "Origo"}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_real_unsigned_and_approved_signed_foundation_navx(self):
        self.assertEqual(0, self.default["signatureTailBytes"])
        info = G.package_info(self.foundation)
        self.assertEqual("5901bebe66b44e91ed6110620e62ee45d122ba9e0378dcfda4aeef4d00d3ae0f", info["sha256"])
        self.assertEqual("336b91d9fff11b71ae5cd75dee08186d4218bf07", info["sourceCommit"])
        self.assertEqual([], info["friends"])
        self.assertGreater(info["signatureTailBytes"], 0)  # Presence only, no trust pass.

    def test_genuine_default_and_test_friend_policy(self):
        expected = self.default["identity"]
        G.check_package(self.default, expected, "Default", "app", self.friend)
        friend = G.package_info(self.fixtures / "friend.app")
        G.check_package(friend, expected, "Test", "app", self.friend)
        test_app = G.package_info(self.fixtures / "testApp.app")
        G.check_package(test_app, test_app["identity"], "Test", "testApp", self.friend)

    def test_surviving_missing_wrong_friend_and_wrong_identity(self):
        for name, mode in (("friend", "Default"), ("default", "Test"), ("wrongFriend", "Test")):
            with self.subTest(name=name), self.assertRaises(G.GateError):
                G.check_package(G.package_info(self.fixtures / (name + ".app")), self.default["identity"], mode, "app", self.friend)
        expected = {**self.default["identity"], "version": "2.0.0.0"}
        with self.assertRaises(G.GateError):
            G.check_package(self.default, expected, "Default", "app", self.friend)
        with self.assertRaises(G.GateError):
            G.check_package(self.default, self.default["identity"], "Default", "app", self.friend, "2" * 40)

    def test_missing_empty_fake_zip_header_and_truncation(self):
        data = (self.fixtures / "default.app").read_bytes()
        for index, value in enumerate((b"", b"not NAVX" + data[40:], b"NAVX" + b"\0" * 36 + data[40:], data[:-30])):
            path = self.root / f"bad{index}.app"
            path.write_bytes(value)
            with self.subTest(index=index), self.assertRaises(G.GateError):
                G.package_info(path)
        with self.assertRaises(G.GateError):
            G.package_info(self.root / "absent.app")

    def test_header_version_size_and_crc_corruption(self):
        original = (self.fixtures / "default.app").read_bytes()
        values = []
        for offset, value in ((4, 41), (8, 3), (28, 0), (28, 2 ** 31)):
            data = bytearray(original)
            struct.pack_into("<I", data, offset, value)
            values.append(data)
        # Corrupt compressed payload, retaining header and central directory.
        data = bytearray(original)
        data[90] ^= 0xff
        values.append(data)
        for index, data in enumerate(values):
            path = self.root / f"corrupt{index}.app"
            path.write_bytes(data)
            with self.subTest(index=index), self.assertRaises((G.GateError, zipfile.BadZipFile)):
                G.package_info(path)

    def malformed(self, change):
        data = (self.fixtures / "default.app").read_bytes()
        archive = zipfile.ZipFile(io.BytesIO(data))
        entries = [(entry.filename, archive.read(entry)) for entry in archive.infolist()]
        entries = change(entries)
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as changed:
            for name, content in entries:
                if name in changed.namelist():
                    with self.assertWarns(UserWarning):
                        changed.writestr(name, content)
                else:
                    changed.writestr(name, content)
        header = bytearray(data[:40])
        struct.pack_into("<Q", header, 28, len(output.getvalue()))
        path = self.root / "malformed.app"
        path.write_bytes(header + output.getvalue())
        return path

    def test_missing_duplicate_malformed_and_unsafe_manifest(self):
        changes = [lambda entries: [(n, b) for n, b in entries if n != "NavxManifest.xml"],
                   lambda entries: entries + [next(e for e in entries if e[0] == "NavxManifest.xml")],
                   lambda entries: [(n, b"<Package" if n == "NavxManifest.xml" else b) for n, b in entries],
                   lambda entries: [(n, b"<!DOCTYPE x>" + b if n == "NavxManifest.xml" else b) for n, b in entries]]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(G.GateError):
                G.package_info(self.malformed(change))

    def test_duplicate_manifest_app_identity_is_rejected(self):
        def change(entries):
            import re
            output = []
            for name, content in entries:
                if name == "NavxManifest.xml":
                    app = re.search(rb"<App\s.*?/>", content, re.S).group(0)
                    content = content.replace(app, app + app)
                output.append((name, content))
            return output
        with self.assertRaises(G.GateError):
            G.package_info(self.malformed(change))

    def state(self, mode="Default"):
        context = dict(run="fixture", attempt="1", job="unit-fixture", sourceCommit="1" * 40,
                       checkoutSha="1" * 40, mode=mode, project=".", buildUrl="https://example.invalid/tooling-fixture")
        self.context = context
        directory = self.root / ".buildartifacts/AppSourceGate" / mode
        directory.mkdir(parents=True)
        state = dict(context=context, startedNs=0, logBytes=0, logPrefixSha256=G.digest(b""), receipts={}, hookHashes={})
        (directory / "state.json").write_text(json.dumps(state))
        for name in ("app", "test"):
            (self.root / name).mkdir()
        (self.root / "app/app.json").write_text(json.dumps(self.default["identity"]))
        (self.root / "test/app.json").write_text(json.dumps({**self.friend, "version": "1.0.0.0"}))
        (self.root / "app/Fixture.al").write_text("fixture source for collector contract unit test")
        (self.root / "test/Fixture.al").write_text("fixture test source for collector contract unit test")
        symbols = self.root / "symbols"
        symbols.mkdir()
        (self.root / 'compiler-symbols').mkdir()
        shutil.copy2(self.foundation_candidate, symbols / "Foundation.app")
        (self.root / "BuildOutput.txt").write_text(log())
        return context

    def request(self, context, name="default", app_type="app"):
        path = self.fixtures / (name + ".app")
        source = "app/Fixture.al" if app_type == "app" else "test/Fixture.al"
        directory = self.root / ".buildartifacts/AppSourceGate" / self.context["mode"]
        (self.root / "symbols/HelperOutput.app").unlink(missing_ok=True)
        G.before_compile(self.root, dict(context=self.context, kind="final", symbolsFolder=str(self.root / "symbols"),
                         compilerSymbolsFolder=str(self.root / "compiler-symbols"),
                         manifest=str(self.root / ("app/app.json" if app_type == "app" else "test/app.json"))))
        shutil.copy2(path, self.root / "symbols/HelperOutput.app")
        (directory / "current-compile.txt").write_text(log(self.default["identity"]["name"] if app_type == "app" else self.friend["name"]))
        return dict(context=context, appType=app_type, appFile=str(path), symbolsFolder=str(self.root / "symbols"),
                    compilerSymbolsFolder=str(self.root / "compiler-symbols"),
                    parameters=params(), sourceFiles=[{"file": source, "sha256": G.file_hash(self.root / source)}])

    def outputs(self, context, name="default", app_type="app"):
        folder = self.root / ".buildartifacts" / ("Apps" if app_type == "app" else "TestApps")
        folder.mkdir(exist_ok=True)
        shutil.copy2(self.fixtures / (name + ".app"), folder / (name + ".app"))

    def test_genuine_package_default_receipt_finalize_and_pipeline(self):
        context = self.state()
        G.post_compile(self.root, self.request(context))
        self.outputs(context)
        G.reconcile(self.root, context, "finalize")
        G.reconcile(self.root, context, "pipeline")

    def test_genuine_test_receipts_require_exact_built_product(self):
        context = self.state("Test")
        G.post_compile(self.root, self.request(context, "friend"))
        shutil.copy2(self.fixtures / "friend.app", self.root / "symbols/Product.app")
        with (self.root / "BuildOutput.txt").open("a") as output:
            output.write(log(self.friend["name"]))
        G.post_compile(self.root, self.request(context, "testApp", "testApp"))
        self.outputs(context, "friend")
        self.outputs(context, "testApp", "testApp")
        G.reconcile(self.root, context, "finalize")

    def test_wrong_run_sha_attempt_mode_and_duplicate_receipts(self):
        context = self.state()
        for key in ("run", "sourceCommit", "checkoutSha", "attempt", "job", "mode"):
            changed = {**context, key: "wrong"}
            with self.subTest(key=key), self.assertRaises((G.GateError, FileNotFoundError)):
                G.post_compile(self.root, self.request(changed))
        G.post_compile(self.root, self.request(context))
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, self.request(context))

    def test_missing_output_test_hook_finalize_and_later_truncation(self):
        context = self.state()
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "finalize")
        G.post_compile(self.root, self.request(context))
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "finalize")
        self.outputs(context)
        with self.assertRaises(FileNotFoundError):
            G.reconcile(self.root, context, "pipeline")
        G.reconcile(self.root, context, "finalize")
        with (self.root / "BuildOutput.txt").open("a") as output:
            output.write(log().split("Compilation ended")[0])
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "pipeline")

    def test_translation_only_wrong_project_zero_source_and_missing_output(self):
        context = self.state()
        for text in (log("Translation fixture"), log(count=0), ""):
            (self.root / "BuildOutput.txt").write_text(text)
            with self.subTest(text=text), self.assertRaises(G.GateError):
                G.post_compile(self.root, self.request(context))
        (self.root / "BuildOutput.txt").write_text(log())
        request = self.request(context)
        request["appFile"] = str(self.root / "missing.app")
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)

    def test_source_only_stripping_and_stale_package_do_not_pass(self):
        context = self.state()
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, self.request(context, "friend"))
        path = self.root / ".buildartifacts/AppSourceGate/Default/state.json"
        state = json.loads(path.read_text())
        state["startedNs"] = 2 ** 63 - 1
        path.write_text(json.dumps(state))
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, self.request(context))

    def test_product_self_symbols_and_wrong_foundation_input(self):
        context = self.state()
        shutil.copy2(self.fixtures / "default.app", self.root / "symbols/Self.app")
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, self.request(context))
        (self.root / "symbols/Self.app").unlink()
        (self.root / "symbols/Foundation.app").unlink()
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, self.request(context))

    def test_precompile_snapshot_then_helper_copy_is_valid_not_a_self_input(self):
        context = self.state()
        request = self.request(context)
        (self.root / 'symbols/HelperOutput.app').unlink()
        shutil.copy2(self.fixtures / "default.app", self.root / "symbols/ProductJustBuilt.app")
        G.post_compile(self.root, request)

    def test_translation_snapshot_missing_isolated_output_and_wrong_test_product(self):
        context = self.state("Test")
        request = self.request(context, "friend")
        directory = self.root / ".buildartifacts/AppSourceGate/Test"
        snapshot = json.loads((directory / "before.json").read_text())
        snapshot["kind"] = "translation"
        (directory / "before.json").write_text(json.dumps(snapshot))
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)
        request = self.request(context, "friend")
        (directory / "current-compile.txt").write_text("")
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)
        request = self.request(context, "friend")
        G.post_compile(self.root, request)
        shutil.copy2(self.fixtures / "default.app", self.root / "symbols/WrongProduct.app")
        with self.assertRaises(G.GateError):
            self.request(context, "testApp", "testApp")

    def test_missing_test_receipt_blocks_finalize(self):
        context = self.state("Test")
        G.post_compile(self.root, self.request(context, "friend"))
        self.outputs(context, "friend")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "finalize")

    def test_output_changed_and_displaced_hook_block_finalize(self):
        context = self.state()
        G.post_compile(self.root, self.request(context))
        self.outputs(context)
        output = self.root / ".buildartifacts/Apps/default.app"
        shutil.copy2(self.fixtures / "friend.app", output)
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "finalize")
        shutil.copy2(self.fixtures / "default.app", output)
        hook = self.root / "Hook.ps1"
        hook.write_text("original hook fixture")
        path = self.root / ".buildartifacts/AppSourceGate/Default/state.json"
        state = json.loads(path.read_text())
        state["hookHashes"] = {"Hook.ps1": G.file_hash(hook)}
        path.write_text(json.dumps(state))
        hook.write_text("displaced hook fixture")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "finalize")

    def test_prefix_replacement_source_count_and_missing_compiler_log(self):
        context = self.state()
        request = self.request(context)
        request["sourceFiles"] = []
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)
        request = self.request(context)
        path = self.root / ".buildartifacts/AppSourceGate/Default/state.json"
        state = json.loads(path.read_text())
        state["logBytes"] = 1
        state["logPrefixSha256"] = G.digest(b"X")
        path.write_text(json.dumps(state))
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)
        (self.root / "BuildOutput.txt").unlink()
        with self.assertRaises(FileNotFoundError):
            G.post_compile(self.root, request)

    def test_missing_stale_precompile_and_missing_compiler_identity(self):
        context = self.state()
        request = self.request(context)
        path = self.root / ".buildartifacts/AppSourceGate/Default/before.json"
        snapshot = json.loads(path.read_text())
        snapshot["context"]["attempt"] = "old"
        path.write_text(json.dumps(snapshot))
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            G.post_compile(self.root, request)
        request = self.request(context)
        request["parameters"]["compilerVersion"] = "18.0.43.2697"
        with self.assertRaises(G.GateError):
            G.post_compile(self.root, request)

    def test_changed_source_output_hook_and_unverified_signature_rejected(self):
        context = self.state()
        G.post_compile(self.root, self.request(context))
        self.outputs(context)
        G.reconcile(self.root, context, "finalize")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "signed")  # No synthetic positive trust verdict.
        (self.root / "app/Fixture.al").write_text("changed source")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "pipeline")

    def test_signed_tail_is_not_a_signature_provider_or_trust_pass(self):
        context = self.state()
        G.post_compile(self.root, self.request(context))
        self.outputs(context)
        G.reconcile(self.root, context, "finalize")
        path = self.root / ".buildartifacts/Apps/default.app"
        with path.open("ab") as output:
            output.write(b"NOT A SIGNATURE")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "pipeline")
        with self.assertRaises(G.GateError):
            G.reconcile(self.root, context, "signed", {"status": "NotSigned"})

    def test_fresh_cache_helper_preparation_addition_and_output_delta(self):
        context = self.state()
        shutil.copy2(self.fixtures / 'testApp.app', self.root / 'compiler-symbols/Transitive.app')
        manifest_path = self.root / "app/app.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["dependencies"] = [G.package_info(self.fixtures / "testApp.app")["identity"]]
        manifest_path.write_text(json.dumps(manifest))
        request = self.request(context)
        shutil.copy2(self.root / 'compiler-symbols/Transitive.app', self.root / 'symbols/Transitive.app')
        receipt = G.post_compile(self.root, request)
        boundaries = receipt['symbolBoundaries']
        self.assertEqual(['Transitive.app'], [s['file'] for s in boundaries['preparationAdditions']])
        self.assertEqual(G.file_hash(self.fixtures / 'default.app'), boundaries['outputCopy']['sha256'])
        self.assertFalse(boundaries['consumedInputsCertified'])

    def test_changed_foundation_or_preexisting_dependency_refused(self):
        for name, original, replacement in [('Foundation.app', self.foundation_candidate, self.fixtures / 'testApp.app'),
                                             ('Dependency.app', self.fixtures / 'testApp.app', self.fixtures / 'wrongFriend.app')]:
            with self.subTest(name=name):
                context = self.state() if not hasattr(self, 'context') else self.context
                shutil.copy2(original, self.root / 'symbols' / name)
                request = self.request(context)
                shutil.copy2(replacement, self.root / 'symbols' / name)
                with self.assertRaises(G.GateError):
                    G.post_compile(self.root, request)
                shutil.copy2(original, self.root / 'symbols' / name)

    def test_changed_compiler_folder_or_unattributed_addition_refused(self):
        context = self.state()
        request = self.request(context)
        shutil.copy2(self.fixtures / 'testApp.app', self.root / 'compiler-symbols/Later.app')
        with self.assertRaisesRegex(G.GateError, 'Compiler-folder inputs changed'):
            G.post_compile(self.root, request)
        (self.root / 'compiler-symbols/Later.app').unlink()
        shutil.copy2(self.fixtures / 'testApp.app', self.root / 'symbols/Unattributed.app')
        with self.assertRaisesRegex(G.GateError, 'Unattributed'):
            G.post_compile(self.root, request)

    def test_missing_changed_or_duplicate_output_copy_refused(self):
        context = self.state()
        request = self.request(context)
        output = self.root / 'symbols/HelperOutput.app'
        output.unlink()
        with self.assertRaisesRegex(G.GateError, 'output-copy'):
            G.post_compile(self.root, request)
        shutil.copy2(self.fixtures / 'wrongFriend.app', output)
        with self.assertRaisesRegex(G.GateError, 'self/output'):
            G.post_compile(self.root, request)
        shutil.copy2(self.fixtures / 'default.app', output)
        shutil.copy2(output, self.root / 'symbols/Duplicate.app')
        with self.assertRaisesRegex(G.GateError, 'Duplicate symbol'):
            G.post_compile(self.root, request)

    def test_wrong_compiler_foundation_self_input_and_missing_boundary_refused(self):
        context = self.state()
        shutil.copy2(self.fixtures / 'default.app', self.root / 'compiler-symbols/Self.app')
        with self.assertRaisesRegex(G.GateError, 'self-app'):
            self.request(context)
        (self.root / 'compiler-symbols/Self.app').unlink()
        request = self.request(context)
        del request['compilerSymbolsFolder']
        with self.assertRaises(KeyError):
            G.post_compile(self.root, request)

    def test_cache_path_substitution_and_translation_snapshot_refused(self):
        context = self.state()
        request = self.request(context)
        request['symbolsFolder'] = str(self.root / 'compiler-symbols')
        with self.assertRaisesRegex(G.GateError, 'Changed symbol cache path'):
            G.post_compile(self.root, request)

    def rejection_request(self):
        return dict(context=self.context, kind="final", manifest=str(self.root / "app/app.json"),
                    symbolsFolder=str(self.root / "symbols"),
                    compilerSymbolsFolder=str(self.root / "compiler-symbols"))

    def rejection_receipt(self):
        return json.loads((self.root / ".buildartifacts/AppSourceGate/Default/rejected-input.json").read_text())

    def test_compiler_rejection_records_actual_offending_bytes(self):
        self.state()
        bad = self.root / "compiler-symbols/Malformed.app"
        bad.write_bytes(b"malformed compiler bytes")
        with self.assertRaisesRegex(G.GateError, "Invalid NAVX header"):
            G.before_compile(self.root, self.rejection_request())
        receipt = self.rejection_receipt()
        item = next(i for i in receipt["inputs"] if i["path"] == str(bad))
        self.assertEqual("compilerSymbolsFolder", item["sourceFolder"])
        self.assertEqual(G.file_hash(bad), item["sha256"])
        self.assertEqual(bad.stat().st_size, item["bytes"])
        self.assertFalse(item["manifestValid"])
        self.assertFalse(receipt["accepted"])
        self.assertFalse(receipt["consumedInputsCertified"])
        self.assertFalse(receipt["truncated"])

    def test_cache_rejection_and_wrong_compiler_foundation_are_attributed(self):
        self.state()
        bad = self.root / "symbols/Bad.app"
        bad.write_bytes(b"bad cache")
        with self.assertRaisesRegex(G.GateError, "Invalid NAVX header"):
            G.before_compile(self.root, self.rejection_request())
        item = next(i for i in self.rejection_receipt()["inputs"] if i["path"] == str(bad))
        self.assertEqual("symbolsFolder", item["sourceFolder"])
        self.assertEqual(G.file_hash(bad), item["sha256"])
        bad.unlink()
        bad = self.root / "compiler-symbols/Foundation.app"
        shutil.copy2(self.foundation, bad)
        with bad.open("ab") as output:
            output.write(b"changed tail")
        with self.assertRaisesRegex(G.GateError, "Unapproved compiler-folder Foundation bytes"):
            G.before_compile(self.root, self.rejection_request())
        item = next(i for i in self.rejection_receipt()["inputs"] if i["path"] == str(bad))
        self.assertEqual("compilerSymbolsFolder", item["sourceFolder"])
        self.assertEqual(G.file_hash(bad), item["sha256"])

    def test_missing_compiler_folder_retains_original_refusal_and_folder_evidence(self):
        self.state()
        (self.root / "compiler-symbols").rmdir()
        with self.assertRaisesRegex(G.GateError, "Actual symbol folder absent"):
            G.before_compile(self.root, self.rejection_request())
        folder = next(i for i in self.rejection_receipt()["folders"]
                      if i["sourceFolder"] == "compilerSymbolsFolder")
        self.assertFalse(folder["present"])
        self.assertEqual(1, len(self.rejection_receipt()["inputs"]))

    def test_rejection_count_and_byte_bounds_report_truncation(self):
        self.state()
        folder = self.root / "compiler-symbols"
        for index in range(257):
            (folder / f"{index:03}.app").write_bytes(b"bad")
        with self.assertRaisesRegex(G.GateError, "256 packages"):
            G.before_compile(self.root, self.rejection_request())
        receipt = self.rejection_receipt()
        self.assertEqual(128, len(receipt["inputs"]))
        self.assertTrue(receipt["truncated"])
        for path in folder.glob("*.app"):
            path.unlink()
        oversized = folder / "Oversized.app"
        with oversized.open("wb") as output:
            output.truncate(128 * 1024 * 1024 + 1)
        with self.assertRaisesRegex(G.GateError, "128 MiB"):
            G.before_compile(self.root, self.rejection_request())
        receipt = self.rejection_receipt()
        item = next(i for i in receipt["inputs"] if i["path"] == str(oversized))
        self.assertTrue(item["truncated"])
        self.assertEqual(128 * 1024 * 1024 + 1, item["bytes"])
        self.assertNotIn("sha256", item)
        self.assertTrue(receipt["truncated"])

    def test_byte_identical_compiler_alias_is_one_package(self):
        self.state()
        folder = self.root / "compiler-symbols"
        shutil.copy2(self.foundation_candidate, folder / "Foundation.app")
        shutil.copy2(self.foundation_candidate, folder / "Foundation_28.0.10.632.app")
        snapshot = G.before_compile(self.root, self.rejection_request())
        foundation_id = "7505e808-6e52-4b96-a328-82573391297a"
        compiler = [s for s in snapshot["compilerSymbols"] if s["identity"]["id"] == foundation_id]
        self.assertEqual(1, len(compiler))
        self.assertEqual(1, len(list(folder.glob("*.app"))))
        self.assertEqual(1, len(snapshot["compilerAliasRemovals"]))
        self.assertTrue((folder / "Foundation_28.0.10.632.app").is_file())
        self.assertFalse((folder / "Foundation.app").is_file())

    def test_conflicting_compiler_versions_preserve_both_disk_hashes(self):
        self.state()
        folder = self.root / "compiler-symbols"
        shutil.copy2(self.foundation, folder / "One.app")
        shutil.copy2(self.foundation_candidate, folder / "Two.app")
        with self.assertRaisesRegex(G.GateError, "conflicting version"):
            G.before_compile(self.root, self.rejection_request())
        self.assertTrue((folder / "One.app").is_file())
        self.assertTrue((folder / "Two.app").is_file())
        items = [i for i in self.rejection_receipt()["inputs"] if i["sourceFolder"] == "compilerSymbolsFolder"]
        self.assertEqual(2, len(items))
        self.assertEqual(sorted([G.file_hash(self.foundation), G.file_hash(self.foundation_candidate)]),
                         sorted(i["sha256"] for i in items))

    def test_manifest_rejection_after_receipt_cap_retains_offending_hash(self):
        self.state()
        folder = self.root / "compiler-symbols"
        # Mutate genuine compiler-produced fixtures into distinct parser inputs.
        # These are diagnostic regressions, never valid deployment evidence.
        import xml.etree.ElementTree as ET
        import uuid
        for index in range(129):
            def unique(entries):
                result = []
                for name, content in entries:
                    if name == "NavxManifest.xml":
                        manifest = ET.fromstring(content)
                        manifest.find("{http://schemas.microsoft.com/navx/2015/manifest}App").set("Id", str(uuid.UUID(int=index + 1)))
                        content = ET.tostring(manifest)
                    result.append((name, content))
                return result
            shutil.move(self.malformed(unique), folder / f"{index:03}.app")
        bad = folder / "zzz-offending.app"
        shutil.move(self.malformed(lambda entries: [(n, b) for n, b in entries if n != "NavxManifest.xml"]), bad)
        with self.assertRaisesRegex(G.GateError, "Missing/duplicate NAVX manifest"):
            G.before_compile(self.root, self.rejection_request())
        receipt = self.rejection_receipt()
        self.assertTrue(receipt["truncated"])
        self.assertEqual(128, len(receipt["inputs"]))
        item = receipt["inputs"][0]
        self.assertEqual(str(bad), item["path"])
        self.assertEqual("compilerSymbolsFolder", item["sourceFolder"])
        self.assertEqual(G.file_hash(bad), item["sha256"])
        self.assertTrue(item["triggeredRejection"])
        self.assertFalse(item["manifestValid"])
        self.assertFalse(receipt["accepted"])

    def test_rejection_receipt_io_failure_preserves_original_gate_error(self):
        self.state()
        package = self.root / "compiler-symbols/Bad.app"
        for operation in ("write_text", "file_hash"):
            with self.subTest(operation=operation):
                # Normalization validates the header before hashing. Use a valid
                # NAVX for the hash failure so that it reaches the intended seam.
                if operation == "file_hash":
                    shutil.copy2(self.foundation_candidate, package)
                    target = patch.object(G, operation, side_effect=OSError("inventory IO failed"))
                    expected_error = "Invalid compiled NAVX payload/manifest"
                else:
                    package.write_bytes(b"bad")
                    target = patch.object(Path, operation, side_effect=OSError("receipt IO failed"))
                    expected_error = "Invalid NAVX header"
                with target, self.assertRaisesRegex(G.GateError, expected_error):
                    G.before_compile(self.root, self.rejection_request())

    def test_inventory_cap_and_missing_folder_are_failures(self):
        with self.assertRaisesRegex(G.GateError, 'absent'):
            G.symbol_inventory(self.root / 'missing')
        folder = self.root / 'bounded'
        folder.mkdir()
        for index in range(257):
            (folder / f'{index}.app').touch()
        with self.assertRaisesRegex(G.GateError, '128 packages'):
            G.symbol_inventory(folder)


if __name__ == "__main__":
    unittest.main()
