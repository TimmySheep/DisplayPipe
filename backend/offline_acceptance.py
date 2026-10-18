import json, pathlib, subprocess
root=pathlib.Path(__file__).resolve().parent
cli=['/usr/bin/python3',str(root/'displaypipe.py')]
snap=json.loads(subprocess.check_output(cli+['inventory']))
services=snap['services']
if len(services)!=1: raise RuntimeError('expected current exact single external service for acceptance')
s=services[0]; out=root/'private'; out.mkdir(mode=0o700,exist_ok=True)
b=out/'p275-original.bin'; c=out/'p275-120.bin'
print(subprocess.check_output(cli+['backup','--service-id',s['serviceID'],'--path',s['path'],'--output',str(b)]).decode())
print(subprocess.check_output(cli+['limit','--input',str(b),'--max-hz','120','--output',str(c)]).decode())
result=json.loads(subprocess.check_output(cli+['apply','--backup',str(b),'--candidate',str(c)]))
assert result['state']=='dry-run' and result['setterStatus'] is None
(out/'dry-run.json').write_text(json.dumps(result,indent=2))
p=subprocess.run(cli+['backup','--service-id',s['serviceID'],'--path',s['path'],'--output',str(b)],capture_output=True)
assert p.returncode==2
print('OFFLINE ACCEPTANCE PASS: exact real backup + candidate + dry-run + overwrite rejection; setter not called')
