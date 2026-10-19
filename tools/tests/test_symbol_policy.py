"""Bounded collector/resolver fixtures, not actual runner or compiler certification."""
import copy
import importlib.util
import io
from pathlib import Path
import struct
import os
import shutil
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

SPEC = importlib.util.spec_from_file_location('gate', Path(__file__).parents[1] / 'appsource_gate.py')
G = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(G)


def fixture(path, identity=None, dependencies=(), propagate=False, content=b'symbols'):
    """Synthetic NAVX shape for resource/identity adversarial tests only."""
    identity = identity or dict(id=str(uuid.uuid4()), publisher='Microsoft', name='Collector fixture', version='29.0.1.0')
    from xml.etree import ElementTree as E
    n = '{http://schemas.microsoft.com/navx/2015/manifest}'
    root = E.Element(n + 'Package')
    E.SubElement(root, n + 'App', {k.title(): v for k, v in identity.items()} | {'PropagateDependencies': str(propagate).lower()})
    deps = E.SubElement(root, n + 'Dependencies')
    for d in dependencies:
        E.SubElement(deps, n + 'Dependency', {'Id': d['id'], 'Publisher': d['publisher'], 'Name': d['name'], 'MinVersion': d['version']})
    E.SubElement(root, n + 'InternalsVisibleTo')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('NavxManifest.xml', E.tostring(root))
        z.writestr('SymbolReference.json', content)
    header = bytearray(40)
    header[:4] = header[36:40] = b'NAVX'
    struct.pack_into('<II', header, 4, 40, 2)
    struct.pack_into('<Q', header, 28, len(output.getvalue()))
    path.write_bytes(header + output.getvalue())
    return identity


