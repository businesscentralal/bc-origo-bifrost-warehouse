"""Fail-closed compiler/NAVX evidence checks for the actual AL-Go hooks (#78).

This reader validates package content, not Authenticode trust. The PowerShell
entry point alone obtains a Windows NAVX signature verdict for shipping output.
"""

import argparse
import hashlib
import io
import json
import re
import struct
import sys
import time
import tempfile
import uuid
import zipfile
import zlib
from pathlib import Path
from xml.etree import ElementTree as ET


class GateError(ValueError):
    """Evidence is missing, incompatible, stale or not clean."""


def require(condition, message):
    if not condition:
        raise GateError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


CHUNK_BYTES = 1024 * 1024
PACKAGE_BYTES = 128 * 1024 * 1024
MANIFEST_BYTES = 16 * 1024 * 1024
PACKAGE_ENTRIES = 4096
INVENTORY_SECONDS = 60
COMPILER_CATALOG_SECONDS = 180
MEASURED_PACKAGE_PROFILES = {
    "05d37036733b4df5ffaf31d3d779ec48af63465da6f694ff15a7e0b228abc1b8": {
        "identity": {"id": "437dbf0e-84ff-417a-965d-ed2bb9650972", "publisher": "Microsoft",
                     "name": "Base Application", "version": "29.0.54011.55935"},
        "maxEntries": 4096, "maxExpandedBytes": 512 * 1024 * 1024,
    },
    "10ebba923b6f8d3b6d676cc1f1db16a8a5d4519ff8ca4f45bbd2e778b52d289c": {
        "identity": {"id": "437dbf0e-84ff-417a-965d-ed2bb9650972", "publisher": "Microsoft",
                     "name": "Base Application", "version": "29.0.54011.55935"},
        "maxEntries": 16384, "maxExpandedBytes": 512 * 1024 * 1024,
    },
    # ReadyToRun wrapper from sandbox/28.5.54151.55751/w1, disk size 98891185.
    # Outer expansion is 261371054 bytes. The embedded app has 8602 entries and
    # 373064901 expanded bytes. The outer hash lifts that embedded app.
    "a2e638554f9c97d37f760d6ab42703e1ed136fd229676e79bb1d1a8224a23d23": {
        "identity": {"id": "437dbf0e-84ff-417a-965d-ed2bb9650972", "publisher": "Microsoft",
                     "name": "Base Application", "version": "28.5.54151.55751"},
        "maxEntries": 16384, "maxExpandedBytes": 512 * 1024 * 1024,
    },
}
FOUNDATION_CANDIDATE = {
    "identity": {"id": "7505e808-6e52-4b96-a328-82573391297a", "publisher": "Origo",
                 "name": "Bifrost Foundation", "version": "28.0.3.530"},
    "sha256": "b95e0eccf7a4038531cea08f0441e757ac176c7c4ff06b1b8eb9d25ac0dd3a88",
    "sourceCommit": "8ec074f4ac69ac9bde15807cf16d21bee045332f",
    "buildUrl": "https://github.com/OrigoSoftwareSolutions/bc-origo-bifrost-core/actions/runs/37679390622",
    "compilerVersion": "18.1.43.7601",
    "artifactId": 11508979803,
    "archiveSha256": "21c6331c47d3134d1f3c8c77f240d021fa47710f6fbdebc974b733e0b708bad8",
}
SYMBOL_POLICIES = {
    "appCache": {"packages": 128, "bytes": 512 * 1024 * 1024},
    # Retained BC29 sample measures 1,863,664,153 expanded bytes across
    # envelope+embedded layers; keep compressed and expanded budgets distinct.
    "compilerCatalog": {"packages": 256, "bytes": 1024 * 1024 * 1024,
                        "expandedBytes": 4 * 1024 * 1024 * 1024},
}


def budget_check(deadline):
    require(time.monotonic() <= deadline, "Symbol measurement elapsed budget exceeded")


def file_hash(path, deadline=None):
    sha = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while True:
            if deadline is not None:
                budget_check(deadline)
            chunk = stream.read(CHUNK_BYTES)
            if not chunk:
                break
            sha.update(chunk)
    return sha.hexdigest()


class PayloadView:
    """Seekable NAVX payload window; ZIP cannot inspect the signature tail."""

    def __init__(self, stream, offset, length):
        self.stream, self.offset, self.length, self.position = stream, offset, length, 0

    def seek(self, offset, whence=0):
        position = offset if whence == 0 else self.position + offset if whence == 1 else self.length + offset
        require(0 <= position <= self.length, "ZIP seek outside NAVX payload")
        self.position = position
        return position

    def tell(self):
        return self.position

    def seekable(self):
        return True

    def read(self, size=-1):
        size = self.length - self.position if size < 0 else min(size, self.length - self.position)
        self.stream.seek(self.offset + self.position)
        chunk = self.stream.read(size)
        require(len(chunk) == size, "Truncated NAVX payload")
        self.position += len(chunk)
        return chunk


def version_tuple(value):
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", value or "") is not None,
            "Invalid dependency/package version")
    parts = tuple(int(part) for part in value.split("."))
    require(all(part <= 2147483647 for part in parts), "Version component out of range")
    return parts + (0,) * (4 - len(parts))


def identity_check(identity):
    require(all(identity.values()), "Incomplete package identity")
    try:
        uuid.UUID(identity["id"])
    except (ValueError, AttributeError) as exc:
        raise GateError("Invalid package/dependency AppId") from exc
    version_tuple(identity["version"])


def read_log(data):
    """Decode actual compiler/Actions output, rejecting undecodable evidence."""
    encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    try:
        return data.decode(encoding)
    except UnicodeError as exc:
        raise GateError("Invalid compiler output encoding") from exc


