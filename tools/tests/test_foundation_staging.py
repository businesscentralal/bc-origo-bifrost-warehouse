"""Real approved/colliding artifact bytes; tooling tests, not runner/trust proof."""
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]))
import stage_foundation_inputs as S
import appsource_gate as G


class Staging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.input_dir = Path(os.environ['FOUNDATION_STAGING_ARTIFACTS'])
        cls.fixtures = Path(os.environ['APPSOURCE_GATE_FIXTURES'])
        cls.archives = {'Apps': cls.input_dir / 'foundation-ci-apps523.zip',
                        'TestApps': cls.input_dir / 'foundation-ci-test523.zip'}
        for kind, path in cls.archives.items():
            if G.file_hash(path) != S.ARTIFACTS[kind][1]:
                raise AssertionError('Genuine pinned artifact missing/changed')
        for name in ('default', 'testApp'):
            G.package_info(cls.fixtures / (name + '.app'))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.context = dict(run='1234', attempt='2', sourceCommit='3' * 40, checkoutSha='4' * 40, mode='Default')
        self.request = dict(profile='controlled523', context=self.context, artifacts={kind: dict(archive=str(path), provenance=dict(
            repository='OrigoSoftwareSolutions/bc-origo-bifrost-core', sourceSha=S.SOURCE, run=S.RUN,
            attempt=2, artifactId=S.ARTIFACTS[kind][0], archiveSha256=S.ARTIFACTS[kind][1],
            expired=False, conclusion='success')) for kind, path in self.archives.items()},
            otherApps=[str(self.fixtures / 'default.app')], otherTestApps=[str(self.fixtures / 'testApp.app')])
        dependencies = self.root / 'dependencies'
        dependencies.mkdir()
        for name in ('default', 'testApp'):
            shutil.copyfile(self.fixtures / (name + '.app'), dependencies / (name + '.app'))
        self.request['otherApps'] = [str(dependencies / 'default.app')]
        self.request['otherTestApps'] = [str(dependencies / 'testApp.app')]
        self.dependencies = dependencies
        self.destination = self.root / 'stage'

    def stage(self):
        arrays = S.stage(self.request, self.destination)
        return arrays, json.loads((self.destination / 'selection.json').read_text())

    def test_both_download_orders_and_modes_preserve_signed_pin_and_genuine_dependencies(self):
        for mode in ('Default', 'Test'):
            for order in (['Apps', 'TestApps'], ['TestApps', 'Apps']):
                with self.subTest(mode=mode, order=order):
                    shared = self.root / ('legacy-' + mode + order[0])
                    shared.mkdir()
                    for kind in order:
                        with zipfile.ZipFile(self.archives[kind]) as z:
                            z.extractall(shared)
                    legacy = G.package_info(next(shared.glob('*.app')))
                    self.assertEqual(S.PIN if order[-1] == 'Apps' else S.TEST_PIN, legacy['sha256'])
                    self.request['context']['mode'] = mode
                    self.request['artifacts'] = {kind: self.request['artifacts'][kind] for kind in order}
                    self.destination = self.root / (mode + order[0])
                    arrays, receipt = self.stage()
                    self.assertEqual(2, len(arrays['installApps']))
                    self.assertEqual([str((self.dependencies / 'testApp.app').resolve())], arrays['installTestApps'])
                    self.assertEqual(S.PIN, next(x for x in receipt['selection']['after']['installApps'] if x['identity']['id'] == S.FOUNDATION)['sha256'])
                    self.assertEqual(S.TEST_PIN, receipt['selection']['excluded'][0]['sha256'])
                    self.assertFalse(receipt['signatureTrustVerified'])
                    S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays))

    def validate_args(self, arrays):
        return dict(install_apps=arrays['installApps'], install_tests=arrays['installTestApps'])

    def test_all_source_artifact_provenance_negative_fields(self):
        for kind in S.ARTIFACTS:
            for key, value in [('sourceSha','f'*40), ('run',1), ('attempt',1), ('artifactId',1),
                               ('expired',True), ('conclusion','failure'), ('repository','wrong/repo'), ('archiveSha256','0'*64)]:
                request = copy.deepcopy(self.request)
                request['artifacts'][kind]['provenance'][key] = value
                with self.subTest(kind=kind, key=key), self.assertRaises(G.GateError):
                    S.stage(request, self.destination)
                self.assertFalse(self.destination.exists())

    def test_missing_and_changed_archive(self):
        for value in (self.root / 'absent.zip', self.root / 'changed.zip'):
            if value.name == 'changed.zip': value.write_bytes(self.archives['Apps'].read_bytes() + b'changed')
            self.request['artifacts']['Apps']['archive'] = str(value)
            with self.assertRaises(G.GateError): self.stage()

    def test_missing_unknown_artifact_and_mode(self):
        request = copy.deepcopy(self.request)
        del request['artifacts']['TestApps']
        with self.assertRaises(G.GateError): S.stage(request, self.destination)
        self.context['mode'] = 'Unknown'
        with self.assertRaises(G.GateError): self.stage()

    def test_duplicate_apps_candidate(self):
        _, receipt = self.stage()
        paths = [x['path'] for x in receipt['selection']['before']['installApps']]
        tests = [x['path'] for x in receipt['selection']['before']['installTestApps']]
        with self.assertRaisesRegex(G.GateError, 'duplicate Apps'): S.select(paths + [paths[0]], tests)

    def test_missing_testapps_collision_and_duplicate_collision(self):
        _, receipt = self.stage()
        paths = [x['path'] for x in receipt['selection']['before']['installApps']]
        tests = [x['path'] for x in receipt['selection']['before']['installTestApps']]
        collision = receipt['selection']['excluded'][0]['path']
        for value in ([x for x in tests if x != collision], tests + [collision]):
            with self.assertRaisesRegex(G.GateError, 'TestApps Foundation'): S.select(paths, value)

    def test_wrong_testapps_bytes_and_apps_friend_bearing_bytes(self):
        _, receipt = self.stage()
        paths = [x['path'] for x in receipt['selection']['before']['installApps']]
        tests = [x['path'] for x in receipt['selection']['before']['installTestApps']]
        approved = next(x for x in paths if G.package_info(x)['identity']['id'] == S.FOUNDATION)
        collision = receipt['selection']['excluded'][0]['path']
        original = Path(collision).read_bytes()
        shutil.copyfile(approved, collision)
        with self.assertRaisesRegex(G.GateError, 'Unrecognized'): S.select(paths, tests)
        Path(collision).write_bytes(original)
        shutil.copyfile(collision, approved)
        with self.assertRaisesRegex(G.GateError, 'Unapproved'): S.select(paths, tests)

    def test_genuine_wrong_identity_and_remaining_duplicate(self):
        _, receipt = self.stage()
        paths = [x['path'] for x in receipt['selection']['before']['installApps']]
        tests = [x['path'] for x in receipt['selection']['before']['installTestApps']]
        with self.assertRaisesRegex(G.GateError, 'Duplicate remaining helper AppId'): S.select(paths, tests + [str(self.dependencies / 'default.app')])
        foundation = next(x for x in paths if G.package_info(x)['identity']['id'] == S.FOUNDATION)
        shutil.copyfile(self.fixtures / 'default.app', foundation)
        with self.assertRaises(G.GateError): S.select(paths, tests)
        with self.assertRaises(G.GateError): S.select(paths, tests + [str(self.dependencies / 'default.app')])

    def test_parenthesized_test_library_keeps_helper_skip_run_policy(self):
        self.request['otherTestApps'] = ['(' + str(self.dependencies / 'testApp.app') + ')']
        arrays, receipt = self.stage()
        self.assertEqual(['(' + str((self.dependencies / 'testApp.app').resolve()) + ')'], arrays['installTestApps'])
        S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays))
        self.assertEqual(1, len(receipt['selection']['after']['installTestApps']))

    def test_later_array_substitution_omission_and_reordering(self):
        arrays, receipt = self.stage()
        for apps in (arrays['installApps'][:-1], arrays['installApps'][::-1], [receipt['selection']['excluded'][0]['path']] + arrays['installApps'][1:]):
            with self.assertRaises(G.GateError): S.validate(self.destination / 'selection.json', self.context, apps, arrays['installTestApps'])

    def test_later_package_mutation_and_symbol_substitution(self):
        arrays, receipt = self.stage()
        collision = receipt['selection']['excluded'][0]['path']
        with self.assertRaises(G.GateError): S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays), symbols=[collision])
        S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays), symbols=arrays['installApps'])
        Path(arrays['installApps'][0]).write_bytes(Path(arrays['installApps'][0]).read_bytes() + b'changed')
        with self.assertRaises(G.GateError): S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays))

    def test_mutation_fixtures_cannot_change_retained_compiler_packages(self):
        original = G.file_hash(self.fixtures / 'default.app')
        arrays, receipt = self.stage()
        Path(arrays['installApps'][0]).write_bytes(b'negative-case')
        with self.assertRaises(G.GateError):
            S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays))
        self.assertEqual(original, G.file_hash(self.fixtures / 'default.app'))

    def test_missing_stale_and_mutated_receipt(self):
        with self.assertRaises(G.GateError): S.validate(self.destination / 'selection.json', self.context, [], [])
        arrays, receipt = self.stage()
        for key, value in [('run','999'), ('attempt','3'), ('sourceCommit','f'*40), ('checkoutSha','e'*40), ('mode','Test')]:
            context = {**self.context, key:value}
            with self.subTest(key=key), self.assertRaises(G.GateError):
                S.validate(self.destination / 'selection.json', context, **self.validate_args(arrays))
        receipt['selection']['after']['installTestApps'] = []
        (self.destination / 'selection.json').write_text(json.dumps(receipt))
        with self.assertRaises(G.GateError): S.validate(self.destination / 'selection.json', self.context, **self.validate_args(arrays))

    def test_existing_stage_is_not_deleted(self):
        self.stage()
        before = (self.destination / 'selection.json').read_bytes()
        with self.assertRaises(G.GateError): self.stage()
        self.assertEqual(before, (self.destination / 'selection.json').read_bytes())

    def test_bounded_paths_counts_and_nonlocal_input_fail_closed(self):
        for paths in (['https://example.invalid/token.app'], ['*.app'], [str(self.fixtures / 'testApp.app')] * 129):
            with self.assertRaises(G.GateError): S.inspect(paths)
        symlink = self.root / 'linked.app'; symlink.symlink_to(self.fixtures / 'default.app')
        with self.assertRaises(G.GateError): S.inspect([symlink])

    def test_archive_traversal_and_duplicate_layout_refused(self):
        for names in (['../bad.app'], ['bad.app','bad.app'], ['folder/bad.app']):
            archive = self.root / 'bad.zip'
            with zipfile.ZipFile(archive,'w') as z:
                for index, name in enumerate(names):
                    if index and name in names[:index]:
                        with self.assertWarnsRegex(UserWarning, 'Duplicate name'): z.writestr(name,b'bad')
                    else: z.writestr(name,b'bad')
            with self.assertRaises(G.GateError): S.extract_archive(archive,self.root)

    def test_rejected_receipt_is_allowlisted_and_preserves_actual_disk_hash(self):
        _, receipt = self.stage()
        output = self.root / 'rejected.json'
        collision = receipt['selection']['excluded'][0]['path']
        G.rejected_receipt(output, {**self.context, 'Settings': {'password':'do-not-emit'}, 'credential':'do-not-emit'}, [collision])
        text = output.read_text(); self.assertNotIn('do-not-emit',text)
        data = json.loads(text)
        self.assertFalse(data['accepted']); self.assertEqual(S.TEST_PIN,data['inputs'][0]['sha256'])
        self.assertEqual([S.TEST_FRIEND],data['inputs'][0]['friends'])
        self.assertEqual(S.SOURCE,data['inputs'][0]['sourceCommit'])

    def test_original_beforecompile_failure_retains_receipt(self):
        arrays, receipt = self.stage()
        (self.root / 'app').mkdir(); (self.root / 'test').mkdir()
        for folder, fixture in [('app','default'),('test','testApp')]:
            shutil.copyfile(self.fixtures / fixture / 'app.json',self.root / folder / 'app.json')
        directory = self.root / '.buildartifacts/AppSourceGate/Default'; directory.mkdir(parents=True)
        (directory / 'state.json').write_text(json.dumps(dict(context=self.context, receipts={})))
        symbols = self.root / 'symbols'; symbols.mkdir()
        shutil.copyfile(receipt['selection']['excluded'][0]['path'],symbols / 'Foundation.app')
        compiler_symbols = self.root/'compiler-symbols'
        compiler_symbols.mkdir()
        request = dict(context=self.context, manifest=str(self.root/'app/app.json'), symbolsFolder=str(symbols), compilerSymbolsFolder=str(compiler_symbols), kind='fixture')
        with self.assertRaisesRegex(G.GateError,'(?i)unapproved Foundation'): G.before_compile(self.root,request)
        rejected=json.loads((directory/'rejected-input.json').read_text())
        self.assertEqual(S.TEST_PIN,rejected['inputs'][0]['sha256'])

    def test_cli_rejection_nonzero_and_no_secret_console_dump(self):
        self.request['artifacts']['Apps']['provenance']['expired'] = True
        self.request['Settings'] = {'password':'do-not-emit'}
        request_path = self.root / 'request.json'; request_path.write_text(json.dumps(self.request))
        result = subprocess.run([sys.executable,S.__file__,'stage','--input',str(request_path),'--destination',str(self.destination)],capture_output=True,text=True)
        self.assertEqual(1,result.returncode); self.assertNotIn('do-not-emit',result.stdout+result.stderr)
        self.assertTrue((self.root/'stage-rejected.json').exists())


