#!/usr/bin/env python3
"""Actual packaged artifact checks; no GUI launch and no possible native setter call."""
import hashlib, json, os, pathlib, shutil, struct, subprocess, sys, unittest, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
APP=pathlib.Path(os.environ.get('DISPLAYPIPE_TEST_APP',str(ROOT/'.build/DisplayPipe.app')))
class Package(unittest.TestCase):
 def test_release_version_and_original_mit_license(self):
  import plistlib
  info=plistlib.loads((APP/'Contents/Info.plist').read_bytes())
  self.assertEqual((info['CFBundleShortVersionString'],info['CFBundleVersion']),('0.2.5','7'))
 def test_original_mit_license(self):
  self.assertTrue((APP/'Contents/Resources/licenses/DisplayPipe-MIT.txt').is_file(),'original MIT license must ship with upstream notices')
  self.assertEqual((APP/'Contents/Resources/licenses/DisplayPipe-MIT.txt').read_bytes(),(ROOT/'LICENSE').read_bytes())
 def test_bundle_resources(self):
  for rel in ['backend/recovery.py','backend/displaypipe.py','backend/build/DisplayPipeIO','backend/edid-core/target/release/displaypipe-edid','docs/USER_GUIDE.md','licenses/DisplayPipe-MIT.txt','licenses/pipecap-MIT.txt','licenses/edid-core-MIT.txt','python-path.txt','DisplayPipe.icns']:
   self.assertTrue((APP/'Contents/Resources'/rel).is_file(),rel)
 def test_runtime_only_manifest(self):
  resources=APP/'Contents/Resources'
  self.assertFalse((resources/'scripts').exists(),'build and test scripts are not runtime resources')
  self.assertFalse((resources/'backend/DisplayPipeIO.m').exists(),'native source is not a runtime resource')
  manifest=json.loads((resources/'MANIFEST.sha256.json').read_text())
  actual={str(p.relative_to(resources)):hashlib.sha256(p.read_bytes()).hexdigest() for p in resources.rglob('*') if p.is_file() and p.name!='MANIFEST.sha256.json'}
  self.assertEqual(manifest,actual,'manifest must enumerate and hash every shipped runtime resource exactly')
  self.assertEqual(set(actual),{'backend/displaypipe.py','backend/recovery.py','backend/build/DisplayPipeIO','backend/edid-core/target/release/displaypipe-edid','docs/USER_GUIDE.md','docs/UPSTREAM.md','licenses/DisplayPipe-MIT.txt','licenses/pipecap-MIT.txt','licenses/edid-core-MIT.txt','licenses/NOTICE.txt','python-path.txt','DisplayPipe.icns'})
 def test_recorded_python_is_a_hint_not_a_hard_dependency(self):
  recorded=(APP/'Contents/Resources/python-path.txt').read_text().strip()
  self.assertTrue(pathlib.Path(recorded).is_absolute(),'the build machine path stays recorded as a hint')
  candidate=recorded if pathlib.Path(recorded).is_file() else '/usr/bin/python3'
  subprocess.run([candidate,'-B','-c','import sys,argparse,fcntl,hashlib,json,pathlib,subprocess; assert sys.version_info >= (3,9); print(sys.executable,sys.version.split()[0])'],check=True)
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
  self.assertTrue(diagnostics['externalCards'],'the copied bundle reports the external displays it actually found')
  result=json.loads(subprocess.check_output([str(exe),'--recovery-smoke-json'],cwd=str(pathlib.Path.home()),timeout=40))
  # A dry run is the honest host-independent contract: it plans and reports, and never writes.
  self.assertIn(result['state'],['already-healthy','dry-run'])
  self.assertFalse(result['setterCalled'])
  self.assertEqual(before,hashes(),'copied bundle must remain byte-identical and no pycache/source-relative writes')
  print('COPIED_BUNDLE',copied,'DIAGNOSTIC_DISPLAYS',len(diagnostics['displays']),'RECOVERY',result)
 def test_live_primary_contract_never_reaches_a_real_setter(self):
  resources=APP/'Contents/Resources'
  python=subprocess.check_output(['/usr/bin/python3','-B','-c','import sys;print(sys.executable)'],text=True).strip()
  state=ROOT/'.build'/('primary-contract-'+uuid.uuid4().hex)
  env=dict(os.environ,DISPLAYPIPE_STATE=str(state),PYTHONDONTWRITEBYTECODE='1')
  dry=("import recovery,json;"
       "calls=[];"
       "e=recovery.Engine(setter=lambda *a:(calls.append(a),(_ for _ in ()).throw(AssertionError('dry run wrote'))));"
       "r=e.run(); assert r['state'] in ('dry-run','already-healthy'), r; assert calls==[], calls;"
       "print(json.dumps(r))")
  result=subprocess.check_output([python,'-B','-c',dry],cwd=str(resources/'backend'),env=env,timeout=40)
  print('LIVE_DRY_RUN_CONTRACT',result.decode().strip())
  # The injected setter is inert, so a healthy live state must never call it at all.
  live=("import recovery,json;"
        "calls=[];"
        "e=recovery.Engine(setter=lambda *a:calls.append(a) or 7);"
        "r=e.run(execute=True,confirmed=True);"
        "assert (r['state']=='already-healthy' and calls==[]) or (r['state']!='already-healthy' and calls), r;"
        "assert r['setterCalled']==bool(calls), r;"
        "print(json.dumps(r))")
  result=subprocess.check_output([python,'-B','-c',live],cwd=str(resources/'backend'),env=env,timeout=40)
  print('LIVE_PRIMARY_CONTRACT',result.decode().strip())
 def test_interpreter_resolution_order_and_fail_closed(self):
  self.assertTrue((APP/'Contents/Resources/backend/recovery.py').exists())
  base=ROOT/'.build'/('interpreter-'+uuid.uuid4().hex); base.mkdir(parents=True)
  copied=base/'DisplayPipe.app'; shutil.copytree(APP,copied)
  config=copied/'Contents/Resources/python-path.txt'
  config.rename(config.with_name('python-path.build-machine.txt'))
  config.write_text('/nonexistent/DisplayPipe-recorded-python3\n')
  exe=copied/'Contents/MacOS/DisplayPipe'
  # 1. A stale recorded path must fall back to a documented interpreter instead of failing.
  env=dict(os.environ); env.pop('DISPLAYPIPE_PYTHON',None); env.pop('DISPLAYPIPE_PYTHON_CANDIDATES',None)
  result=subprocess.run([str(exe),'--recovery-smoke-json'],capture_output=True,text=True,timeout=45,env=env)
  self.assertNotEqual(result.returncode,2,'a usable fallback interpreter must be found')
  self.assertNotIn('缺少可用的现有 Python',result.stderr)
  # 2. No interpreter anywhere: explicit, actionable error and no write.
  env=dict(os.environ); env['DISPLAYPIPE_PYTHON_CANDIDATES']='/nonexistent/only-candidate'
  env.pop('DISPLAYPIPE_PYTHON',None)
  result=subprocess.run([str(exe),'--recovery-smoke-json'],capture_output=True,text=True,timeout=25,env=env)
  self.assertEqual(result.returncode,2)
  self.assertTrue(any(text in result.stderr for text in ['缺少可用的现有 Python 3.9+','No usable existing Python 3.9+']),result.stderr)
  self.assertTrue(any(text in result.stderr for text in ['未写入显示','No display writes occurred']),result.stderr)
  self.assertIn('/nonexistent/only-candidate',result.stderr)
  # 3. An unusable explicit override is honoured as a decision, not silently replaced.
  env=dict(os.environ); env['DISPLAYPIPE_PYTHON']='/nonexistent/override-python3'
  env.pop('DISPLAYPIPE_PYTHON_CANDIDATES',None)
  result=subprocess.run([str(exe),'--recovery-smoke-json'],capture_output=True,text=True,timeout=25,env=env)
  self.assertEqual(result.returncode,2)
  self.assertIn('DISPLAYPIPE_PYTHON',result.stderr)
if __name__=='__main__': unittest.main()