def compile_spans(text):
    """Require a compiler banner and paired positive-count compile for each span.

    Multiple translation/final compiles are retained; only the last span can
    satisfy a PostCompileApp receipt. No old completion masks a later truncation.
    """
    require(text.strip(), "Empty compiler output")
    spans, opened, compiler = [], None, None
    for original in text.splitlines():
        line = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", original)
        line = re.sub(r"^\d{4}-\d{2}-\d{2}T\S+Z\s+", "", line).strip()
        diagnostic = (
            r"(?:^|\):\s*)(?:warning|error)\s+[A-Z]{2,3}\d{4}\s*:"
            r"|^::(?:warning|error)(?:\s|::)|^##\[(?:warning|error)\]"
            r"|^##vso\[task\.(?:logissue\s+type=(?:warning|error)|complete\s+result=(?:Failed|SucceededWithIssues))"
            r"|App generation failed|Retrying without Cops"
        )
        require(not re.search(diagnostic, line, re.I), "Compiler/pipeline diagnostic present")
        match = re.match(r"Microsoft \(R\) AL Compiler version (\S+)", line)
        if match:
            require(opened is None and compiler is None, "Unpaired compiler banner")
            compiler = match[1]
        match = re.match(r"Compilation started for project '([^']+)' containing '(\d+)' files", line)
        if match:
            require(opened is None and compiler is not None, "Missing compiler or nested compilation")
            require(int(match[2]) > 0, "Compilation contains no sources")
            opened = {"project": match[1], "sourceCount": int(match[2]), "compilerVersion": compiler}
            compiler = None
        if re.match(r"Compilation ended\b", line):
            require(opened is not None, "Orphan compiler completion")
            spans.append(opened)
            opened = None
    require(opened is None and compiler is None, "Truncated final compilation")
    require(spans, "No complete compilation")
    return spans


def _compiler_manifest_document(node, namespace):
    """Canonical compiler manifest. Timestamps and translation packaging flags are not inputs."""
    ignored_flags = ("TRANSLATIONFILE", "LCGTRANSLATIONFILE")
    attributes = {key: value for key, value in node.attrib.items()
                  if not (node.tag == namespace + "Build" and key == "Timestamp")}
    children = []
    for child in list(node):
        if (node.tag == namespace + "Features" and child.tag == namespace + "Feature"
                and (child.text or "").strip() in ignored_flags):
            continue
        children.append(_compiler_manifest_document(child, namespace))
    return [node.tag, sorted(attributes.items()), (node.text or "").strip(), children]


def _compiler_manifest_hash(root):
    namespace = "{http://schemas.microsoft.com/navx/2015/manifest}"
    return digest(json.dumps(_compiler_manifest_document(root, namespace), sort_keys=True).encode())