class Candidate530(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = S.PROFILES['candidate530']
        inputs = Path(os.environ['FOUNDATION_CANDIDATE_ARTIFACTS'])
        context = dict(run='1234', attempt='1', sourceCommit='3' * 40, checkoutSha='4' * 40, mode='Default')
        artifacts = {}
        for kind, (artifact, sha) in self.config['artifacts'].items():
            archive = inputs / f'foundation530-{artifact}.zip'
            self.assertEqual(sha, G.file_hash(archive))
            artifacts[kind] = dict(archive=str(archive), provenance=dict(repository='OrigoSoftwareSolutions/bc-origo-bifrost-core',
                sourceSha=self.config['source'], run=self.config['run'], attempt=self.config['attempt'],
                artifactId=artifact, archiveSha256=sha, expired=False, conclusion='success'))
        # Default production staging profile is candidate530.523is only explicit controlled fixture.
        self.request = dict(context=context, artifacts=artifacts)

    def test_actual_candidate_staging_retains_signed_apps_and_excludes_only_exact_test_collision(self):
        arrays = S.stage(self.request, self.root / 'stage')
        self.assertEqual(1, len(arrays['installApps']))
        self.assertEqual([], arrays['installTestApps'])
        info = G.package_info(arrays['installApps'][0])
        G.check_foundation_candidate(info)
        receipt = S.validate(self.root / 'stage/selection.json', self.request['context'], arrays['installApps'], arrays['installTestApps'])
        self.assertEqual('candidate530', receipt['profile'])
        self.assertFalse(receipt['signatureTrustVerified'])
        self.assertEqual(self.config['testPin'], receipt['selection']['excluded'][0]['sha256'])
        self.assertEqual([S.TEST_FRIEND], receipt['selection']['excluded'][0]['friends'])

    def test_wrong_candidate_source_archive_swap_and_wrong_profile_fail_closed(self):
        for change in ('source', 'swap', 'profile'):
            request = copy.deepcopy(self.request)
            if change == 'source': request['artifacts']['Apps']['provenance']['sourceSha'] = '0' * 40
            elif change == 'swap': request['artifacts']['Apps']['archive'] = request['artifacts']['TestApps']['archive']
            else: request['profile'] = 'controlled523'
            with self.subTest(change=change), self.assertRaises(G.GateError): S.stage(request, self.root / change)
            self.assertFalse((self.root / change).exists())

    def test_test_candidate_cannot_be_swapped_into_apps_or_mutated_after_staging(self):
        arrays = S.stage(self.request, self.root / 'stage')
        excluded = json.loads((self.root / 'stage/selection.json').read_text())['selection']['excluded'][0]['path']
        with self.assertRaises(G.GateError): S.select([excluded], [excluded], 'candidate530')
        with open(arrays['installApps'][0], 'ab') as out: out.write(b'mutated-tail')
        with self.assertRaises(G.GateError):
            S.validate(self.root / 'stage/selection.json', self.request['context'], arrays['installApps'], arrays['installTestApps'])


if __name__ == '__main__': unittest.main()
