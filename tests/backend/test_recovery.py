import copy, importlib.util, json, os, pathlib, sys, unittest, uuid
from unittest.mock import patch
import synthetic_fixtures as fixtures
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'backend'))
import displaypipe as dp
try: import recovery as r
except ImportError: r=None

class Recovery(unittest.TestCase):
 def setUp(self):
  self.root=ROOT/'.build'/'recovery-tests'/uuid.uuid4().hex; self.root.mkdir(parents=True)
  state=patch.dict(os.environ,{'DISPLAYPIPE_STATE':str(self.root)})
  state.start(); self.addCleanup(state.stop)
  self.base=fixtures.inventory()
  self.assertIsNotNone(r,'manual recovery orchestrator is missing')
  original=fixtures.panel_edid()
  # Only this test instance trusts synthetic SHA values; never edit production.
  # Prove the unpatched production gate rejects our fabricated monitor bytes.
  production_original=r.ORIGINAL_SHA; production_candidate=r.CANDIDATE_SHA
  self.assertNotEqual(dp.sha(original),production_original)
  with self.assertRaisesRegex(ValueError,'EDID'):
   r.Engine(self.root,lambda:copy.deepcopy(self.base),lambda *a:self.fail('unexpected setter')).run()
  proposed=dp.candidate(original,120)
  self.assertNotEqual(proposed['sha256'],production_candidate)
  with patch.object(r,'ORIGINAL_SHA',dp.sha(original)):
   with self.assertRaisesRegex(ValueError,'候选'):
    r.Engine(self.root,lambda:copy.deepcopy(self.base),lambda *a:self.fail('unexpected setter')).run()
  for name,value in (('ORIGINAL_SHA',dp.sha(original)),('CANDIDATE_SHA',proposed['sha256'])):
   allowlist=patch.object(r,name,value); allowlist.start(); self.addCleanup(allowlist.stop)
  # Accidentally reaching the native setter is a hard test failure, not a write.
  native=dp.subprocess.check_output
  def read_only_native(args,*a,**kw):
   if 'temporary-write' in args: self.fail('tests must never invoke a native display setter')
   return native(args,*a,**kw)
  guard=patch.object(dp.subprocess,'check_output',side_effect=read_only_native)
  guard.start(); self.addCleanup(guard.stop)
 def test_dryrun_new_exact_backup_no_setter(self):
  self.assertIsNotNone(r,'manual recovery orchestrator is missing')
  calls=[]
  out=r.Engine(self.root,lambda:copy.deepcopy(self.base),lambda *a:calls.append(a)).run()
  self.assertEqual(out['state'],'dry-run'); self.assertEqual(calls,[])
  m=dp.load_backup(pathlib.Path(out['runDirectory'])/'original.bin')
  self.assertEqual(m['serviceID'],self.base['services'][0]['serviceID'])
  self.assertEqual(m['path'],self.base['services'][0]['path'])
  self.assertFalse(out['physicalInputConfirmed'])
 def test_apply_stable_poll_reset_exact_original(self):
  calls=[]; current=copy.deepcopy(self.base); clock=[0]
  def read(): return copy.deepcopy(current)
  def setter(mode,run):
   calls.append(mode)
   current['services'][0]['edid']=(run/('candidate.bin' if mode else 'original.bin')).read_bytes().hex()
   current['online'].append(dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120)) if mode else None
   current['crossbar'][0]['ConnectionMapping']=[dict(ProductName='P275MV PLUS',Address='0.3.0',PipeIDs=[1]),dict(ProductName='QSN-CAB',Address='0.2.0',PipeIDs=[0])]
   return dict(setterStatus=0,copyStatus=0,effectiveEDID=current['services'][0]['edid'])
  out=r.Engine(self.root,read,setter,lambda n:clock.__setitem__(0,clock[0]+n),lambda:clock[0]).run(True,True)
  self.assertEqual(calls,[1,0]); self.assertEqual(out['state'],'cg-restored-reset-verified')
  self.assertFalse(out['physicalInputConfirmed']); self.assertTrue(out['bothOnline'])
  self.assertEqual(r.Engine(self.root,read,setter).pending(),[])
 def timeout_engine(self):
  current=copy.deepcopy(self.base); calls=[]; clock=[0]
  def setter(mode,run):
   calls.append(mode); current['services'][0]['edid']=(run/('candidate.bin' if mode else 'original.bin')).read_bytes().hex()
   return dict(setterStatus=0,copyStatus=0,effectiveEDID=current['services'][0]['edid'])
  engine=r.Engine(self.root,lambda:copy.deepcopy(current),setter,lambda n:clock.__setitem__(0,clock[0]+n),lambda:clock[0])
  return engine,current,calls,clock
 def test_timeout_pending_manual_undo_owned_transaction(self):
  e,current,calls,clock=self.timeout_engine(); out=e.run(True,True)
  self.assertEqual(out['state'],'recovery-needed'); self.assertEqual(calls,[1]); self.assertEqual(clock[0],20)
  self.assertEqual(e.run()['state'],'recovery-needed')
  out=e.undo(True)
  self.assertEqual(out['state'],'undo-verified'); self.assertEqual(calls,[1,0]); self.assertEqual(e.pending(),[])
 def test_healthy_never_calls_setter(self):
  e,current,calls,_=self.timeout_engine()
  current['online'].append(dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120))
  self.assertEqual(e.run(True,True)['state'],'already-healthy'); self.assertEqual(calls,[])
 def test_missing_confirmation_no_write(self):
  e,_,calls,_=self.timeout_engine()
  with self.assertRaises(ValueError): e.run(True,False)
  self.assertEqual(calls,[])
 def test_unvalidated_huawei_first_and_unknown_fail_closed(self):
  for fault in ('order','unknown','internal','duplicate'):
   e,current,calls,_=self.timeout_engine()
   if fault=='order': current['online'][1].update(vendor=0x22f6,product=0x6346,serial=16777216)
   if fault=='unknown': current['online'][1]['serial']=999
   if fault=='internal': current['online']=current['online'][1:]
   if fault=='duplicate': current['services']*=2
   with self.assertRaises(ValueError): e.run(True,True)
   self.assertEqual(calls,[])
 def test_changed_registry_id_blocks_undo_no_blind_reset(self):
  e,current,calls,_=self.timeout_engine(); e.run(True,True)
  current['services'][0]['serviceID']='new'
  out=e.undo(True)
  self.assertEqual(out['state'],'recovery-needed'); self.assertEqual(calls,[1]); self.assertTrue(e.pending())
 def test_bad_immediate_readback_keeps_pending_without_reset(self):
  e,current,calls,_=self.timeout_engine(); original=e.setter
  def bad(mode,run):
   result=original(mode,run); result['effectiveEDID']='bad'; return result
  e.setter=bad; out=e.run(True,True)
  self.assertEqual(out['state'],'recovery-needed'); self.assertEqual(calls,[1]); self.assertTrue(e.pending())
 def test_global_lock_refuses_second_operation(self):
  e,_,calls,_=self.timeout_engine()
  with e.locked():
   with self.assertRaises(ValueError): e.run(True,True)
  self.assertEqual(calls,[])
 def test_core_uses_external_recoverable_scratch(self):
  import os
  from unittest.mock import patch
  original=bytes.fromhex(self.base['services'][0]['edid'])
  before=set((self.root/'scratch-archive').glob('*.bin'))
  with patch.dict(os.environ,{'DISPLAYPIPE_STATE':str(self.root)}):
   dp.core(original)
  archived=list(set((self.root/'scratch-archive').glob('*.bin'))-before)
  self.assertEqual(len(archived),1,'core scratch must be archived outside application, not deleted')
  self.assertEqual(archived[0].read_bytes(),original)
 def test_status_reports_pending_after_restart(self):
  e,current,calls,_=self.timeout_engine(); e.run(True,True)
  fresh=r.Engine(self.root,lambda:copy.deepcopy(current))
  self.assertEqual(fresh.status()['state'],'recovery-needed'); self.assertEqual(len(fresh.status()['pending']),1)
 def test_physical_acceptance_is_explicit_separate_record(self):
  e,_,_,_=self.timeout_engine()
  run=self.root/'runs'/'accept-test'; run.mkdir(parents=True)
  e.event(run,'cg-restored-reset-verified',False,bothOnline=True)
  with self.assertRaises(ValueError): e.accept(False)
  self.assertFalse(e.status()['physicalInputConfirmed'])
  self.assertTrue(e.accept(True)['physicalInputConfirmed'])
 def test_healthy_closed_lid_is_noop_not_a_write_preflight(self):
  e,current,calls,_=self.timeout_engine()
  current['online']=[dict(builtin=0,vendor=0x3103,product=0x907d,serial=0,refreshHz=120),dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120)]
  self.assertEqual(e.run(True,True)['state'],'already-healthy'); self.assertEqual(calls,[])
 def test_reset_failure_keeps_pending_and_original_not_assumed(self):
  e,current,calls,clock=self.timeout_engine(); original=e.setter
  def setter(mode,run):
   result=original(mode,run)
   if mode:
    current['online'].append(dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120))
    current['crossbar'][0]['ConnectionMapping']=[dict(ProductName='P275MV PLUS',Address='0.3.0',PipeIDs=[1]),dict(ProductName='QSN-CAB',Address='0.2.0',PipeIDs=[0])]
   else: result['setterStatus']=7
   return result
  e.setter=setter; out=e.run(True,True)
  self.assertEqual(out['state'],'recovery-needed'); self.assertEqual(calls,[1,0]); self.assertTrue(e.pending())
 def test_missing_readback_stops_not_automatic_reset(self):
  e,current,calls,_=self.timeout_engine(); original=e.setter
  def setter(mode,run):
   result=original(mode,run); current['services'][0]['edid']=None; return result
  e.setter=setter; out=e.run(True,True)
  self.assertEqual(out['state'],'recovery-needed'); self.assertEqual(calls,[1])
 def test_recheck_stability_immediately_before_automatic_reset(self):
  e,current,calls,_=self.timeout_engine(); original=e.setter; reads=[0]
  def setter(mode,run):
   result=original(mode,run)
   if mode:
    current['online'].append(dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120))
    current['crossbar'][0]['ConnectionMapping']=[dict(ProductName='P275MV PLUS',Address='0.3.0',PipeIDs=[1]),dict(ProductName='QSN-CAB',Address='0.2.0',PipeIDs=[0])]
   return result
  def read():
   reads[0]+=1
   # initial, apply preflight, readback, three poll samples, reset preflight
   if reads[0]==7: current['online']=current['online'][:2]
   return copy.deepcopy(current)
  e.setter=setter; e.inventory=read; out=e.run(True,True)
  self.assertEqual(calls,[1]); self.assertEqual(out['state'],'recovery-needed')
 def test_becomes_healthy_during_preparation_no_write(self):
  e,current,calls,_=self.timeout_engine(); reads=[0]
  def read():
   reads[0]+=1
   if reads[0]==2: current['online'].append(dict(builtin=0,vendor=0x22f6,product=0x6346,serial=16777216,refreshHz=120))
   return copy.deepcopy(current)
  e.inventory=read; out=e.run(True,True)
  self.assertEqual(calls,[]); self.assertEqual(out['state'],'already-healthy'); self.assertFalse(e.pending())
 def test_legacy_cli_lock_is_archived_outside_resources(self):
  import os
  from unittest.mock import patch
  original=bytes.fromhex(self.base['services'][0]['edid']); run=self.root/'legacy'; run.mkdir()
  backup=run/'original.bin'; candidate=run/'candidate.bin'
  dp.backup(backup,original,{k:self.base['services'][0][k] for k in ('serviceID','path','location')})
  proposed=dp.candidate(original,120); candidate.write_bytes(proposed.pop('bytes'))
  pathlib.Path(str(candidate)+'.json').write_text(json.dumps(proposed))
  argv=['displaypipe','apply','--backup',str(backup),'--candidate',str(candidate),'--execute-temporary','--ack-private-api-unvalidated']
  with patch.dict(os.environ,{'DISPLAYPIPE_STATE':str(self.root)}),patch('sys.argv',argv),patch.object(dp,'inventory',return_value=self.base),patch.object(dp,'transact',return_value={'state':'dry-run'}): dp.main()
  self.assertEqual(len(list((self.root/'legacy-locks/released-locks').glob('*'))),1,'legacy lock must not mutate bundled Resources/build')
 def test_native_write_rejects_unvalidated_mac_model(self):
  from unittest.mock import patch
  e=r.Engine(self.root,lambda:copy.deepcopy(self.base))
  with patch.object(r.subprocess,'check_output',return_value=b'Mac99,1\n') as command:
   with self.assertRaisesRegex(ValueError,'Mac14,10'): e.write(1,self.root)
   self.assertEqual(command.call_count,1)
 def test_cli_missing_edid_preflight_structured_no_setter(self):
  import contextlib,io,os,runpy
  from unittest.mock import patch
  broken=copy.deepcopy(self.base); broken['services'][0]['edid']=None
  stdout=io.StringIO()
  with patch.dict(os.environ,{'DISPLAYPIPE_STATE':str(self.root)}),patch('sys.argv',['recovery','recover','--execute','--confirm-private-api-risk']),patch.object(dp,'inventory',return_value=broken),contextlib.redirect_stdout(stdout):
   with self.assertRaises(SystemExit): runpy.run_path(str(ROOT/'backend/recovery.py'),run_name='__main__')
  value=json.loads(stdout.getvalue()); self.assertEqual(value['state'],'unsupported')
  self.assertEqual(value['code'],'edid-unavailable'); self.assertFalse(value['setterCalled'])
if __name__=='__main__': unittest.main()