def package_info(path, deadline=None, *, allow_ready_to_run=False, measured_profile=None):
    """Stream bounded NAVX content and metadata; signature presence is not trust."""
    path = Path(path)
    deadline = time.monotonic() + INVENTORY_SECONDS if deadline is None else deadline
    budget_check(deadline)
    require(path.is_file() and not path.is_symlink(), "Missing package or linked input")
    before = path.stat()
    require(before.st_size >= 40, "Invalid NAVX header")
    require(before.st_size <= PACKAGE_BYTES, "Package exceeds 128 MiB")
    try:
        with path.open("rb") as stream:
            header = stream.read(40)
            require(header[:4] == b"NAVX" and header[36:40] == b"NAVX", "Invalid NAVX header")
            header_size, version = struct.unpack_from("<II", header, 4)
            length = struct.unpack_from("<Q", header, 28)[0]
            require(header_size == 40 and version == 2, "Unsupported NAVX header version")
            require(0 < length <= before.st_size - 40 and stream.read(4) == b"PK\x03\x04",
                    "Invalid NAVX payload length/header")
            initial_hash = file_hash(path, deadline)
            profile = MEASURED_PACKAGE_PROFILES.get(initial_hash)
            if profile is None:
                profile = measured_profile
            max_entries = profile["maxEntries"] if profile else PACKAGE_ENTRIES
            max_expanded = profile["maxExpandedBytes"] if profile else PACKAGE_BYTES
            with zipfile.ZipFile(PayloadView(stream, 40, length)) as archive:
                items = archive.infolist()
                require(len(items) <= max_entries, "Package entry bound exceeded")
                names = [item.filename for item in items]
                require(len(names) == len(set(names)), "Duplicate package entries")
                require(not ("NavxManifest.xml" in names and "readytorunappmanifest.json" in names),
                        "Ambiguous NAVX/ReadyToRun manifests")
                if names.count("NavxManifest.xml") == 0 and allow_ready_to_run and "readytorunappmanifest.json" in names:
                    return ready_to_run_info(path, before, archive, items, initial_hash, length,
                                             deadline, max_expanded, profile)
                require(names.count("NavxManifest.xml") == 1, "Missing/duplicate NAVX manifest")
                expanded = sum(item.file_size for item in items)
                require(expanded <= max_expanded, "Package expanded-byte bound exceeded")
                require(archive.getinfo("NavxManifest.xml").file_size <= MANIFEST_BYTES,
                        "Manifest exceeds 16 MiB")
                entries, manifest = [], None
                for item in sorted(items, key=lambda item: item.filename):
                    sha, size, chunks = hashlib.sha256(), 0, []
                    with archive.open(item) as content:
                        while True:
                            budget_check(deadline)
                            chunk = content.read(CHUNK_BYTES)
                            if not chunk:
                                break
                            size += len(chunk)
                            require(size <= item.file_size and size <= max_expanded, "Expanded entry bound exceeded")
                            sha.update(chunk)
                            if item.filename == "NavxManifest.xml":
                                chunks.append(chunk)
                    require(size == item.file_size, "Truncated expanded entry")
                    entries.append({"name": item.filename, "sha256": sha.hexdigest()})
                    if item.filename == "NavxManifest.xml":
                        manifest = b"".join(chunks)
                xml_text = manifest.decode("utf-16" if manifest.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
                require("<!DOCTYPE" not in xml_text.upper() and "<!ENTITY" not in xml_text.upper(), "Unsafe manifest XML")
                root = ET.fromstring(manifest)
                namespace = "{http://schemas.microsoft.com/navx/2015/manifest}"
                require(root.tag == namespace + "Package", "Invalid manifest root/namespace")

                def one(name):
                    nodes = root.findall(namespace + name)
                    require(len(nodes) == 1, "Missing/duplicate manifest " + name)
                    return nodes[0]

                app, friends = one("App"), one("InternalsVisibleTo")
                source_nodes, build_nodes = root.findall(namespace + "Source"), root.findall(namespace + "Build")
                require(len(source_nodes) <= 1 and len(build_nodes) <= 1, "Duplicate source/build metadata")
                source = source_nodes[0] if source_nodes else ET.Element("Source")
                build = build_nodes[0] if build_nodes else ET.Element("Build")
                identity = {key.lower(): app.get(key, "") for key in ("Id", "Publisher", "Name", "Version")}
                identity_check(identity)
                if profile:
                    require(identity == profile["identity"], "Measured package profile identity mismatch")
                grants = []
                for friend in friends:
                    require(friend.tag == namespace + "Module", "Unknown friend element")
                    grant = {key.lower(): friend.get(key, "") for key in ("Id", "Publisher", "Name")}
                    require(all(grant.values()), "Incomplete friend identity")
                    grants.append(grant)
                dependencies = []
                nodes = root.findall(namespace + "Dependencies")
                require(len(nodes) <= 1, "Duplicate dependency metadata")
                for node in nodes[0] if nodes else []:
                    require(node.tag == namespace + "Dependency", "Unknown dependency metadata")
                    dep = {key.lower(): node.get(key, "") for key in ("Id", "Publisher", "Name", "MinVersion")}
                    dep["id"] = dep["id"] or node.get("AppId", "")
                    dep["version"] = dep.pop("minversion") or node.get("Version", "")
                    identity_check(dep)
                    dependencies.append(dep)
                propagate = app.get("PropagateDependencies", "false").lower()
                require(propagate in ("true", "false"), "Invalid PropagateDependencies")
                application, platform = app.get("Application", ""), app.get("Platform", "")
                for value in (application, platform):
                    if value:
                        version_tuple(value)
        require(tuple(getattr(path.stat(), k) for k in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")) ==
                tuple(getattr(before, k) for k in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns"))
                and file_hash(path, deadline) == initial_hash,
                "Package changed during measurement")
        budget_check(deadline)
    except (zipfile.BadZipFile, ET.ParseError, RuntimeError, OSError, zlib.error, UnicodeError) as exc:
        raise GateError("Invalid compiled NAVX payload/manifest") from exc
    return {"identity": identity, "friends": grants, "dependencies": dependencies,
            "application": application, "platform": platform, "propagateDependencies": propagate == "true",
            "sourceCommit": source.get("Commit", ""), "compilerVersion": build.get("CompilerVersion", ""),
            "buildUrl": build.get("Url", ""), "sha256": initial_hash,
            "contentSha256": digest(json.dumps(entries, sort_keys=True).encode()),
            "symbolReferenceSha256": next((entry["sha256"] for entry in entries
                                           if entry["name"] == "SymbolReference.json"), None),
            "compilerManifestSha256": _compiler_manifest_hash(root),
            "bytes": before.st_size, "expandedBytes": expanded, "entryCount": len(items),
            "resourceProfile": initial_hash if profile else "generic",
            "signatureTailBytes": before.st_size - 40 - length}



def ready_to_run_info(path, before, archive, items, initial_hash, length, deadline, max_expanded, profile):
    """Read one bounded ReadyToRun envelope for dependency inventories only.

    Report the outer file hash consumed by the helper, and retain the embedded
    NAVX hash separately. No wrapper is accepted for shipping/postcompile output.
    """
    names = [item.filename for item in items]
    require(names.count("readytorunappmanifest.json") == 1, "Missing/duplicate ReadyToRun manifest")
    expanded = sum(item.file_size for item in items)
    require(expanded <= max_expanded, "Package expanded-byte bound exceeded")
    require(archive.getinfo("readytorunappmanifest.json").file_size <= MANIFEST_BYTES,
            "ReadyToRun manifest exceeds 16 MiB")
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate ReadyToRun metadata key")
            result[key] = value
        return result
    metadata = json.loads(archive.read("readytorunappmanifest.json").decode("utf-8-sig"),
                          object_pairs_hook=unique_object)
    keys = {"EmbeddedAppId", "EmbeddedAppPublisher", "EmbeddedAppName", "EmbeddedAppVersion", "EmbeddedAppFileName"}
    require(isinstance(metadata, dict) and set(metadata) == keys and
            all(isinstance(value, str) and value for value in metadata.values()), "Invalid ReadyToRun metadata")
    expected = {key.lower(): metadata["EmbeddedApp" + key] for key in ("Id", "Publisher", "Name", "Version")}
    identity_check(expected)
    embedded = metadata["EmbeddedAppFileName"]
    require("/" not in embedded and "\\" not in embedded and ":" not in embedded and
            embedded not in (".", "..") and embedded.lower().endswith(".app"), "Invalid ReadyToRun embedded filename")
    require([name for name in names if name.lower().endswith(".app")] == [embedded],
            "Missing/ambiguous ReadyToRun embedded app")
    require(archive.getinfo(embedded).file_size <= PACKAGE_BYTES, "Embedded package exceeds 128 MiB")
    entries = []
    with tempfile.TemporaryDirectory(prefix="appsource-r2r-") as scratch:
        inner_path = Path(scratch) / "embedded.app"
        for item in sorted(items, key=lambda item: item.filename):
            sha, size = hashlib.sha256(), 0
            with archive.open(item) as content:
                with inner_path.open("wb") if item.filename == embedded else io.BytesIO() as target:
                    while True:
                        budget_check(deadline)
                        chunk = content.read(CHUNK_BYTES)
                        if not chunk:
                            break
                        size += len(chunk)
                        require(size <= item.file_size and size <= max_expanded, "Expanded entry bound exceeded")
                        sha.update(chunk)
                        if item.filename == embedded:
                            target.write(chunk)
            require(size == item.file_size, "Truncated expanded entry")
            entries.append({"name": item.filename, "sha256": sha.hexdigest()})
        inner = package_info(inner_path, deadline, measured_profile=profile)
        require(inner["identity"] == expected, "ReadyToRun embedded identity mismatch")
        if profile:
            require(inner["identity"] == profile["identity"], "Measured package profile identity mismatch")
    require(tuple(getattr(path.stat(), key) for key in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")) ==
            tuple(getattr(before, key) for key in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")) and
            file_hash(path, deadline) == initial_hash, "Package changed during measurement")
    budget_check(deadline)
    # Count work at both compression layers in the aggregate inventory budget.
    return {**inner, "sha256": initial_hash, "contentSha256": digest(json.dumps(entries, sort_keys=True).encode()),
            "bytes": before.st_size, "expandedBytes": expanded + inner["expandedBytes"], "entryCount": len(items),
            "resourceProfile": initial_hash if profile else "generic", "signatureTailBytes": before.st_size - 40 - length,
            "readyToRun": {"embeddedSha256": inner["sha256"], "embeddedContentSha256": inner["contentSha256"],
                           "embeddedEntryCount": inner["entryCount"], "embeddedExpandedBytes": inner["expandedBytes"],
                           "outerExpandedBytes": expanded, "signatureTrustVerified": False}}


def check_package(info, expected, mode, app_type, friend, source_commit=None):
    require(info["identity"] == {k: expected[k] for k in ("id", "publisher", "name", "version")}, "Wrong package identity/version")
    expected_grants = [friend] if mode == "Test" and app_type == "app" else []
    require(info["friends"] == expected_grants, "Wrong/missing/surviving compiled friend grants")
    if source_commit is not None:
        require(info["sourceCommit"] == source_commit, "Wrong compiled source commit")


def check_foundation_candidate(info):
    """Exact development candidate content, not Windows signature acceptance."""
    for key in ("identity", "sha256", "sourceCommit", "buildUrl", "compilerVersion"):
        require(info[key] == FOUNDATION_CANDIDATE[key], "Unapproved Foundation candidate " + key)
    require(info["friends"] == [] and info["signatureTailBytes"] > 0,
            "Foundation candidate friend/signature-content mismatch")
    return {"candidate": "candidate530", "artifactId": FOUNDATION_CANDIDATE["artifactId"],
            "archiveSha256": FOUNDATION_CANDIDATE["archiveSha256"], "signatureTrustVerified": False,
            "runnerInputEqualityVerified": False}


def validate_parameters(params):
    for cop in ("enableCodeCop", "enableUICop", "enableAppSourceCop"):
        require(params.get(cop) is True, "Final analyzer disabled/missing: " + cop)
    require(params.get("failOn") == "warning", "Final failOn must be warning")
    require(params.get("escapeFromCops") is False, "Analyzer fallback not ruled out")
    require(params.get("workspaceCompilation") is False, "Workspace hook bypass unsupported")
    require(params.get("rulesetValidated") is True, "Final ruleset not validated")
    for name in ("compiler", "CodeCop", "UICop", "AppSourceCop", "Analyzers.Common", "helper", "alpacaOverride"):
        item = params.get("tools", {}).get(name, {})
        require(re.fullmatch(r"[a-f0-9]{64}", item.get("sha256", "")) is not None,
                "Missing compiler/analyzer/helper hash: " + name)
    require(params.get("compilerVersion"), "Missing compiler version")


class SymbolInventory(list):
    """List-compatible immutable receipt payload with local elapsed measurement."""


def symbol_inventory(folder, policy="appCache", expanded_exemptions=()):
    """Complete inventories use distinct finite catalog/cache resource policies.

    App-cache expanded exemptions are exact compiler-catalog package hashes
    already measured under the catalog budget. They still count toward the
    cache package and disk-byte bounds. The catalog inventory never exempts.
    """
    require(policy in SYMBOL_POLICIES, "Unknown symbol resource policy")
    exemptions = set(expanded_exemptions) if policy == "appCache" else set()
    folder = Path(folder)
    require(folder.is_dir() and not folder.is_symlink(), "Actual symbol folder absent or linked")
    limit, started = SYMBOL_POLICIES[policy], time.monotonic()
    deadline = started + (COMPILER_CATALOG_SECONDS if policy == "compilerCatalog" else INVENTORY_SECONDS)
    paths = []
    for path in folder.iterdir():
        budget_check(deadline)
        if path.suffix.lower() == ".app":
            paths.append(path)
            require(len(paths) <= limit["packages"], "Symbol inventory exceeds " + str(limit["packages"]) + " packages (" + policy + ")")
    paths.sort()
    require(sum(path.stat().st_size for path in paths) <= limit["bytes"], "Symbol aggregate-byte bound exceeded")
    result, identities, filenames, expanded = SymbolInventory(), {}, set(), 0
    for path in paths:
        try:
            info = package_info(path, min(deadline, time.monotonic() + INVENTORY_SECONDS), allow_ready_to_run=True)
        except GateError as error:
            # Retain the actual failing input even beyond the diagnostic item cap.
            error.rejected_package = path
            raise
        identity = (info["identity"]["id"].lower(), version_tuple(info["identity"]["version"]))
        if identity in identities:
            error = GateError("Duplicate symbol identity/version: " + identities[identity].name + " and " + path.name)
            error.rejected_packages = (identities[identity], path)
            raise error
        require(path.name.casefold() not in filenames, "Case-insensitive symbol filename collision")
        identities[identity] = path
        filenames.add(path.name.casefold())
        # Envelope plus embedded expansion for a catalog copy is already inside
        # the catalog budget. Charging it again against the cache's 512 MiB
        # expanded bound rejects the helper's dependency copy.
        if info["sha256"] not in exemptions:
            expanded += info["expandedBytes"]
        require(expanded <= limit.get("expandedBytes", limit["bytes"]), "Symbol aggregate expanded-byte bound exceeded")
        result.append({"file": path.name, **info})
    budget_check(deadline)
    require(sorted(p.name for p in folder.iterdir() if p.suffix.lower() == ".app") == sorted(p.name for p in paths),
            "Symbol inventory membership changed during measurement")
    result.elapsed_seconds = time.monotonic() - started
    return result


def _symbol_conflict(kept, other):
    """None when two same-identity packages are one compiler input.

    Byte-identical files, identical zip entries, and a ReadyToRun wrapper whose
    embedded app matches the other package's entries are the same package.
    Otherwise SymbolReference.json and the canonical compiler manifest must
    both be present and equal. A missing symbol reference is a conflict.
    """
    if kept["identity"] != other["identity"]:
        return "identity"
    if kept["sha256"] == other["sha256"] or kept["contentSha256"] == other["contentSha256"]:
        return None
    for left, right in ((kept, other), (other, kept)):
        embedded = (left.get("readyToRun") or {}).get("embeddedContentSha256")
        if embedded and embedded == right["contentSha256"]:
            return None
    left_symbol, right_symbol = kept.get("symbolReferenceSha256"), other.get("symbolReferenceSha256")
    if not left_symbol or not right_symbol:
        return "missing symbol reference"
    if left_symbol != right_symbol:
        return "symbol reference"
    if kept.get("compilerManifestSha256") != other.get("compilerManifestSha256"):
        return "compiler manifest"
    return None


def _prefer_retained_symbol(item):
    """Keep the versioned artifact name; it is the catalog's primary filename."""
    versioned = item["file"].casefold().endswith("_" + item["identity"]["version"].casefold() + ".app")
    return (0 if versioned else 1, item["file"].casefold())


def collapse_equivalent_compiler_symbols(folder):
    """Remove filename aliases from the compiler catalog and leave one package.

    Byte-identical copies, same entry content, a ReadyToRun wrapper of that
    content, and the same id+version with the same symbol reference and
    canonical compiler manifest are deleted only after every group has been
    checked. The versioned filename is kept. The same app id with different
    symbol or manifest content, or two versions of that id, fails and the
    folder is left unchanged. The app-symbol cache is not modified.
    """
    folder = Path(folder)
    require(folder.is_dir() and not folder.is_symlink(), "Actual symbol folder absent or linked")
    limit = SYMBOL_POLICIES["compilerCatalog"]
    deadline = time.monotonic() + COMPILER_CATALOG_SECONDS
    paths = []
    for path in folder.iterdir():
        budget_check(deadline)
        if path.suffix.lower() == ".app":
            paths.append(path)
            require(len(paths) <= limit["packages"],
                    "Symbol inventory exceeds " + str(limit["packages"]) + " packages (compilerCatalog)")
    paths.sort()
    require(sum(path.stat().st_size for path in paths) <= limit["bytes"], "Symbol aggregate-byte bound exceeded")
    infos, expanded = [], 0
    for path in paths:
        try:
            info = package_info(path, min(deadline, time.monotonic() + INVENTORY_SECONDS), allow_ready_to_run=True)
        except GateError as error:
            error.rejected_package = path
            raise
        expanded += info["expandedBytes"]
        require(expanded <= limit.get("expandedBytes", limit["bytes"]), "Symbol aggregate expanded-byte bound exceeded")
        info["file"] = path.name
        infos.append(info)
    by_id = {}
    for info in infos:
        by_id.setdefault(info["identity"]["id"].lower(), []).append(info)
    for app_id, items in by_id.items():
        versions = []
        for info in items:
            if info["identity"]["version"] not in versions:
                versions.append(info["identity"]["version"])
        if len(versions) > 1:
            error = GateError("Duplicate symbol identity with conflicting version: "
                              + app_id + " " + " vs ".join(versions))
            error.rejected_package = folder / items[-1]["file"]
            raise error
    groups = {}
    for info in infos:
        key = (info["identity"]["id"].lower(), version_tuple(info["identity"]["version"]))
        groups.setdefault(key, []).append(info)
    removals = []
    for items in groups.values():
        if len(items) == 1:
            continue
        items.sort(key=_prefer_retained_symbol)
        kept = items[0]
        for other in items[1:]:
            reason = _symbol_conflict(kept, other)
            if reason is None:
                removals.append({"retained": kept["file"], "removed": other["file"],
                                 "sha256": kept["sha256"], "removedSha256": other["sha256"],
                                 "contentSha256": kept["contentSha256"],
                                 "symbolReferenceSha256": kept.get("symbolReferenceSha256"),
                                 "compilerManifestSha256": kept.get("compilerManifestSha256"),
                                 "identity": kept["identity"]})
                continue
            error = GateError("Duplicate symbol identity/version with conflicting content ("
                              + reason + "): " + other["identity"]["publisher"] + " "
                              + other["identity"]["name"] + " " + other["identity"]["version"])
            error.rejected_package = folder / other["file"]
            raise error
    verified = []
    for item in removals:
        path = folder / item["removed"]
        require(path.is_file() and not path.is_symlink() and file_hash(path, deadline) == item["removedSha256"],
                "Catalog changed before alias removal")
        verified.append(path)
    for path in verified:
        path.unlink()
    return removals


def inventory_measurement(items, policy):
    return {"policy": policy, "limits": SYMBOL_POLICIES[policy], "packages": len(items),
            "bytes": sum(s["bytes"] for s in items), "expandedBytes": sum(s["expandedBytes"] for s in items),
            "inventorySha256": digest(json.dumps(items, sort_keys=True).encode()),
            "elapsedSeconds": getattr(items, "elapsed_seconds", None), "elapsedBudgetSeconds": COMPILER_CATALOG_SECONDS if policy == "compilerCatalog" else INVENTORY_SECONDS,
            "packageElapsedBudgetSeconds": INVENTORY_SECONDS,
            "runnerCapacityValidated": False}


def resolve_helper_inputs(manifest, existing, catalog):
    """Observe helper6.1.18 selection; never substitute its compiler/cache inputs.

    Existing highest compatible version wins; otherwise the helper copies ALL
    compatible catalog versions. Copied inputs follow all dependencies; existing
    inputs follow dependencies only when PropagateDependencies is true.
    Full identity checks deliberately refuse helper's AppId-only mismatches.
    """
    dependencies = list(manifest.get("dependencies", []))
    for field, app_id, name in (("application", "c1335042-3002-4257-bf8a-75c898ccb1b8", "Application"),
                               ("platform", "8874ed3a-0643-4247-9ced-7a7002f7135d", "System")):
        if manifest.get(field):
            dependencies.insert(0, dict(id=app_id, publisher="Microsoft", name=name, version=manifest[field]))
    available, copies, trace, queued = list(existing), [], [], set()
    index = 0
    while index < len(dependencies):
        require(len(dependencies) <= 4096, "Dependency resolution bound exceeded")
        dep = dependencies[index]
        index += 1
        identity_check(dep)
        key = (dep["id"].lower(), dep["version"], dep["publisher"], dep["name"])
        if key in queued:
            continue
        queued.add(key)

        def matching(items):
            matches = [s for s in items if s["identity"]["id"].lower() == dep["id"].lower()
                       and version_tuple(s["identity"]["version"]) >= version_tuple(dep["version"])]
            require(all(s["identity"]["publisher"] == dep["publisher"] and s["identity"]["name"] == dep["name"]
                        for s in matches), "Wrong resolved dependency publisher/name")
            return sorted(matches, key=lambda s: version_tuple(s["identity"]["version"]), reverse=True)

        found = matching(available)
        chosen = found[:1] if found else matching(catalog)
        require(chosen, "Missing compatible dependency: " + dep["name"])
        trace.append({"dependency": dep, "source": "existing" if found else "compilerCatalog",
                      "selected": [{"file": s["file"], "identity": s["identity"], "sha256": s["sha256"]} for s in chosen]})
        for item in chosen:
            if not found:
                require(all(s["file"].casefold() != item["file"].casefold() for s in available),
                        "Helper copy would overwrite existing input")
                copies.append(item)
                available.append(item)
                if item["application"] and not any(d["name"] == "Application" for d in dependencies):
                    dependencies.append(dict(id="c1335042-3002-4257-bf8a-75c898ccb1b8", publisher="Microsoft",
                                             name="Application", version=item["application"]))
                if item["platform"] and not any(d["name"] == "System" and d["publisher"] == "Microsoft" for d in dependencies):
                    dependencies.append(dict(id="8874ed3a-0643-4247-9ced-7a7002f7135d", publisher="Microsoft",
                                             name="System", version=item["platform"]))
            if not found or item["propagateDependencies"]:
                # Helper queues every catalog version for a new transitive AppId.
                for child in item["dependencies"]:
                    if not any(d["id"].lower() == child["id"].lower() for d in dependencies):
                        transitive = [s["identity"] for s in catalog if s["identity"]["id"].lower() == child["id"].lower()]
                        require(transitive, "Missing transitive catalog dependency: " + child["name"])
                        require(all(d["name"] == child["name"] and d["publisher"] == child["publisher"]
                                    and version_tuple(d["version"]) >= version_tuple(child["version"]) for d in transitive),
                                "Wrong/too-old transitive catalog dependency")
                        dependencies.extend(transitive)
    require(len(available) <= SYMBOL_POLICIES["appCache"]["packages"], "Resolved app cache package bound exceeded")
    require(sum(s["bytes"] for s in available) <= SYMBOL_POLICIES["appCache"]["bytes"],
            "Resolved app cache byte bound exceeded")
    return {"copies": copies, "trace": trace, "resolved": inventory_measurement(available, "appCache"),
            "helperEquivalenceVerified": False, "consumedInputsCertified": False}


def reconcile_symbols(snapshot, request, output):
    """Check boundary observations, not unobservable transient compiler consumption."""
    require(snapshot["symbolsFolder"] == str(Path(request["symbolsFolder"]).resolve()), "Changed symbol cache path")
    require(snapshot["compilerSymbolsFolder"] == str(Path(request["compilerSymbolsFolder"]).resolve()),
            "Changed compiler symbol path")
    compiler = symbol_inventory(request["compilerSymbolsFolder"], "compilerCatalog")
    require(compiler == snapshot["compilerSymbols"], "Compiler-folder inputs changed during helper call")
    final = symbol_inventory(request["symbolsFolder"], expanded_exemptions={item["sha256"] for item in compiler})
    before = {s["file"]: s for s in snapshot["symbols"]}
    prepared = {s["file"]: s for s in compiler}
    after = {s["file"]: s for s in final}
    for name, info in before.items():
        require(after.get(name) == info, "Pre-existing symbol changed or disappeared: " + name)
    additions, copies = [], []
    for name, info in after.items():
        if name in before:
            continue
        if info["identity"]["id"].lower() == output["identity"]["id"].lower():
            require(info["sha256"] == output["sha256"], "Unexpected self/output symbol bytes")
            copies.append(info)
        else:
            require(prepared.get(name) == info, "Unattributed helper symbol addition: " + name)
            additions.append(info)
    require(len(copies) == 1, "Missing/ambiguous exact helper output-copy delta")
    require("resolution" in snapshot, "Missing bounded dependency resolution receipt")
    require(sorted(additions, key=lambda s: s["file"]) == sorted(snapshot["resolution"]["copies"], key=lambda s: s["file"]),
            "Actual helper additions differ from bounded dependency resolution")
    return {"before": snapshot["symbols"], "compilerBeforeAndAfter": compiler,
            "after": final, "preparationAdditions": additions, "outputCopy": copies[0],
            "measurements": {"compilerCatalog": inventory_measurement(compiler, "compilerCatalog"),
                             "appCache": inventory_measurement(final, "appCache")},
            "consumedInputsCertified": False}


def sanitized_inventory(items):
    result = []
    for info in items:
        item = dict(info)
        url = item["buildUrl"]
        item["buildUrl"] = url if re.fullmatch(r"https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+", url) else "redacted-unrecognized-build-url"
        result.append(item)
    return result


def _before_compile(root, request):
    """Snapshot the symbol cache BEFORE helper CopyAppToSymbolsFolder changes it."""
    root = Path(root)
    context = request["context"]
    directory = root / ".buildartifacts/AppSourceGate" / context["mode"]
    state = json.loads((directory / "state.json").read_text(encoding="utf-8-sig"))
    require(state["context"] == context, "Wrong precompiler run context")
    manifest = json.loads(Path(request["manifest"]).read_text(encoding="utf-8-sig"))
    product = json.loads((root / "app/app.json").read_text(encoding="utf-8-sig"))
    test = json.loads((root / "test/app.json").read_text(encoding="utf-8-sig"))
    require(manifest["id"] in (product["id"], test["id"]), "Unexpected compilation project")
    app_type = "app" if manifest["id"] == product["id"] else "testApp"
    alias_removals = collapse_equivalent_compiler_symbols(request["compilerSymbolsFolder"])
    compiler_symbols = symbol_inventory(request["compilerSymbolsFolder"], "compilerCatalog")
    # The test compile remeasures the cache after the product compile copied
    # catalog packages into it. Those exact hashes already passed the catalog
    # budget; the cache expanded bound still applies to everything else.
    symbols = symbol_inventory(
        request["symbolsFolder"],
        expanded_exemptions={item["sha256"] for item in compiler_symbols},
    )
    # Keep successful boundary measurements even if later identity/pin/resolution refuses.
    measured = {"context": context, "measurements": {
        "appCache": inventory_measurement(symbols, "appCache"),
        "compilerCatalog": inventory_measurement(compiler_symbols, "compilerCatalog")},
        "inputs": {"appCache": sanitized_inventory(symbols), "compilerCatalog": sanitized_inventory(compiler_symbols)},
        "folders": {"appCache": str(Path(request["symbolsFolder"]).resolve()),
                    "compilerCatalog": str(Path(request["compilerSymbolsFolder"]).resolve())},
        "consumedInputsCertified": False}
    (directory / "symbol-measurements.json").write_text(json.dumps(measured, indent=2) + "\n")
    for symbol in symbols + compiler_symbols:
        require(symbol["identity"]["id"].lower() != manifest["id"].lower(),
                "Product self-app in actual PRECOMPILE symbol cache")
    require(symbols, "Empty actual precompile symbol inventory")
    foundation = [s for s in symbols if s["identity"]["id"] == "7505e808-6e52-4b96-a328-82573391297a"]
    require(len(foundation) == 1, "Missing/ambiguous/unapproved Foundation input bytes")
    foundation_candidate = check_foundation_candidate(foundation[0])
    if app_type == "testApp":
        require("app" in state["receipts"], "Test compile before product receipt")
        products = [s for s in symbols if s["identity"]["id"] == product["id"]]
        require(len(products) == 1 and products[0]["sha256"] == state["receipts"]["app"]["package"]["sha256"],
                "Test does not consume exact just-built product")
    for symbol in compiler_symbols:
        if symbol["identity"]["id"].lower() == foundation[0]["identity"]["id"].lower():
            require(symbol["sha256"] == foundation[0]["sha256"], "Unapproved compiler-folder Foundation bytes")
        if app_type == "testApp" and symbol["identity"]["id"].lower() == product["id"].lower():
            require(symbol["sha256"] == state["receipts"]["app"]["package"]["sha256"], "Wrong compiler-folder Test product")
    snapshot = {"context": context, "kind": request["kind"], "appType": app_type, "symbols": symbols,
                "symbolsFolder": str(Path(request["symbolsFolder"]).resolve()),
                "compilerSymbolsFolder": str(Path(request["compilerSymbolsFolder"]).resolve()),
                "compilerSymbols": compiler_symbols, "compilerAliasRemovals": alias_removals,
                "measurements": {"appCache": inventory_measurement(symbols, "appCache"),
                                 "compilerCatalog": inventory_measurement(compiler_symbols, "compilerCatalog")},
                "resolution": resolve_helper_inputs(manifest, symbols, compiler_symbols),
                "foundationCandidate": foundation_candidate}
    (directory / "before.json").write_text(json.dumps(snapshot, indent=2) + "\n")
    return snapshot


def rejected_receipt(output, context, paths=(), *, folders=None, offending=None, offending_paths=()):
    """Record bounded disk identities only; never dump Settings or credentials."""
    deadline = time.monotonic() + INVENTORY_SECONDS
    candidates = [(Path(path), None) for path in paths]
    require(len(candidates) <= 4096, "Diagnostic path bound exceeded")
    folder_receipts = []
    for source, folder in (folders or {}).items():
        folder = Path(folder)
        present = folder.is_dir()
        item = {"sourceFolder": source, "path": str(folder), "present": present,
                "packages": 0, "bytes": 0, "enumerationComplete": True}
        folder_receipts.append(item)
        if present:
            for path in folder.iterdir():
                if time.monotonic() > deadline:
                    item["enumerationComplete"] = False
                    break
                if path.suffix.lower() == ".app":
                    item["packages"] += 1
                    item["bytes"] += path.stat().st_size
                    candidates.append((path, source))
                    if len(candidates) >= 4096:
                        item["enumerationComplete"] = False
                        break
    prioritized_paths = {Path(path) for path in offending_paths}
    if offending is not None:
        prioritized_paths.add(Path(offending))
    if prioritized_paths:
        prioritized = [(path, source) for path, source in candidates if path in prioritized_paths]
        candidates = prioritized + [(path, source) for path, source in candidates if path not in prioritized_paths]
    inventory = []
    truncated = len(candidates) > 128 or any(not f["enumerationComplete"] for f in folder_receipts)
    hashed_bytes = 0
    for path, source in candidates[:128]:
        if time.monotonic() > deadline:
            truncated = True
            break
        item = {"path": str(path), "present": path.is_file()}
        if path in prioritized_paths:
            item["triggeredRejection"] = True
        if source is not None:
            item["sourceFolder"] = source
        if item["present"]:
            size = path.stat().st_size
            item["bytes"] = size
            if size > PACKAGE_BYTES or hashed_bytes + size > SYMBOL_POLICIES["appCache"]["bytes"] or path.is_symlink():
                item["truncated"] = True
                truncated = True
            else:
                hashed_bytes += size
                try:
                    item["sha256"] = file_hash(path, deadline)
                except GateError:
                    item["truncated"] = True
                    truncated = True
                    inventory.append(item)
                    break
                try:
                    info = package_info(path, deadline, allow_ready_to_run=True)
                    item.update({k: info[k] for k in ("identity", "friends", "sourceCommit", "compilerVersion")})
                    # Build URLs may contain secrets in malformed/untrusted manifests.
                    url = info["buildUrl"]
                    item["buildUrl"] = url if re.fullmatch(r"https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+", url) else "redacted-unrecognized-build-url"
                except (GateError, OSError, ValueError):
                    item["manifestValid"] = False
        inventory.append(item)
    allowed = {k: context[k] for k in ("run", "attempt", "job", "sourceCommit", "checkoutSha", "mode") if k in context}
    Path(output).write_text(json.dumps({"accepted": False, "context": allowed, "inputs": inventory,
                                      "folders": folder_receipts, "truncated": truncated,
                                      "consumedInputsCertified": False,
                                      "signatureTrustVerified": False}, indent=2) + "\n")


def before_compile(root, request):
    """Keep the original failure while recording bounded allowlisted disk inputs."""
    try:
        return _before_compile(root, request)
    except (GateError, OSError, KeyError, ValueError) as error:
        # Evidence failure must never replace or clear the original gate failure.
        try:
            context = request.get("context", {})
            directory = Path(root) / ".buildartifacts/AppSourceGate" / context.get("mode", "Unknown")
            directory.mkdir(parents=True, exist_ok=True)
            rejected_receipt(directory / "rejected-input.json", context, folders={
                key: request[key] for key in ("symbolsFolder", "compilerSymbolsFolder") if key in request},
                offending=getattr(error, "rejected_package", None),
                offending_paths=getattr(error, "rejected_packages", ()))
        except (OSError, ValueError, KeyError):
            pass
        raise


def post_compile(root, request):
    """Consume only allowlisted data collected inside the actual post hook."""
    root = Path(root)
    context = request["context"]
    state_path = root / ".buildartifacts" / "AppSourceGate" / context["mode"] / "state.json"
    require(state_path.is_file(), "PipelineInitialize receipt missing")
    state = json.loads(state_path.read_text(encoding="utf-8-sig"))
    require(state["context"] == context, "Stale/wrong run, SHA, attempt, job or mode")
    require(context["mode"] in ("Default", "Test"), "Unsupported build mode")
    params = request["parameters"]
    validate_parameters(params)
    app_type = request["appType"]
    require(app_type in ("app", "testApp"), "Unexpected app type")
    require(context["mode"] == "Test" or app_type == "app", "Unexpected Default test compile")
    require(app_type not in state["receipts"], "Duplicate postcompile receipt")
    expected_path = root / ("app" if app_type == "app" else "test") / "app.json"
    expected = json.loads(expected_path.read_text(encoding="utf-8-sig"))
    friend_manifest = json.loads((root / "test" / "app.json").read_text(encoding="utf-8-sig"))
    friend = {k: friend_manifest[k] for k in ("id", "publisher", "name")}
    data = (root / "BuildOutput.txt").read_bytes()
    offset = state["logBytes"]
    require(len(data) > offset, "Missing/new compiler output")
    require(digest(data[:offset]) == state["logPrefixSha256"], "Compiler output replaced/truncated")
    spans = compile_spans(read_log(data[offset:]))
    require(spans[-1]["project"] == expected["name"], "Wrong final compilation project")
    require(spans[-1]["compilerVersion"] == params["compilerVersion"], "Compiler/banner mismatch")
    require(request["sourceFiles"] and spans[-1]["sourceCount"] == len(request["sourceFiles"]), "Source count/inventory mismatch")
    info = package_info(request["appFile"])
    check_package(info, expected, context["mode"], app_type, friend, context["sourceCommit"])
    require(info["compilerVersion"] == params["compilerVersion"], "Package/compiler mismatch")
    require(info["buildUrl"] == context["buildUrl"], "Stale package from different run")
    require(Path(request["appFile"]).stat().st_mtime_ns >= state["startedNs"], "Stale package timestamp")
    snapshot = json.loads((state_path.parent / "before.json").read_text(encoding="utf-8-sig"))
    require(snapshot["context"] == context and snapshot["appType"] == app_type and snapshot["kind"] == "final",
            "Missing/stale/translation-only actual precompile snapshot")
    isolated = (state_path.parent / "current-compile.txt").read_bytes()
    isolated_spans = compile_spans(read_log(isolated))
    require(len(isolated_spans) == 1 and isolated_spans[0] == spans[-1], "Wrong/missing isolated final compiler output")
    boundaries = reconcile_symbols(snapshot, request, info)
    symbols = snapshot["symbols"]
    receipt = {"context": context, "appType": app_type, "parameters": params, "package": info,
               "logSha256": digest(data[offset:]), "isolatedLogSha256": digest(isolated), "spans": spans, "symbols": symbols,
               "sourceFiles": request["sourceFiles"], "symbolBoundaries": boundaries}
    state["receipts"][app_type] = receipt
    state["logBytes"], state["logPrefixSha256"] = len(data), digest(data)
    state_path.write_text(json.dumps(state, indent=2) + "\n")
    return receipt


def reconcile(root, context, stage, signature=None):
    """Check expected hooks and actual published artifact paths, also after Sign."""
    root = Path(root)
    directory = root / ".buildartifacts" / "AppSourceGate" / context["mode"]
    state = json.loads((directory / "state.json").read_text(encoding="utf-8-sig"))
    require(state["context"] == context, "Stale finalize context")
    expected = {"app", "testApp"} if context["mode"] == "Test" else {"app"}
    require(set(state["receipts"]) == expected, "Skipped/missing/unexpected compile hook")
    require(file_hash(root / "BuildOutput.txt") == state["logPrefixSha256"], "Unreceipted later compiler output")
    for relative, sha in state["hookHashes"].items():
        require(file_hash(root / relative) == sha, "Hook/tool displaced during pipeline")
    outputs = []
    for app_type in sorted(expected):
        receipt = state["receipts"][app_type]
        require(receipt["context"] == context, "Wrong receipt mode/run/SHA")
        validate_parameters(receipt["parameters"])
        for item in receipt["sourceFiles"]:
            require(file_hash(root / item["file"]) == item["sha256"], "Compiled AL source changed after receipt")
        folder = root / ".buildartifacts" / ("Apps" if app_type == "app" else "TestApps")
        files = list(folder.glob("*.app"))
        require(len(files) == 1, "Missing/ambiguous final package output")
        info = package_info(files[0])
        require(info["contentSha256"] == receipt["package"]["contentSha256"], "Final package content changed")
        require(stage == "signed" or info["sha256"] == receipt["package"]["sha256"], "Unsigned package bytes changed")
        if stage == "signed":
            require(context["mode"] == "Default", "Only Default shipping is signed")
            require(signature and signature.get("status") == "Valid" and signature.get("signerThumbprint")
                    and signature.get("provider") == "Windows Get-AuthenticodeSignature" and signature.get("sha256") == info["sha256"],
                    "Missing/invalid/unsupported NAVX signature verification")
        outputs.append({"file": str(files[0].relative_to(root)), **info})
    if stage != "finalize":
        finalized = json.loads((directory / "finalize.json").read_text(encoding="utf-8-sig"))
        require(finalized["context"] == context and finalized["stateSha256"] == file_hash(directory / "state.json"),
                "Missing/stale/displaced PipelineFinalize")
    result = {"context": context, "stage": stage, "stateSha256": file_hash(directory / "state.json"), "outputs": outputs}
    if signature:
        result["signature"] = signature
    (directory / (stage + ".json")).write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["before", "post", "finalize", "pipeline", "signed", "package"])
    parser.add_argument("--root", type=Path)
    parser.add_argument("--input", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "package":
            result = package_info(args.input)
        else:
            request = json.loads(args.input.read_text(encoding="utf-8-sig"))
            if args.action == "before":
                result = before_compile(args.root, request)
            elif args.action == "post":
                result = post_compile(args.root, request)
            else:
                result = reconcile(args.root, request["context"], args.action, request.get("signature"))
        # Receipts are files, not console dumps of pipeline settings or paths.
        print(json.dumps(result) if args.action == "package" else "AppSource gate: " + args.action + " passed")
        return 0
    except (GateError, OSError, KeyError, ValueError) as exc:
        print("AppSource gate failed: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
