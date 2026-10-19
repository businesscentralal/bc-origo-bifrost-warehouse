"""TestApps filename collision restore. Synthetic packages, not artifact certification."""
import base64
import copy
import http.server
import io
import json
import threading
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).parents[1]))
import stage_foundation_inputs as S
from test_symbol_policy import fixture


def with_friend(path):
    data = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(data[40:])) as archive:
        entries = [(name, archive.read(name)) for name in archive.namelist()]
    namespace = "{http://schemas.microsoft.com/navx/2015/manifest}"
    updated = []
    for name, content in entries:
        if name == "NavxManifest.xml":
            root = ET.fromstring(content)
            parent = root.find(namespace + "InternalsVisibleTo")
            ET.SubElement(parent, namespace + "Module", {
                "Id": S.TEST_FRIEND["id"], "Publisher": S.TEST_FRIEND["publisher"], "Name": S.TEST_FRIEND["name"]})
            content = ET.tostring(root)
        updated.append((name, content))
    payload = io.BytesIO()
    with zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in updated:
            archive.writestr(name, content)
    header = bytearray(data[:40])
    struct.pack_into("<Q", header, 28, len(payload.getvalue()))
    path.write_bytes(bytes(header) + payload.getvalue())


def archive_of(path, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(path, path.name)
    return destination


class WorkflowToken(unittest.TestCase):
    def test_algo_secret_json_is_base64_decoded(self):
        encoded = base64.b64encode(b"ghp_exampletokenvalue000").decode("ascii")
        with patch.dict("os.environ", {"Secrets": json.dumps({"ghTokenWorkflow": encoded})}, clear=False):
            self.assertEqual("ghp_exampletokenvalue000", S.workflow_token())


class ArtifactDownload(unittest.TestCase):
    def test_redirect_does_not_forward_the_token(self):
        seen = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen.setdefault(self.path, []).append(self.headers.get("Authorization"))
                if self.path == "/zip":
                    self.send_response(302)
                    location = "http://127.0.0.1:%d/file" % self.server.server_address[1]
                    self.send_header("Location", location)
                    self.end_headers()
                    return
                if self.headers.get("Authorization"):
                    self.send_response(401)
                    self.end_headers()
                    return
                body = b"PK\x03\x04ok"
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        destination = Path(tempfile.mkdtemp()) / "artifact.bin"
        try:
            S._download_url("http://127.0.0.1:%d/zip" % server.server_address[1],
                            "secret-token-value-0000", destination)
            self.assertEqual(b"PK\x03\x04ok", destination.read_bytes())
            self.assertEqual("Bearer secret-token-value-0000", seen["/zip"][0])
            self.assertIsNone(seen["/file"][0])
        finally:
            server.shutdown()
            server.server_close()

    def test_dropped_connection_is_retried(self):
        calls = {"n": 0}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                calls["n"] += 1
                if calls["n"] == 1:
                    self.close_connection = True
                    return
                body = b"PK\x03\x04ok"
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        destination = Path(tempfile.mkdtemp()) / "artifact.bin"
        try:
            with patch.object(S.time, "sleep"):
                S._download_url("http://127.0.0.1:%d/file" % server.server_address[1],
                                "secret-token-value-0000", destination)
            self.assertEqual(b"PK\x03\x04ok", destination.read_bytes())
            self.assertGreaterEqual(calls["n"], 2)
        finally:
            server.shutdown()
            server.server_close()


class FoundationRestore(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dependencies = self.root / ".dependencies"
        self.dependencies.mkdir()
        self.identity = dict(S.PROFILES["candidate530"]["identity"])
        self.collision = self.dependencies / "Origo_Bifrost Foundation_28.0.3.530.app"
        fixture(self.collision, self.identity)
        with_friend(self.collision)
        self.approved_source = self.root / "approved.app"
        fixture(self.approved_source, self.identity)
        self.archive = archive_of(self.approved_source, self.root / "apps.zip")
        self.config = copy.deepcopy(S.PROFILES["candidate530"])
        self.config["pin"] = S.file_hash(self.approved_source)
        self.config["testPin"] = S.file_hash(self.collision)
        self.config["source"] = ""
        self.config["buildUrl"] = ""
        self.config["artifacts"] = dict(self.config["artifacts"])
        self.config["artifacts"]["Apps"] = (self.config["artifacts"]["Apps"][0], S.file_hash(self.archive))
        self.calls = 0

    def fetch(self, destination):
        self.calls += 1
        destination.write_bytes(self.archive.read_bytes())
        return destination

    def restore(self):
        with patch.dict(S.PROFILES, {"candidate530": self.config}):
            return S.restore_overwritten_foundation(self.root, self.fetch)

    def test_testapps_collision_is_replaced_and_other_files_stay(self):
        other = self.dependencies / "Other.app"
        other.write_bytes(b"leave-me")
        result = self.restore()
        self.assertEqual("restored", result["action"])
        self.assertEqual(self.config["pin"], S.file_hash(self.collision))
        self.assertEqual([], S.package_info(self.collision)["friends"])
        self.assertEqual(b"leave-me", other.read_bytes())
        self.assertEqual(1, self.calls)

    def test_symbol_folder_outside_the_standard_cache_is_restored(self):
        self.collision.unlink()
        symbols = self.root / "compiler-symbols"
        symbols.mkdir()
        external = symbols / "Origo_Bifrost Foundation_28.0.3.530.app"
        fixture(external, self.identity)
        with_friend(external)
        self.config["testPin"] = S.file_hash(external)
        with patch.dict(S.PROFILES, {"candidate530": self.config}):
            result = S.restore_overwritten_foundation(self.root, self.fetch, symbols=symbols)
        self.assertEqual([str(external)], result["restored"])
        self.assertEqual(self.config["pin"], S.file_hash(external))

    def test_approved_package_is_not_downloaded_again(self):
        self.collision.write_bytes(self.approved_source.read_bytes())
        result = self.restore()
        self.assertEqual("already-approved", result["action"])
        self.assertEqual(0, self.calls)

    def test_unknown_hash_fails_without_download_or_replacement(self):
        before = self.collision.read_bytes()
        self.config["testPin"] = "0" * 64
        with self.assertRaisesRegex(S.GateError, "Unapproved Foundation"):
            self.restore()
        self.assertEqual(before, self.collision.read_bytes())
        self.assertEqual(0, self.calls)

    def test_wrong_archive_hash_leaves_the_collision(self):
        before = self.collision.read_bytes()
        self.config["artifacts"]["Apps"] = (self.config["artifacts"]["Apps"][0], "1" * 64)
        with self.assertRaisesRegex(S.GateError, "Changed Foundation Apps artifact"):
            self.restore()
        self.assertEqual(before, self.collision.read_bytes())


if __name__ == "__main__":
    unittest.main(verbosity=2)