class SymbolPolicy(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog, self.cache = self.root / 'catalog', self.root / 'cache'
        self.catalog.mkdir(); self.cache.mkdir()

    def test_complete_186_catalog_with_small_cache_and_exact_resolved_additions(self):
        identities = []
        for index in range(186):
            identities.append(fixture(self.catalog / f'Microsoft-{index:03}.app'))
        catalog = G.symbol_inventory(self.catalog, 'compilerCatalog')
        self.assertEqual(186, len(catalog))
        with self.assertRaisesRegex(G.GateError, '128 packages'):
            G.symbol_inventory(self.catalog, 'appCache')
        resolution = G.resolve_helper_inputs({'dependencies': [identities[12]]}, [], catalog)
        self.assertEqual(['Microsoft-012.app'], [s['file'] for s in resolution['copies']])
        output_id = fixture(self.cache / 'Output.app', dict(id=str(uuid.uuid4()), publisher='Origo', name='Output', version='1.0.0.0'))
        import shutil
        shutil.copy2(self.catalog / 'Microsoft-012.app', self.cache / 'Microsoft-012.app')
        snapshot = {'symbolsFolder': str(self.cache.resolve()), 'compilerSymbolsFolder': str(self.catalog.resolve()),
                    'symbols': [], 'compilerSymbols': catalog, 'resolution': resolution}
        request = {'symbolsFolder': str(self.cache), 'compilerSymbolsFolder': str(self.catalog)}
        boundaries = G.reconcile_symbols(snapshot, request, G.package_info(self.cache / 'Output.app'))
        self.assertFalse(boundaries['consumedInputsCertified'])
        self.assertEqual(186, boundaries['measurements']['compilerCatalog']['packages'])
        self.assertEqual(2, boundaries['measurements']['appCache']['packages'])
        self.assertFalse(boundaries['measurements']['appCache']['runnerCapacityValidated'])
        missing_resolution = dict(snapshot)
        del missing_resolution['resolution']
        with self.assertRaisesRegex(G.GateError, 'Missing bounded dependency'):
            G.reconcile_symbols(missing_resolution, request, G.package_info(self.cache / 'Output.app'))
        fixture(self.cache / 'Injected.app')
        with self.assertRaisesRegex(G.GateError, 'Unattributed'):
            G.reconcile_symbols(snapshot, request, G.package_info(self.cache / 'Output.app'))

    def test_catalog_overflow_and_case_insensitive_duplicate_and_identity_duplicate(self):
        for index in range(257):
            (self.catalog / f'{index}.app').write_bytes(b'invalid')
        with self.assertRaisesRegex(G.GateError, '256 packages'):
            G.symbol_inventory(self.catalog, 'compilerCatalog')
        for p in self.catalog.iterdir(): p.unlink()
        identity = fixture(self.catalog / 'One.app')
        fixture(self.catalog / 'Two.app', identity)
        with self.assertRaisesRegex(G.GateError, 'Duplicate symbol identity'):
            G.symbol_inventory(self.catalog, 'compilerCatalog')
        (self.catalog / 'Two.app').unlink()
        fixture(self.catalog / 'one.APP')
        with self.assertRaisesRegex(G.GateError, 'filename collision'):
            G.symbol_inventory(self.catalog, 'compilerCatalog')

    def test_duplicate_pair_is_retained_beyond_diagnostic_cap(self):
        for index in range(130):
            fixture(self.catalog / f'A-{index:03}.app')
        first = self.catalog / 'Z-First.app'
        second = self.catalog / 'Z-Second.app'
        identity = fixture(first)
        shutil.copy2(first, second)
        with self.assertRaisesRegex(G.GateError, 'Duplicate symbol identity/version') as caught:
            G.symbol_inventory(self.catalog, 'compilerCatalog')
        self.assertEqual((first, second), caught.exception.rejected_packages)
        output = self.root / 'rejected.json'
        G.rejected_receipt(output, {}, folders={'compilerSymbolsFolder': self.catalog},
                           offending_paths=caught.exception.rejected_packages)
        import json
        receipt = json.loads(output.read_text())
        pair = [item for item in receipt['inputs'] if item.get('triggeredRejection')]
        self.assertEqual({str(first), str(second)}, {item['path'] for item in pair})
        self.assertTrue(all(item['identity'] == identity for item in pair))
        self.assertTrue(all(item['sha256'] == G.file_hash(first) for item in pair))
        self.assertTrue(receipt['truncated'])
        self.assertFalse(receipt['accepted'])
        self.assertEqual(128, len(receipt['inputs']))
        self.assertTrue(first.exists() and second.exists())

    def test_aggregate_disk_expansion_manifest_entry_and_time_bounds(self):
        fixture(self.catalog / 'One.app', content=b'A' * 10000)
        size = (self.catalog / 'One.app').stat().st_size
        with patch.dict(G.SYMBOL_POLICIES, {'compilerCatalog': {'packages': 256, 'bytes': size - 1}}):
            with self.assertRaisesRegex(G.GateError, 'aggregate-byte'):
                G.symbol_inventory(self.catalog, 'compilerCatalog')
        with patch.dict(G.SYMBOL_POLICIES, {'compilerCatalog': {'packages': 256, 'bytes': size + 1}}):
            with self.assertRaisesRegex(G.GateError, 'aggregate expanded'):
                G.symbol_inventory(self.catalog, 'compilerCatalog')
        for constant, value, error in [('PACKAGE_BYTES', size - 1, '128 MiB'), ('PACKAGE_BYTES', size + 1, 'expanded-byte'),
                                        ('MANIFEST_BYTES', 1, 'Manifest'), ('PACKAGE_ENTRIES', 1, 'entry bound')]:
            with patch.object(G, constant, value), self.assertRaisesRegex(G.GateError, error):
                G.package_info(self.catalog / 'One.app')
        with patch.object(G, 'INVENTORY_SECONDS', -1), self.assertRaisesRegex(G.GateError, 'elapsed budget'):
            G.symbol_inventory(self.catalog, 'compilerCatalog')

    def test_catalog_and_cache_have_distinct_finite_elapsed_limits(self):
        path = self.catalog / 'One.app'
        fixture(path)
        original = G.package_info
        observed = []
        def measure(p, deadline=None, **kwargs):
            observed.append(deadline)
            return original(p, deadline, **kwargs)
        with patch.object(G.time, 'monotonic', return_value=0), patch.object(G, 'package_info', side_effect=measure):
            catalog = G.symbol_inventory(self.catalog, 'compilerCatalog')
        self.assertEqual([G.INVENTORY_SECONDS], observed)
        self.assertEqual(G.COMPILER_CATALOG_SECONDS, G.inventory_measurement(catalog, 'compilerCatalog')['elapsedBudgetSeconds'])
        self.assertEqual(G.INVENTORY_SECONDS, G.inventory_measurement(catalog, 'compilerCatalog')['packageElapsedBudgetSeconds'])
        with patch.object(G.time, 'monotonic', side_effect=[0, G.COMPILER_CATALOG_SECONDS + 1]), self.assertRaisesRegex(G.GateError, 'elapsed budget'):
            G.symbol_inventory(self.catalog, 'compilerCatalog')
        with patch.object(G.time, 'monotonic', side_effect=[0, G.INVENTORY_SECONDS + 1]), self.assertRaisesRegex(G.GateError, 'elapsed budget'):
            G.symbol_inventory(self.catalog, 'appCache')

    def test_single_package_keeps_its_60_second_limit_inside_catalog(self):
        fixture(self.catalog / 'One.app')
        clock = [0]
        original = G.package_info
        def slow_package(path, deadline=None, **kwargs):
            clock[0] = G.INVENTORY_SECONDS + 1
            return original(path, deadline, **kwargs)
        with patch.object(G.time, 'monotonic', side_effect=lambda: clock[0]), patch.object(G, 'package_info', side_effect=slow_package):
            with self.assertRaisesRegex(G.GateError, 'elapsed budget'):
                G.symbol_inventory(self.catalog, 'compilerCatalog')
        self.assertLess(clock[0], G.COMPILER_CATALOG_SECONDS)

    def test_normalization_preserves_catalog_expanded_work_bound(self):
        path = self.catalog / 'One.app'
        fixture(path)
        info = G.package_info(path)
        with patch.dict(G.SYMBOL_POLICIES, {'compilerCatalog': {'packages': 256, 'bytes': info['bytes'] + 1, 'expandedBytes': info['expandedBytes'] - 1}}):
            with self.assertRaisesRegex(G.GateError, 'aggregate expanded'):
                G.collapse_equivalent_compiler_symbols(self.catalog)
        self.assertTrue(path.exists())

    def test_streams_bounded_reads_and_detects_mid_measurement_mutation(self):
        path = self.catalog / 'One.app'
        fixture(path, content=b'A' * (2 * G.CHUNK_BYTES + 10))
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('unbounded whole-file read')):
            self.assertTrue(G.package_info(path)['sha256'])
        original = G.file_hash
        count = 0
        def mutate(p, deadline=None):
            nonlocal count
            count += 1
            if count == 2:
                with path.open('ab') as f: f.write(b'mutation')
            return original(p, deadline)
        with patch.object(G, 'file_hash', side_effect=mutate), self.assertRaisesRegex(G.GateError, 'changed during'):
            G.package_info(path)

    def test_header_truncated_duplicate_and_wrong_version_negatives(self):
        path = self.catalog / 'One.app'
        fixture(path)
        data = path.read_bytes()
        path.write_bytes(data[:-10])
        with self.assertRaises(G.GateError): G.package_info(path)
        fixture(path, dict(id=str(uuid.uuid4()), publisher='Microsoft', name='WrongVersion', version='bad'))
        with self.assertRaisesRegex(G.GateError, 'version'): G.package_info(path)

    def test_existing_highest_and_all_compatible_catalog_versions(self):
        dep = fixture(self.catalog / 'v1.app')
        fixture(self.catalog / 'v2.app', dep | {'version': '30.0.0.0'})
        catalog = G.symbol_inventory(self.catalog, 'compilerCatalog')
        r = G.resolve_helper_inputs({'dependencies': [dep]}, [], catalog)
        self.assertEqual({'v1.app', 'v2.app'}, {s['file'] for s in r['copies']})
        r = G.resolve_helper_inputs({'dependencies': [dep]}, catalog, catalog)
        self.assertEqual([], r['copies'])
        self.assertEqual('v2.app', r['trace'][0]['selected'][0]['file'])
        for d in (dep | {'publisher': 'Injected'}, dep | {'name': 'Wrong'}, dep | {'version': '31.0.0.0'}):
            with self.assertRaises(G.GateError): G.resolve_helper_inputs({'dependencies': [d]}, [], catalog)

    def test_implicit_application_system_and_propagated_transitive_roots(self):
        child = fixture(self.catalog / 'child.app')
        application = fixture(self.catalog / 'Application.app', dict(id='c1335042-3002-4257-bf8a-75c898ccb1b8', publisher='Microsoft', name='Application', version='29.0.0.0'), [child], True)
        system = fixture(self.catalog / 'System.app', dict(id='8874ed3a-0643-4247-9ced-7a7002f7135d', publisher='Microsoft', name='System', version='29.0.0.0'))
        catalog = G.symbol_inventory(self.catalog, 'compilerCatalog')
        existing = [i for i in catalog if i['identity'] == application]
        r = G.resolve_helper_inputs({'application': '28.0.0.0', 'platform': '28.0.0.0'}, existing, catalog)
        self.assertEqual({'child.app', 'System.app'}, {i['file'] for i in r['copies']})
        for missing in ('Application.app', 'System.app', 'child.app'):
            reduced = [i for i in catalog if i['file'] != missing]
            with self.subTest(missing=missing), self.assertRaises(G.GateError):
                G.resolve_helper_inputs({'application': '28.0.0.0', 'platform': '28.0.0.0'}, [], reduced)

    def test_resolved_cache_cannot_omit_preexisting_inputs_or_exceed_bound(self):
        for index in range(128): fixture(self.cache / f'existing-{index}.app')
        dep = fixture(self.catalog / 'New.app')
        with self.assertRaisesRegex(G.GateError, 'Resolved app cache package'):
            G.resolve_helper_inputs({'dependencies': [dep]}, G.symbol_inventory(self.cache), G.symbol_inventory(self.catalog, 'compilerCatalog'))

    def test_genuine_measured_base_profile_and_changed_hash_cannot_inherit_exception(self):
        path = Path(os.environ['APPSOURCE_GATE_BASE29'])
        info = G.package_info(path)
        self.assertEqual('10ebba923b6f8d3b6d676cc1f1db16a8a5d4519ff8ca4f45bbd2e778b52d289c', info['sha256'])
        self.assertEqual(info['sha256'], info['resourceProfile'])
        self.assertEqual(8665, info['entryCount'])
        self.assertEqual(379592378, info['expandedBytes'])
        self.assertEqual(G.MEASURED_PACKAGE_PROFILES[info['sha256']]['identity'], info['identity'])
        changed = self.root / 'changed-base.app'
        shutil.copyfile(path, changed)
        with changed.open('ab') as output: output.write(b'changed-signature-tail')
        with self.assertRaisesRegex(G.GateError, 'entry bound'):
            G.package_info(changed)
        # The hash exception also requires every exact manifest identity field.
        # Mutating the profile exercises that second guard using genuine bytes;
        # changing package bytes instead would stop at the generic entry bound.
        for key, value in [('id', str(uuid.uuid4())), ('version', '29.0.54011.55936'),
                           ('publisher', 'Other'), ('name', 'Other Application')]:
            profile = copy.deepcopy(G.MEASURED_PACKAGE_PROFILES[info['sha256']])
            profile['identity'][key] = value
            with self.subTest(identityField=key), patch.dict(G.MEASURED_PACKAGE_PROFILES, {info['sha256']: profile}):
                with self.assertRaisesRegex(G.GateError, 'Measured package profile identity mismatch'):
                    G.package_info(path)
        # Profile entry/expansion ceilings remain independently enforced.
        for key, maximum, message in [('maxEntries', 8664, 'entry bound'),
                                      ('maxExpandedBytes', 379592377, 'expanded-byte')]:
            profile = copy.deepcopy(G.MEASURED_PACKAGE_PROFILES[info['sha256']])
            profile[key] = maximum
            with patch.dict(G.MEASURED_PACKAGE_PROFILES, {info['sha256']: profile}):
                with self.assertRaisesRegex(G.GateError, message): G.package_info(path)

    def test_genuine_foundation530_candidate_and_wrong_hash_source_version_friend_tail(self):
        path = Path(os.environ['APPSOURCE_GATE_FOUNDATION530'])
        info = G.package_info(path)
        receipt = G.check_foundation_candidate(info)
        self.assertFalse(receipt['signatureTrustVerified'])
        self.assertFalse(receipt['runnerInputEqualityVerified'])
        for key, value in [('sha256', '0' * 64), ('sourceCommit', '0' * 40),
                           ('buildUrl', 'https://example.invalid'), ('compilerVersion', 'wrong'),
                           ('friends', [{'id': '9db1a0c9-c503-4793-a9e4-bcda3d3f3c94', 'publisher': 'Origo', 'name': 'Bifrost Foundation - Tests'}]),
                           ('signatureTailBytes', 0)]:
            changed = copy.deepcopy(info)
            changed[key] = value
            with self.subTest(key=key), self.assertRaises(G.GateError): G.check_foundation_candidate(changed)
        for key, value in [('id', str(uuid.uuid4())), ('version', '28.0.3.531'),
                           ('publisher', 'Other'), ('name', 'Other Foundation')]:
            changed = copy.deepcopy(info)
            changed['identity'][key] = value
            with self.subTest(identityField=key), self.assertRaisesRegex(G.GateError, 'identity'):
                G.check_foundation_candidate(changed)


if __name__ == '__main__': unittest.main()
