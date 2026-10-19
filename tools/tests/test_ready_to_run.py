"""ReadyToRun inventory metadata regressions; no compiler/runtime/signature certification."""
import importlib.util, pathlib, unittest, tempfile, json, zipfile, struct, io, hashlib
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('policy',ROOT/'test_symbol_policy.py');P=importlib.util.module_from_spec(spec);spec.loader.exec_module(P);G=P.G
import os
def wrap(path, inner, identity, *, override=None, extra=(), raw=None):
 meta={"EmbeddedApp"+k.title():v for k,v in identity.items()};meta['EmbeddedAppFileName']='inner.app';meta.update(override or {})
 payload=io.BytesIO()
 with zipfile.ZipFile(payload,'w',zipfile.ZIP_DEFLATED) as z:
  z.writestr('readytorunappmanifest.json',raw or json.dumps(meta));z.writestr('inner.app',inner)
  for name,content in extra:z.writestr(name,content)
 header=bytearray(40);header[:4]=header[36:40]=b'NAVX';struct.pack_into('<II',header,4,40,2);struct.pack_into('<Q',header,28,len(payload.getvalue()));path.write_bytes(header+payload.getvalue())
class ReadyToRun(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name);self.inner=self.root/'source.app';self.identity=P.fixture(self.inner);self.outer=self.root/'wrapper.app';wrap(self.outer,self.inner.read_bytes(),self.identity)
 def test_valid_and_outer_evidence(self):
  info=G.package_info(self.outer,allow_ready_to_run=True);plain=G.package_info(self.inner)
  self.assertEqual(self.identity,info['identity']);self.assertEqual(hashlib.sha256(self.outer.read_bytes()).hexdigest(),info['sha256']);self.assertEqual(plain['sha256'],info['readyToRun']['embeddedSha256']);self.assertGreater(info['expandedBytes'],plain['expandedBytes']);self.assertFalse(info['readyToRun']['signatureTrustVerified'])
 def test_separate_disk_and_expanded_inventory_budgets(self):
  catalog=self.root/'catalog';catalog.mkdir();(catalog/'wrapper.app').write_bytes(self.outer.read_bytes())
  info=G.package_info(self.outer,allow_ready_to_run=True)
  policy={'packages':256,'bytes':self.outer.stat().st_size+1,'expandedBytes':info['expandedBytes']}
  with patch.dict(G.SYMBOL_POLICIES,{'compilerCatalog':policy}):
   self.assertEqual(1,len(G.symbol_inventory(catalog,'compilerCatalog')))
  policy['expandedBytes']-=1
  with patch.dict(G.SYMBOL_POLICIES,{'compilerCatalog':policy}):
   with self.assertRaisesRegex(G.GateError,'aggregate expanded'):G.symbol_inventory(catalog,'compilerCatalog')
 def test_shipping_still_refuses_wrapper(self):
  with self.assertRaisesRegex(G.GateError,'NAVX manifest'):G.package_info(self.outer)
 def test_mismatched_identity(self):
  wrap(self.outer,self.inner.read_bytes(),self.identity,override={'EmbeddedAppPublisher':'Injected'})
  with self.assertRaisesRegex(G.GateError,'identity mismatch'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_ambiguous_inner(self):
  wrap(self.outer,self.inner.read_bytes(),self.identity,extra=[('second.app',self.inner.read_bytes())])
  with self.assertRaisesRegex(G.GateError,'ambiguous'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_duplicate_entry(self):
  wrap(self.outer,self.inner.read_bytes(),self.identity,extra=[('inner.app',b'injected')])
  with self.assertRaisesRegex(G.GateError,'Duplicate package'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_mixed_outer_manifests_refused(self):
  wrap(self.outer,self.inner.read_bytes(),self.identity,extra=[('NavxManifest.xml',b'<injected/>')])
  for allowed in (False,True):
   with self.subTest(allowed=allowed),self.assertRaisesRegex(G.GateError,'Ambiguous NAVX/ReadyToRun'):
    G.package_info(self.outer,allow_ready_to_run=allowed)
 def test_duplicate_json_key(self):
  wrap(self.outer,self.inner.read_bytes(),self.identity,raw='{"EmbeddedAppId":"one","EmbeddedAppId":"two"}')
  with self.assertRaisesRegex(G.GateError,'Duplicate ReadyToRun'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_path_injection(self):
  for name in ('../inner.app','a/inner.app',r'a\inner.app','C:inner.app'):
   with self.subTest(name=name):
    wrap(self.outer,self.inner.read_bytes(),self.identity,override={'EmbeddedAppFileName':name})
    with self.assertRaisesRegex(G.GateError,'filename'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_invalid_inner(self):
  wrap(self.outer,b'malformed',self.identity)
  with self.assertRaises(G.GateError):G.package_info(self.outer,allow_ready_to_run=True)
 def test_nested_wrapper_refused(self):
  original=self.outer.read_bytes();wrap(self.outer,original,self.identity)
  with self.assertRaisesRegex(G.GateError,'NAVX manifest'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_expansion_and_manifest_bounds(self):
  with patch.object(G,'MANIFEST_BYTES',8):
   with self.assertRaisesRegex(G.GateError,'16 MiB'):G.package_info(self.outer,allow_ready_to_run=True)
  wrap(self.outer,self.inner.read_bytes(),self.identity,extra=[('payload.bin',b'A'*10000)])
  with patch.object(G,'PACKAGE_BYTES',self.outer.stat().st_size+1):
   with self.assertRaisesRegex(G.GateError,'expanded-byte'):G.package_info(self.outer,allow_ready_to_run=True)
 def test_missing_manifest_not_waived(self):
  broken=self.inner.read_bytes().replace(b'NavxManifest.xml',b'OtherNoManifestx')
  self.outer.write_bytes(broken)
  with self.assertRaises(G.GateError):G.package_info(self.outer,allow_ready_to_run=True)
 def test_genuine_any(self):
  p=pathlib.Path(os.environ['APPSOURCE_GATE_READYTORUN_ANY']);info=G.package_info(p,allow_ready_to_run=True)
  expected=G.package_info(pathlib.Path(os.environ['APPSOURCE_GATE_EMBEDDED_ANY']))
  self.assertEqual(expected['sha256'],info['readyToRun']['embeddedSha256']);self.assertEqual(expected['identity'],info['identity'])
 def test_genuine_base(self):
  p=pathlib.Path(os.environ['APPSOURCE_GATE_READYTORUN_BASE29']);info=G.package_info(p,allow_ready_to_run=True)
  self.assertEqual('10ebba923b6f8d3b6d676cc1f1db16a8a5d4519ff8ca4f45bbd2e778b52d289c',info['readyToRun']['embeddedSha256']);self.assertEqual(8665,info['readyToRun']['embeddedEntryCount'])
if __name__=='__main__':unittest.main(verbosity=2)
