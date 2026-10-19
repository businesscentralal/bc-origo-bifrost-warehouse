"""Check source allocations and dependency identities before AL compilation (#74)."""

import argparse
import json
import re
from pathlib import Path


TOKEN = re.compile(r"//[^\n]*|/\*[\s\S]*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|[A-Za-z_][\w]*|\d+|[^\s]")
OBJECT_KINDS = {
    "table", "tableextension", "page", "pageextension", "codeunit", "query",
    "report", "reportextension", "xmlport", "enum", "enumextension",
    "permissionset", "permissionsetextension",
}
FOUNDATION_ID = "7505e808-6e52-4b96-a328-82573391297a"


def tokens(source):
    """Ignore comments without interpreting quoted AL identifiers as code."""
    return [t for t in TOKEN.findall(source) if not t.startswith(("//", "/*"))]


def check_project(project):
    """Return allocation/dependency errors for a single app's identity and ranges."""
    manifest = json.loads((project / "app.json").read_text(encoding="utf-8-sig"))
    errors = []
    objects = {}
    values = {}
    ranges = manifest["idRanges"]

    def in_range(number):
        return any(r["from"] <= number <= r["to"] for r in ranges)

    for dependency in manifest.get("dependencies", []):
        if dependency["id"].lower() == manifest["id"].lower():
            errors.append("manifest declares its own app as a dependency")
        if dependency["id"].lower() == FOUNDATION_ID:
            if (dependency["name"], dependency["publisher"]) != ("Bifrost Foundation", "Origo"):
                errors.append("Foundation dependency identity does not match its AppId")
            if tuple(map(int, dependency["version"].split("."))) < (28, 0, 3, 530):
                errors.append("Foundation dependency is below 28.0.3.530")

    for path in sorted(project.rglob("*.al")):
        stream = tokens(path.read_text(encoding="utf-8-sig"))
        relative = str(path.relative_to(project))
        for i, token in enumerate(stream[:-3]):
            kind = token.lower()
            if kind not in OBJECT_KINDS or not stream[i + 1].isdigit():
                continue
            number = int(stream[i + 1])
            key = (kind, number)
            if key in objects:
                errors.append(f"duplicate {kind} {number}: {objects[key]} and {relative}")
            objects[key] = relative
            if not in_range(number):
                errors.append(f"unallocated {kind} {number}: {relative}")
            if kind not in {"enum", "enumextension"}:
                continue
            target = stream[i + 2]
            start = i + 3
            if kind == "enumextension":
                if stream[start].lower() != "extends":
                    errors.append(f"cannot resolve enum extension target: {relative}")
                    continue
                target = stream[start + 1]
                start += 2
            target = target.strip('"').lower()
            depth = 0
            for j in range(start, len(stream)):
                item = stream[j]
                if item == "{":
                    depth += 1
                elif item == "}":
                    depth -= 1
                    if depth == 0:
                        break
                elif depth == 1 and item.lower() == "value" and stream[j + 1] == "(":
                    ordinal = int(stream[j + 2])
                    value_key = (target, ordinal)
                    if value_key in values:
                        errors.append(f"duplicate enum value {target}/{ordinal}: {values[value_key]} and {relative}")
                    values[value_key] = relative
                    if kind == "enumextension" and not in_range(ordinal):
                        errors.append(f"unallocated enum value {target}/{ordinal}: {relative}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = []
    for name in ("app", "test"):
        errors.extend(f"{name}: {error}" for error in check_project(args.root / name))
    for error in errors:
        print(error)
    print(f"Build input checks: {len(errors)} error(s)")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
