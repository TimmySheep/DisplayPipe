#!/usr/bin/env python3
"""Manual, single-target recovery. Never runs at login; CLI defaults to no display writes."""
import argparse, contextlib, fcntl, json, os, pathlib, subprocess, sys, time, uuid
import displaypipe as dp
P275=(0x3103,0x907d,0)
HUAWEI=(0x22f6,0x6346,16777216)
NAMES={P275:'P275MV PLUS',HUAWEI:'QSN-CAB'}
ORIGINAL_SHA='b45b962220ee0fe03b680a210de4af23cf92c4e973ed4e5624b4b55d4a450e92'
CANDIDATE_SHA='b27da31530a8b01541b57b40d5b87c205abc0f901daed4af6c928766df9d6d38'

def state_root():
 return pathlib.Path(os.environ.get('DISPLAYPIPE_STATE',str(pathlib.Path.home()/'Library/Application Support/DisplayPipe')))

def identity(b):
 return (int.from_bytes(b[8:10],'big'),int.from_bytes(b[10:12],'little'),int.from_bytes(b[12:16],'little'))

def classify(snap,require_pattern=True):
 externals=[d for d in snap['online'] if not d.get('builtin')]
 ids=[(d.get('vendor'),d.get('product'),d.get('serial')) for d in externals]
 if any(i not in NAMES for i in ids) or len(ids)!=len(set(ids)): raise ValueError('外屏身份不在精确白名单内或不唯一。')
 services={}
 for s in snap['services']:
  b=dp.service_edid(s); i=identity(b)
  if i not in NAMES or i in services or s.get('location')!='External': raise ValueError('IOAV 身份未知或不唯一。')
  if not s.get('serviceID') or not s.get('path'): raise ValueError('缺少精确注册表身份。')
  services[i]=s
 rows=[m for c in snap['crossbar'] for m in c.get('ConnectionMapping',[])]
 named=[m for m in rows if m.get('ProductName')]
 if any(m['ProductName'] not in NAMES.values() for m in named): raise ValueError('未知 Crossbar 映射。')
 mappings={}
 for i,name in NAMES.items():
  matches=[m for m in named if m['ProductName']==name]
  if len(matches)>1: raise ValueError('Crossbar 目标不唯一。')
  if matches: mappings[i]=matches[0]
 if set(ids)==set(NAMES): return 'healthy',services,mappings
 if not any(d.get('builtin') for d in snap['online']): raise ValueError('内屏必须在线；请打开机盖。')
 if ids==[P275] and P275 in services and mappings.get(P275,{}).get('PipeIDs') in ([1,0],[0,1]) and not mappings.get(HUAWEI,{}).get('PipeIDs'):
  return 'supported-fault',services,mappings
 if not require_pattern: return 'observed-incomplete',services,mappings
 raise ValueError('不支持的接入顺序或故障：仅验证 P275 先接、双 Pipe、华为缺失。华为先接尚未独立验证，拒绝写入。')

class AlreadyHealthy(Exception):
 pass

