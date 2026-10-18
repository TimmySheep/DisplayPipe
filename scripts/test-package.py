#!/usr/bin/env python3
"""Actual packaged artifact checks; no GUI launch and no possible native setter call."""
import hashlib, json, os, pathlib, shutil, struct, subprocess, sys, unittest, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
APP=pathlib.Path(os.environ.get('DISPLAYPIPE_TEST_APP',str(ROOT/'.build/DisplayPipe.app')))
class Package(unittest.TestCase):
 def test_bundle_resources(self):
  for rel in ['backend/recovery.py','backend/displaypipe.py','backend/build/DisplayPipeIO','backend/edid-core/target/release/displaypipe-edid','docs/USER_GUIDE.md','licenses/pipecap-MIT.txt','licenses/edid-core-MIT.txt','python-path.txt','DisplayPipe.icns']:
   self.assertTrue((APP/'Contents/Resources'/rel).is_file(),rel)
 def test_runtime_only_manifest(self):
  resources=APP/'Contents/Resources'
  self.assertFalse((resources/'scripts').exists(),'build and test scripts are not runtime resources')
  self.assertFalse((resources/'backend/DisplayPipeIO.m').exists(),'native source is not a runtime resource')
  manifest=json.loads((resources/'MANIFEST.sha256.json').read_text())
  actual={str(p.relative_to(resources)):hashlib.sha256(p.read_bytes()).hexdigest() for p in resources.rglob('*') if p.is_file() and p.name!='MANIFEST.sha256.json'}
  self.assertEqual(manifest,actual,'manifest must enumerate and hash every shipped runtime resource exactly')
  self.assertEqual(set(actual),{'backend/displaypipe.py','backend/recovery.py','backend/build/DisplayPipeIO','backend/edid-core/target/release/displaypipe-edid','docs/USER_GUIDE.md','docs/UPSTREAM.md','licenses/pipecap-MIT.txt','licenses/edid-core-MIT.txt','licenses/NOTICE.txt','python-path.txt','DisplayPipe.icns'})
 def test_existing_python_explicit_dependency(self):
  python=(APP/'Contents/Resources/python-path.txt').read_text().strip()
  self.assertTrue(pathlib.Path(python).is_absolute())
  subprocess.run([python,'-B','-c','import sys,argparse,fcntl,hashlib,json,pathlib,subprocess; assert sys.version_info >= (3,9); print(sys.executable,sys.version.split()[0])'],check=True)
 def test_real_icon_and_bundle_metadata(self):
  info=json.loads(subprocess.check_output(['/usr/bin/plutil','-convert','json','-o','-',str(APP/'Contents/Info.plist')]))
  self.assertEqual(info.get('CFBundleIconFile'),'DisplayPipe.icns')
  icon=APP/'Contents/Resources/DisplayPipe.icns'; self.assertGreater(icon.stat().st_size,1000)
  output=ROOT/'.build'/('validated-icon-'+uuid.uuid4().hex+'.iconset')
  subprocess.run(['/usr/bin/iconutil','-c','iconset','-o',str(output),str(icon)],check=True)
  pngs=list(output.glob('*.png')); self.assertGreaterEqual(len(pngs),10)
  for png in pngs:
   b=png.read_bytes(); self.assertEqual(b[:8],b'\x89PNG\r\n\x1a\n')
   w,h=struct.unpack('>II',b[16:24]); self.assertEqual(w,h); self.assertGreaterEqual(w,16)
 def test_signature(self):
  subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',str(APP)],check=True)
 def test_copied_bundle_actual_no_write_smokes(self):
  self.assertTrue((APP/'Contents/Resources/backend/recovery.py').exists(),'do not execute a legacy GUI lacking headless smoke flags')
  copied=ROOT/'.build'/('copy-smoke-'+uuid.uuid4().hex)/'DisplayPipe.app'
  shutil.copytree(APP,copied)
  def hashes(): return {str(p.relative_to(copied)):hashlib.sha256(p.read_bytes()).hexdigest() for p in copied.rglob('*') if p.is_file()}
  before=hashes(); exe=copied/'Contents/MacOS/DisplayPipe'
  diagnostics=json.loads(subprocess.check_output([str(exe),'--smoke-json'],cwd=str(pathlib.Path.home()),timeout=35))
  self.assertTrue(diagnostics['readOnly']); self.assertEqual(diagnostics['errors'],[])
  result=json.loads(subprocess.check_output([str(exe),'--recovery-smoke-json'],cwd=str(pathlib.Path.home()),timeout=35))
  self.assertEqual(result['state'],'already-healthy'); self.assertFalse(result['setterCalled'])
  self.assertEqual(before,hashes(),'copied bundle must remain byte-identical and no pycache/source-relative writes')
  print('COPIED_BUNDLE',copied,'DIAGNOSTIC_DISPLAYS',len(diagnostics['displays']),'RECOVERY',result)
 def test_live_healthy_primary_contract_with_setter_disabled(self):
  resources=APP/'Contents/Resources'; python=(resources/'python-path.txt').read_text().strip()
  state=ROOT/'.build'/('healthy-contract-'+uuid.uuid4().hex)
  env=dict(os.environ,DISPLAYPIPE_STATE=str(state),PYTHONDONTWRITEBYTECODE='1')
  code="import recovery,json; calls=[]; e=recovery.Engine(setter=lambda *a:calls.append(a)); result=e.run(execute=True,confirmed=True); assert result['state']=='already-healthy',result; assert calls==[],calls; print(json.dumps(result))"
  result=subprocess.check_output([python,'-B','-c',code],cwd=str(resources/'backend'),env=env,timeout=20)
  print('LIVE_HEALTHY_PRIMARY_CONTRACT',result.decode().strip())
 def test_missing_runtime_fails_clearly_without_install(self):
  self.assertTrue((APP/'Contents/Resources/backend/recovery.py').exists())
  copied=ROOT/'.build'/('missing-runtime-'+uuid.uuid4().hex)/'DisplayPipe.app'; shutil.copytree(APP,copied)
  config=copied/'Contents/Resources/python-path.txt'
  config.rename(config.with_name('python-path.verified-backup.txt'))
  config.write_text('/nonexistent/DisplayPipe-python3\n')
  result=subprocess.run([str(copied/'Contents/MacOS/DisplayPipe'),'--recovery-smoke-json'],capture_output=True,text=True,timeout=20)
  self.assertEqual(result.returncode,2); self.assertIn('缺少已验证的现有 Python',result.stderr)
  self.assertIn('未写入显示',result.stderr)
if __name__=='__main__': unittest.main()
