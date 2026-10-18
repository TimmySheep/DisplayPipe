#!/usr/bin/env python3
"""Build a relocatable manual-use app. Preserve previous artifacts by rename."""
import hashlib,json,os,pathlib,plistlib,shutil,subprocess,sys,uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
os.chdir(ROOT)
def run(*args): subprocess.run([str(a) for a in args],check=True)
def write(path,data):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as f: f.write(data)
python=subprocess.check_output(['/usr/bin/python3','-B','-c','import sys; print(sys.executable)'],text=True).strip()
if not pathlib.Path(python).is_absolute() or not os.access(python,os.X_OK): raise RuntimeError('existing Python dependency not executable')
run(python,'-B','-c','import sys,argparse,fcntl,hashlib,json,pathlib,subprocess; assert sys.version_info >= (3,9); print("Verified existing interpreter:",sys.executable,sys.version)')
app=ROOT/'.build/DisplayPipe.app'
if app.exists():
 archive=ROOT/'.build/archive'; archive.mkdir(exist_ok=True)
 app.rename(archive/('DisplayPipe-'+uuid.uuid4().hex+'.app'))
mac=app/'Contents/MacOS'; helpers=app/'Contents/Helpers'; resources=app/'Contents/Resources'
for p in (mac,helpers,resources): p.mkdir(parents=True,exist_ok=True)
run('xcrun','clang','-fobjc-arc','-framework','Foundation','-framework','IOKit','EDIDProbe.m','-o',helpers/'EDIDProbe')
run('xcrun','swiftc','-O','DisplayProbe.swift','-o',helpers/'DisplayProbe')
sources=['GUI/DiagnosticCore.swift','GUI/Presentation.swift','GUI/Diagnostics.swift','GUI/RecoveryPresentation.swift','GUI/RecoveryClient.swift','GUI/App.swift']
run('xcrun','swiftc','-swift-version','5','-Osize','-framework','AppKit','-framework','CoreGraphics',*sources,'-o',mac/'DisplayPipe')
for rel in ['backend/displaypipe.py','backend/recovery.py','backend/build/DisplayPipeIO','backend/edid-core/target/release/displaypipe-edid','docs/USER_GUIDE.md','docs/UPSTREAM.md']:
 target=resources/rel; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(ROOT/rel,target)
# Only runtime resources ship. Build/test scripts and native source stay in the repository.
write(resources/'licenses/pipecap-MIT.txt',(ROOT/'pipecap-review/LICENSE').read_bytes())
write(resources/'licenses/edid-core-MIT.txt',(ROOT/'backend/edid-core/LICENSE').read_bytes())
write(resources/'licenses/NOTICE.txt',b'DisplayPipe independent local manual recovery app. EDID parser derived from pipecap at d045192de888188783b4da74b10ab05f4229c868. MIT notices retained. Private Apple interfaces are not a compatibility guarantee. No BetterDisplay code or license bypass.\n')
write(resources/'python-path.txt',(python+'\n').encode())
icons=ROOT/'.build'/('DisplayPipe-'+uuid.uuid4().hex+'.iconset')
run('xcrun','swiftc','scripts/GenerateIcon.swift','-o',ROOT/'.build/icon-generator')
run(ROOT/'.build/icon-generator',icons)
raw_icon=ROOT/'.build'/('DisplayPipe-uncompressed-'+uuid.uuid4().hex+'.icns')
run('/usr/bin/iconutil','-c','icns','-o',raw_icon,icons)
run(python,'-B',ROOT/'scripts/optimize-icon.py',raw_icon,resources/'DisplayPipe.icns')
info=dict(CFBundleExecutable='DisplayPipe',CFBundleIdentifier='local.displaypipe.diagnostics',CFBundleName='DisplayPipe',CFBundleDisplayName='DisplayPipe',CFBundlePackageType='APPL',CFBundleShortVersionString='0.2.1',CFBundleVersion='3',CFBundleIconFile='DisplayPipe.icns',NSHighResolutionCapable=True,LSMinimumSystemVersion='13.0')
write(app/'Contents/Info.plist',plistlib.dumps(info))
for native in [helpers/'EDIDProbe',helpers/'DisplayProbe',resources/'backend/build/DisplayPipeIO',resources/'backend/edid-core/target/release/displaypipe-edid']:
 run('/usr/bin/codesign','--force','--sign','-',native)
manifest={str(p.relative_to(resources)):hashlib.sha256(p.read_bytes()).hexdigest() for p in resources.rglob('*') if p.is_file()}
write(resources/'MANIFEST.sha256.json',json.dumps(manifest,indent=2,sort_keys=True).encode())
run('/usr/bin/codesign','--force','--sign','-',app)
run('/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',app)
print('Built',app)