class Engine:
 def __init__(self,root=None,inventory=None,setter=None,sleep=time.sleep,clock=time.monotonic):
  self.root=pathlib.Path(root or state_root()); self.inventory=inventory or dp.inventory
  self.setter=setter; self.sleep=sleep; self.clock=clock; self.setter_attempted=False
 def pending(self):
  result=[]
  for run in sorted((self.root/'runs').glob('*')):
   events=sorted(run.glob('event-*.json'))
   if events:
    event=json.loads(events[-1].read_text())
    if event.get('pending'): result.append(dict(event,runDirectory=str(run)))
  return result
 def event(self,run,state,pending,**fields):
  value=dict(state=state,pending=pending,runDirectory=str(run),physicalInputConfirmed=False,recoveryValidated=False)
  value.update(fields)
  dp.exclusive(run/('event-%020d-%s.json'%(time.time_ns(),uuid.uuid4().hex)),json.dumps(value,sort_keys=True).encode())
  print(json.dumps(dict(progress=state,**fields),sort_keys=True),file=sys.stderr,flush=True)
  return value
 @contextlib.contextmanager
 def locked(self):
  self.root.mkdir(parents=True,exist_ok=True,mode=0o700)
  with open(self.root/'operation.lock','a') as lock:
   try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
   except BlockingIOError: raise ValueError('已有操作进行中；拒绝并发。')
   yield
 def checked(self,snap,run,expected):
  # Exact per-run identity, never rebind a replacement registry node.
  if not any(d.get('builtin') for d in snap['online']): raise ValueError('写入与回读期间内屏必须持续在线。')
  m=dp.load_backup(run/'original.bin')
  if dp.sha(m['bytes'])!=ORIGINAL_SHA: raise ValueError('原件不属于已验收身份。')
  proposed=(run/'candidate.bin').read_bytes()
  if dp.sha(proposed)!=CANDIDATE_SHA or dp.candidate(m['bytes'],120)['bytes']!=proposed: raise ValueError('候选完整性失败。')
  classify(snap,False)
  s=dp.select(snap['services'],m['serviceID'],m['path'])
  if identity(dp.service_edid(s))!=P275 or dp.service_edid(s)!=expected: raise ValueError('同一目标 EDID 回读不一致；停止，不盲目写入。')
  return m
 def write(self,mode,run):
  if self.setter: return self.setter(mode,run)
  model=subprocess.check_output(['/usr/sbin/sysctl','-n','hw.model'],timeout=3).decode().strip()
  if model!='Mac14,10': raise ValueError('仅允许已验证 Mac14,10；其它Mac型号尚未验收。')
  m=dp.load_backup(run/'original.bin')
  args=[str(dp.BASE/'build/DisplayPipeIO'),'temporary-write',m['serviceID'],m['path'],str(run/('original.bin' if mode else 'candidate.bin')),str(mode),str(run/'candidate.bin'),'I_ACCEPT_UNVALIDATED_PRIVATE_API']
  return json.loads(subprocess.check_output(args,timeout=12))
 def verified_write(self,mode,run,require_stable=False):
  m=dp.load_backup(run/'original.bin'); proposed=(run/'candidate.bin').read_bytes()
  current=self.inventory()
  if mode and classify(current)[0]=='healthy': raise AlreadyHealthy()
  self.checked(current,run,m['bytes'] if mode else proposed)
  if require_stable and not self.stable(current): raise ValueError('撤销前双屏稳定证据已变化；停止自动写入。')
  self.event(run,'applying' if mode else 'resetting',True)
  self.setter_attempted=True
  result=self.write(mode,run)
  dp.exclusive(run/('native-%s-%s.json'%(mode,uuid.uuid4().hex)),json.dumps(result,sort_keys=True).encode())
  expected=proposed if mode else m['bytes']
  if result.get('setterStatus')!=0 or result.get('copyStatus')!=0 or result.get('effectiveEDID')!=expected.hex(): raise ValueError('私有接口结果或即时字节回读不确定。')
  snap=self.inventory(); self.checked(snap,run,expected)
  dp.exclusive(run/('verified-%s-%s.json'%(mode,uuid.uuid4().hex)),json.dumps(snap,sort_keys=True).encode())
  return snap
 def stable(self,snap):
  kind,_,mapping=classify(snap,False)
  external=[d for d in snap['online'] if not d.get('builtin')]
  pipes=[mapping.get(i,{}).get('PipeIDs',[]) for i in NAMES]
  return kind=='healthy' and all(len(p)==1 for p in pipes) and pipes[0]!=pipes[1] and all(abs(d.get('refreshHz',0)-120)<1 for d in external)
 def latest(self):
  files=list((self.root/'runs').glob('*/event-*.json'))
  return json.loads(max(files,key=lambda p:p.name).read_text()) if files else None
 def status(self):
  pending=self.pending(); last=self.latest()
  if pending: return dict(state='recovery-needed',pending=pending,lastTransaction=last,physicalInputConfirmed=False,setterCalled=False)
  snap=self.inventory()
  try:
   kind,_,_=classify(snap)
   state='already-healthy' if kind=='healthy' else 'ready'
   error=''
  except ValueError as e: state='unsupported'; error=str(e)
  return dict(state=state,error=error,snapshot=snap,pending=[],lastTransaction=last,physicalInputConfirmed=False,setterCalled=False)
 def accept(self,confirmed=False):
  if not confirmed: raise ValueError('必须由用户明确确认两个屏幕实际点亮及 OSD 输入。')
  with self.locked():
   last=self.latest()
   if self.pending() or not last or last['state']!='cg-restored-reset-verified': raise ValueError('只有已完成原件撤销的系统双屏恢复事务可以记录实体确认。')
   return self.event(pathlib.Path(last['runDirectory']),'physical-accepted',False,physicalInputConfirmed=True,acceptanceSource='explicit-user-action',setterCalled=False)
 def undo(self,confirmed=False):
  if not confirmed: raise ValueError('手动撤销必须明确确认。')
  with self.locked():
   pending=self.pending()
   if len(pending)!=1: raise ValueError('必须恰好存在一个本程序拥有的未结束事务。')
   run=pathlib.Path(pending[0]['runDirectory'])
   try:
    m=dp.load_backup(run/'original.bin'); snap=self.inventory()
    s=dp.select(snap['services'],m['serviceID'],m['path'])
    current=dp.service_edid(s)
    if current==m['bytes']:
     self.checked(snap,run,current)
     return self.event(run,'undo-verified',False,setterCalled=False,alreadyOriginal=True)
    self.checked(snap,run,(run/'candidate.bin').read_bytes())
    self.verified_write(0,run)
    return self.event(run,'undo-verified',False,setterCalled=True)
   except Exception as e: return self.event(run,'recovery-needed',True,error=str(e))
 def run(self,execute=False,confirmed=False):
  with self.locked(): return self._run(execute,confirmed)
 def _run(self,execute,confirmed):
  self.setter_attempted=False
  if execute and not confirmed: raise ValueError('必须明确确认临时 EDID 私有接口风险。')
  pending=self.pending()
  if pending: return dict(state='recovery-needed',pending=pending,setterCalled=False,physicalInputConfirmed=False)
  snap=self.inventory(); kind,services,mappings=classify(snap)
  if kind=='healthy': return dict(state='already-healthy',setterCalled=False,physicalInputConfirmed=False)
  original=dp.service_edid(services[P275])
  if dp.sha(original)!=ORIGINAL_SHA: raise ValueError('仅支持已独立验收的 P275 原件；EDID 已变化。')
  proposed=dp.candidate(original,120)
  if proposed['sha256']!=CANDIDATE_SHA: raise ValueError('候选不等于已验收字节。')
  run=self.root/'runs'/uuid.uuid4().hex; run.mkdir(parents=True,mode=0o700)
  dp.backup(run/'original.bin',original,{k:services[P275][k] for k in ('serviceID','path','location')})
  dp.exclusive(run/'candidate.bin',proposed.pop('bytes'))
  dp.exclusive(run/'candidate.bin.json',json.dumps(proposed,sort_keys=True).encode())
  dp.exclusive(run/'before.json',json.dumps(snap,sort_keys=True).encode())
  if not execute: return self.event(run,'dry-run',False,setterCalled=False)
  try:
   self.verified_write(1,run)
   deadline=self.clock()+20; consecutive=0
   while self.clock()<=deadline:
    observed=self.inventory(); self.checked(observed,run,(run/'candidate.bin').read_bytes())
    dp.exclusive(run/('poll-%s.json'%uuid.uuid4().hex),json.dumps(observed,sort_keys=True).encode())
    consecutive=consecutive+1 if self.stable(observed) else 0
    self.event(run,'polling',True,stableSamples=consecutive,remainingSeconds=max(0,round(deadline-self.clock())))
    if consecutive>=3:
     final=self.verified_write(0,run,require_stable=True)
     both=classify(final,False)[0]=='healthy'
     return self.event(run,'cg-restored-reset-verified' if both else 'reset-verified-cg-not-restored',False,bothOnline=both,setterCalled=True)
    if self.clock()>=deadline: break
    self.sleep(1)
   return self.event(run,'recovery-needed',True,error='20秒内未取得连续3次双外屏120Hz、独立单Pipe证据。未盲目撤销；请手动撤销本次覆盖。',setterCalled=True)
  except AlreadyHealthy:
   return self.event(run,'already-healthy',False,setterCalled=False)
  except Exception as e:
   return self.event(run,'recovery-needed' if self.setter_attempted else 'unsupported',self.setter_attempted,error=str(e),setterCalled=self.setter_attempted)

