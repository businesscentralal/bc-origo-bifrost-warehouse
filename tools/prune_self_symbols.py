"""Remove AL-Go's previous self-app from the actual compile cache, before the gate.

This is cache preparation, not certification. The unchanged AppSource gate must
still inventory and validate every remaining actual input before compilation.
"""
import argparse
import json
import shutil
import zipfile
from xml.etree import ElementTree as ET
from pathlib import Path
from appsource_gate import GateError, file_hash, package_info, require


def manifest_identity(path):
    # Preparation reads identity only. Full package/resource certification belongs
    # to the unchanged gate, including its separate cache/catalog budgets.
    require(path.is_file() and not path.is_symlink(), 'Missing package or linked input')
    require(40 <= path.stat().st_size <= 128 * 1024 * 1024, 'Invalid package size')
    with path.open('rb') as stream:
        header = stream.read(40)
    require(header[:4] == header[36:40] == b'NAVX', 'Invalid NAVX header')
    with zipfile.ZipFile(path) as archive:
        require(len(archive.infolist()) <= 128000, 'Identity archive entry bound exceeded')
        manifests = [entry for entry in archive.infolist() if entry.filename == 'NavxManifest.xml']
        if not manifests and 'readytorunappmanifest.json' in archive.namelist():
            return package_info(path, allow_ready_to_run=True)['identity']
        require(len(manifests) == 1, 'Missing or ambiguous NAVX manifest')
        require(manifests[0].file_size <= 256 * 1024, 'Identity manifest too large')
        manifest = ET.fromstring(archive.read(manifests[0]))
    apps = manifest.findall('{http://schemas.microsoft.com/navx/2015/manifest}App')
    require(len(apps) == 1, 'Missing or ambiguous app identity')
    return {key: apps[0].attrib[key.title()] for key in ('id', 'publisher', 'name')}


def prepare_baseline(root, project, symbols, measured, compiler_symbols):
    cop_path = project / 'AppSourceCop.json'
    if not cop_path.exists():
        return None
    cop = json.loads(cop_path.read_text(encoding='utf-8-sig'))
    keys = {key.lower(): key for key in cop}
    require(len(keys) == len(cop), 'Ambiguous analyzer configuration keys')
    version = cop.get(keys.get('version'))
    if not version:
        return None
    require(isinstance(version, str) and len(version.split('.')) == 4 and
            all(part.isdigit() for part in version.split('.')), 'Invalid baseline version')
    manifest = json.loads((project / 'app.json').read_text(encoding='utf-8-sig'))
    expected = {key: manifest[key] for key in ('id', 'publisher', 'name')}
    owned = root / '.buildartifacts' / 'AppSourceBaseline' / project.name / version
    configured = cop.get(keys.get('baselinepackagecachepath'))
    if configured and Path(configured).resolve() != owned:
        # An explicitly configured baseline is read-only to this repair.
        configured_path = Path(configured)
        if not configured_path.is_absolute():
            configured_path = project / configured_path
        require(configured_path.resolve().is_relative_to(root), 'Baseline outside owned workspace')
        candidates = [path for path in configured_path.glob('*.app')
                      if manifest_identity(path)['id'].lower() == expected['id'].lower()]
        require(any(package_info(path)['identity'] == dict(expected, version=version)
                    for path in candidates), 'Configured baseline package missing')
        return {'version': version, 'path': str(configured_path), 'existingConfigurationPreserved': True}
    for parent in [owned, *owned.parents]:
        if parent == root:
            break
        require(not parent.is_symlink(), 'Linked baseline output refused')
    owned.mkdir(parents=True, exist_ok=True)
    baseline = owned / 'Baseline.app'
    own_inputs = [(path, package_info(path)) for path, identity in measured
                  if identity['id'].lower() == expected['id'].lower()]
    selected = [(path, info) for path, info in own_inputs
                if info['identity'] == dict(expected, version=version)]
    require(selected or baseline.is_file(), 'Required upgrade baseline missing before cleanup')
    require(len({info['sha256'] for _, info in selected}) <= 1, 'Conflicting baseline bytes')

    def preserve(source, destination):
        require(not source.is_symlink() and not destination.is_symlink(), 'Linked baseline input/output')
        digest = file_hash(source)
        if destination.exists():
            require(file_hash(destination) == digest, 'Existing baseline bytes differ')
        else:
            shutil.copy2(source, destination)
        require(file_hash(destination) == digest, 'Baseline copy changed')

    if selected:
        preserve(selected[0][0], baseline)
    require(package_info(baseline)['identity'] == dict(expected, version=version), 'Wrong upgrade baseline')
    dependencies = [path for path, identity in measured if identity['id'].lower() != expected['id'].lower()]
    if compiler_symbols:
        compiler_symbols = Path(compiler_symbols)
        require(compiler_symbols.is_dir() and not compiler_symbols.is_symlink(), 'Compiler catalog missing/linked')
        dependencies += [path for path in compiler_symbols.iterdir() if path.suffix.lower() == '.app']
    require(len(dependencies) <= 384, 'Baseline dependency bound exceeded')
    for dependency in dependencies:
        preserve(dependency, owned / dependency.name)
    cop[keys.get('baselinepackagecachepath', 'baselinePackageCachePath')] = str(owned)
    # Preserve version and all analyzer rules; only separate its input cache.
    cop_path.write_text(json.dumps(cop, indent=2) + '\n', encoding='utf-8')
    return {'version': version, 'path': str(owned), 'sha256': file_hash(baseline),
            'dependencyInputs': len(dependencies), 'breakingChangeValidationRetained': True}


def prune(root, project, symbols, compiler_symbols=None):
    root = Path(root).resolve()
    project = Path(project).resolve()
    symbols = Path(symbols)
    require(project in (root / 'app', root / 'test'), 'Unknown compiling project')
    require(not symbols.is_symlink() and symbols.resolve() == root / '.packages',
            'Self-cache cleanup requires the owned workspace .packages folder')
    manifest = json.loads((project / 'app.json').read_text(encoding='utf-8-sig'))
    expected = {key: manifest[key] for key in ('id', 'publisher', 'name')}
    require(symbols.is_dir(), 'Actual symbol cache missing')
    packages = sorted(path for path in symbols.iterdir() if path.suffix.lower() == '.app')
    require(len(packages) <= 128, 'Too many cache packages')
    # Inspect every input before deleting any; malformed or linked inputs fail closed.
    measured = [(path, manifest_identity(path)) for path in packages]
    removals = []
    for path, identity in measured:
        if identity['id'].lower() != expected['id'].lower():
            continue
        require(all(identity[key] == expected[key] for key in ('publisher', 'name')),
                'Self-app ID has unexpected publisher/name')
        info = package_info(path)
        require(not path.is_symlink() and file_hash(path) == info['sha256'],
                'Self-app changed after cache inspection')
        removals.append((path, info))
    baseline = prepare_baseline(root, project, symbols, measured, compiler_symbols)
    for path, info in removals:
        path.unlink()
    return {'project': project.name, 'baseline': baseline, 'removed': [
        {'file': path.name, 'identity': info['identity'], 'sha256': info['sha256']}
        for path, info in removals]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'project', 'symbols'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--compiler-symbols')
    args = parser.parse_args()
    try:
        print(json.dumps(prune(args.root, args.project, args.symbols, args.compiler_symbols)))
    except (GateError, OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        parser.exit(1, f'Self-cache preparation failed: {error}\n')