def main():
 if sys.version_info < (3,9): raise ValueError('需要现有 Python3.9+；本App不会安装运行时。')
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('command',choices=['status','recover','undo','accept'],nargs='?',default='status')
 parser.add_argument('--execute',action='store_true',help='Explicit temporary display-write permission; recover otherwise dry-runs.')
 parser.add_argument('--confirm-private-api-risk',action='store_true')
 parser.add_argument('--confirm-physical',action='store_true')
 args=parser.parse_args(); engine=Engine()
 if args.command=='status': return engine.status()
 if args.command=='recover': return engine.run(args.execute,args.confirm_private_api_risk)
 if args.command=='undo':
  if not args.execute: return dict(state='dry-run',pending=engine.pending(),setterCalled=False)
  return engine.undo(args.confirm_private_api_risk)
 return engine.accept(args.confirm_physical)

if __name__=='__main__':
 try:
  result=main(); print(json.dumps(result,sort_keys=True),flush=True)
  if result['state'] in ('unsupported','recovery-needed','reset-verified-cg-not-restored'): sys.exit(3)
 except dp.EDIDUnavailable as e:
  print(json.dumps(dict(e.as_dict(),state='unsupported')),flush=True);sys.exit(2)
 except Exception as e:
  print(json.dumps(dict(state='failure',error=str(e),physicalInputConfirmed=False,recoveryValidated=False)),flush=True);sys.exit(2)
