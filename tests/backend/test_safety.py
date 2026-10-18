import importlib.util, os, pathlib, unittest, tempfile, uuid
from unittest.mock import patch
import synthetic_fixtures as fixtures
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('dp',ROOT/'backend/displaypipe.py'); dp=importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

def setUpModule():
 global _state_patch
 # Archive parser scratch inside the test tree, never the user's app state.
 _state_patch=patch.dict(os.environ,{'DISPLAYPIPE_STATE':str(ROOT/'.build'/'safety-tests'/uuid.uuid4().hex)})
 _state_patch.start()

def tearDownModule():
 _state_patch.stop()

class Safety(unittest.TestCase):
 def test_exact_identity_and_internal_denial(self):
  s={'serviceID':'123','path':'exact','location':'External','edid':'00'}
  self.assertEqual(dp.select([s], '123', 'exact'),s)
  for location in ['Embedded','','Unknown']:
   with self.assertRaises(ValueError): dp.select([dict(s,location=location)],'123','exact')
  with self.assertRaises(ValueError): dp.select([s,s],'123','exact')
  with self.assertRaises(ValueError): dp.select([s],'123','other')
 def test_backup_refuses_overwrite_and_checks_hash(self):
  b=bytes.fromhex('00ffffffffffff00')+bytes(120); b=bytearray(b); b[127]=(-sum(b))%256; b=bytes(b)
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'original.bin'; identity={'serviceID':'1','path':'p','location':'External'}
   m=dp.backup(p,b,identity)
   self.assertEqual(dp.load_backup(p)['bytes'],b)
   with self.assertRaises(FileExistsError): dp.backup(p,b,identity)
   p.write_bytes(b'corrupt')
   with self.assertRaises(ValueError): dp.load_backup(p)
 def test_validation_rejects_length_checksum_header(self):
  for b in [bytes(128),b'bad']:
   with self.assertRaises(ValueError): dp.validate(b)
class RangeLimits(unittest.TestCase):
 """Display Range Limits descriptor precision: byte 4 offsets and byte 10 formula."""
 def test_horizontal_range_offset_is_supported_recorded_and_still_cappable(self):
  b=fixtures.panel_edid(range_offset_bits=0x08)
  a=dp.audit(b)
  self.assertEqual(a['unsupported'],[],'a horizontal-only offset leaves the vertical cap well defined')
  self.assertEqual(a['ranges'][0]['offsetBits'],0x08)
  self.assertTrue(a['ranges'][0]['horizontalOffsets'])
  self.assertFalse(a['ranges'][0]['verticalOffsets'])
  candidate=dp.candidate(b,120)
  self.assertEqual(candidate['bytes'][fixtures.RANGE_MAX_OFFSET],120)
  self.assertEqual(candidate['bytes'][8:18],b[8:18])

 def test_vertical_or_reserved_offset_bits_fail_closed_naming_the_field(self):
  for bits,needle in ((0x01,'vertical offsets'),(0x02,'vertical offsets'),(0x10,'reserved offset bits'),(0x80,'reserved offset bits')):
   with self.subTest(bits=bits):
    b=fixtures.panel_edid(range_offset_bits=bits)
    problems=dp.audit(b)['unsupported']
    self.assertTrue(any(needle in problem for problem in problems),problems)
    self.assertTrue(any('0x%02x'%bits in problem for problem in problems),'the exact byte must be reported')
    with self.assertRaisesRegex(ValueError,'unsupported'): dp.candidate(b,120)

 def test_unsupported_range_timing_formula_is_named(self):
  for formula in (2,4):
   with self.subTest(formula=formula):
    problems=dp.audit(fixtures.panel_edid(range_formula=formula))['unsupported']
    self.assertTrue(any('range timing formula' in problem for problem in problems),problems)

 def test_cap_allowance_is_descriptor_quantization_not_a_mode_tolerance(self):
  nominal=dict(refresh_hz=120.0056,v_total=2250,h_total=4400)
  allowance=dp.cap_allowance(nominal)
  self.assertLess(allowance,0.2)
  self.assertLess(120.0056-120,allowance,'a nominal 120 Hz descriptor stays inside the allowance')
  self.assertGreater(144,120+allowance,'a real mode step never fits inside the allowance')
  self.assertGreater(120.5-120,dp.cap_allowance(dict(refresh_hz=120.5,v_total=2250,h_total=4400)))

 def test_quantized_120_mode_is_kept_and_reported(self):
  b=fixtures.quantized_120_edid()
  candidate=dp.candidate(b,120)
  self.assertTrue(candidate['retainedAboveCap'],'the retained nominal mode is reported, not hidden')
  entry=candidate['retainedAboveCap'][0]
  self.assertGreater(entry['refresh_hz'],120)
  self.assertLess(entry['refresh_hz']-120,entry['allowanceHz'])
  self.assertEqual(candidate['capAllowanceRule'],'per-timing descriptor quantization')
  self.assertEqual({round(t['refresh_hz']) for t in candidate['dropped']},{144,160})


class MissingEDID(unittest.TestCase):
 def test_missing_edid_preflight_is_structured_and_never_writes(self):
  import json
  from unittest.mock import patch
  identity={'serviceID':'123','path':'exact','location':'External'}
  original=bytes.fromhex('00ffffffffffff00')+bytes(120)
  original=bytearray(original); original[127]=(-sum(original))%256; original=bytes(original)
  with tempfile.TemporaryDirectory() as d:
   b=pathlib.Path(d)/'original.bin'; c=pathlib.Path(d)/'candidate.bin'
   dp.backup(b,original,identity); c.write_bytes(original)
   pathlib.Path(str(c)+'.json').write_text(json.dumps({'sha256':dp.sha(original),'originalSHA256':dp.sha(original),'maxHz':120}))
   for command in ('backup','apply','reset'):
    for fields in ({'copyStatus':0},{'copyStatus':7},{'copyStatus':0,'edid':None},{'copyStatus':0,'edid':''},{'copyStatus':0,'edid':'not-hex'},{'copyStatus':7,'edid':original.hex()}):
     with self.subTest(command=command,fields=fields):
      argv=['displaypipe',command]
      if command=='backup': argv+=['--service-id','123','--path','exact','--output',str(pathlib.Path(d)/'must-not-exist.bin')]
      else: argv+=['--backup',str(b),'--candidate',str(c),'--execute-temporary','--ack-private-api-unvalidated']
      snap={'services':[dict(identity,**fields)],'online':[{'builtin':True}],'crossbar':[]}
      with patch('sys.argv',argv),patch.object(dp,'inventory',return_value=snap),patch.object(dp,'candidate',return_value={'bytes':original}),patch.object(dp.subprocess,'check_output') as native,patch.object(dp,'transact') as transact:
       try: dp.main()
       except ValueError as e:
        self.assertEqual(e.as_dict()['code'],'edid-unavailable')
        self.assertEqual(e.as_dict()['serviceID'],'123')
        self.assertEqual(e.as_dict()['path'],'exact')
        self.assertEqual(e.as_dict()['copyStatus'],fields['copyStatus'])
        self.assertFalse(e.as_dict()['setterCalled'])
       else: self.fail('missing/failed EDID must abort preflight')
       native.assert_not_called(); transact.assert_not_called()
      self.assertFalse((pathlib.Path(d)/'must-not-exist.bin').exists())
 def test_missing_edid_cli_emits_json_exit_two(self):
  import contextlib,io,json,runpy
  from unittest.mock import patch
  service={'serviceID':'123','path':'exact','location':'External','copyStatus':0}
  stderr=io.StringIO(); stdout=io.StringIO()
  argv=['displaypipe','backup','--service-id','123','--path','exact','--output','must-not-be-created.bin']
  with patch('sys.argv',argv),patch('subprocess.check_output',return_value=json.dumps({'services':[service]}).encode()) as native,contextlib.redirect_stderr(stderr),contextlib.redirect_stdout(stdout):
   with self.assertRaises(SystemExit) as exit:
    runpy.run_path(str(ROOT/'backend/displaypipe.py'),run_name='__main__')
  self.assertEqual(exit.exception.code,2); self.assertEqual(stdout.getvalue(),'')
  error=json.loads(stderr.getvalue())
  self.assertEqual(error['code'],'edid-unavailable'); self.assertEqual(error['reason'],'missing-data')
  self.assertEqual(error['phase'],'preflight'); self.assertFalse(error['setterCalled'])
  self.assertFalse(error['recoveryValidated']); self.assertNotIn('KeyError',error['error'])
  self.assertEqual(native.call_count,1); self.assertEqual(native.call_args.args[0][-1],'inventory')
class Native(unittest.TestCase):
 def test_native_inventory_read_only_json(self):
  import subprocess,json
  helper=ROOT/'backend/build/DisplayPipeIO'
  self.assertTrue(helper.exists(),'native helper missing')
  data=json.loads(subprocess.check_output([str(helper),'inventory']))
  self.assertTrue(data['readOnly']); self.assertIn('services',data); self.assertIn('online',data); self.assertIn('crossbar',data)
  for s in data['services']: self.assertEqual(s['location'],'External'); self.assertTrue(s['path'])
class Offline(unittest.TestCase):
 def test_synthetic_edid_audit_and_candidate_fail_closed(self):
  for supported,b in ((True,fixtures.panel_edid()),(False,fixtures.unsupported_edid())):
   with self.subTest(supported=supported):
    a=dp.audit(b)
    self.assertTrue(a['valid']); self.assertIn('blockDetails',a)
    if supported:
     self.assertEqual(a['unsupported'],[])
     result=dp.candidate(b,120)
     dp.validate(result['bytes']); self.assertEqual(len(result['bytes']),len(b))
     self.assertEqual(result['bytes'][8:18],b[8:18])
    else:
     self.assertTrue(a['unsupported'])
     with self.assertRaisesRegex(ValueError,'unsupported'): dp.candidate(b,120)
 def test_unknown_extensions_and_malformed_data_block_refused(self):
  for fault in ('unknown-extension','truncated-cta-data-block'):
   with self.subTest(fault=fault):
    b=bytearray(fixtures.panel_edid())
    if fault=='unknown-extension': b[128]=0x99
    else: b[132]=0x5f  # Declared 31-byte Video Data Block exceeds CTA boundary.
    b[255]=0; b[255]=(-sum(b[128:256]))%256
    with self.assertRaisesRegex(ValueError,'unsupported'): dp.candidate(bytes(b),120)
 def test_vic_interlaced_definition(self):
  for vic,hz in [(5,60),(20,50)]:
   t=dp.vic(vic); self.assertTrue(t['interlaced']); self.assertEqual(t['fieldHz'],hz); self.assertEqual(t['frameHz'],hz/2)
class Transaction(unittest.TestCase):
 def test_dry_run_never_calls_setter(self):
  calls=[]
  result=dp.transact('apply',b'old',b'new',False,lambda *a:calls.append(a),lambda:b'new',lambda:{'online':[],'crossbar':[]})
  self.assertEqual(calls,[]); self.assertEqual(result['state'],'dry-run')
 def test_status_and_byte_readback_required(self):
  for status,readback,expected in [(0,b'new','edid-verified'),(1,b'new','setter-failed'),(0,b'wrong','readback-mismatch')]:
   result=dp.transact('apply',b'old',b'new',True,lambda *a:status,lambda:readback,lambda:{'online':[],'crossbar':[]})
   self.assertEqual(result['state'],expected); self.assertFalse(result['recoveryValidated'])
 def test_reset_must_read_original(self):
  calls=[]
  r=dp.transact('reset',b'old',b'new',True,lambda *a:(calls.append(a) or 0),lambda:b'old',lambda:{'online':[],'crossbar':[]})
  self.assertEqual(calls,[(0,None)]); self.assertEqual(r['state'],'edid-verified')
 def test_no_readback_on_setter_failure_is_not_success(self):
  r=dp.transact('reset',b'old',b'new',True,lambda *a:7,lambda:(_ for _ in ()).throw(ValueError('unavailable')),lambda:{})
  self.assertEqual(r['state'],'setter-failed'); self.assertFalse(r['recoveryValidated'])
 def test_native_write_rejects_without_full_authorization(self):
  import subprocess
  p=subprocess.run([str(ROOT/'backend/build/DisplayPipeIO'),'temporary-write'],capture_output=True)
  self.assertNotEqual(p.returncode,0)
  p=subprocess.run([str(ROOT/'backend/build/DisplayPipeIO'),'write-preflight'],capture_output=True)
  self.assertEqual(p.returncode,0)
  self.assertIn(b'private-api-unvalidated',p.stdout)
 def test_synthetic_panel_candidate_preserves_cta_and_identity(self):
  b=fixtures.panel_edid()
  r=dp.candidate(b,120); out=r['bytes']
  self.assertEqual(out[128:256],b[128:256]); self.assertEqual(out[8:54],b[8:54]); self.assertEqual(out[126],b[126]); self.assertEqual(len(out),384)
  self.assertEqual(out[fixtures.RANGE_MAX_OFFSET],120); self.assertEqual(len(r['dropped']),2)
  self.assertEqual({round(t['refresh_hz']) for t in r['dropped']},{144,160})
  self.assertTrue(any(t['h_active']==3840 and t['v_active']==2160 and t['refresh_hz']==120 for t in r['audit']['decoded']['timings']))
  self.assertFalse(any(t['refresh_hz']>120 for t in r['audit']['decoded']['timings']))
 def test_injected_high_vrr_refused(self):
  b=bytearray(fixtures.panel_edid()); b[fixtures.HF_VRR_MIN_OFFSET]=48;b[fixtures.HF_VRR_MAX_OFFSET]=160;b[255]=0;b[255]=(-sum(b[128:256]))%256
  with self.assertRaisesRegex(ValueError,'VRR'): dp.candidate(bytes(b),120)
 def test_range_only_is_capped_even_without_dropped_modes(self):
  b=fixtures.panel_edid(); out=bytearray(dp.candidate(b,120)['bytes']);out[fixtures.RANGE_MAX_OFFSET]=160;out[127]=0;out[127]=(-sum(out[:128]))%256
  result=dp.candidate(bytes(out),120)
  self.assertEqual(result['dropped'],[])
  self.assertEqual(result['bytes'][fixtures.RANGE_MAX_OFFSET],120)
 def test_recovery_evidence_requires_pipe_release_and_both_online(self):
  before={'crossbar':[{'ConnectionMapping':[{'ProductName':'panel','Address':'p','PipeIDs':[1,0]}]}],'online':[]}
  after={'crossbar':[{'ConnectionMapping':[{'ProductName':'panel','Address':'p','PipeIDs':[1]}]}],'online':[{'builtin':False,'vendor':1,'product':2},{'builtin':False,'vendor':3,'product':4}]}
  r=dp.recovery_evidence(before,after,(1,2),(3,4),'p')
  self.assertTrue(r['pipeReleased']);self.assertTrue(r['bothOnline']);self.assertFalse(r['physicalInputConfirmed'])
  after['online']=after['online'][:1]; self.assertFalse(dp.recovery_evidence(before,after,(1,2),(3,4),'p')['bothOnline'])
 def test_standard_timing_above_cap_fails_closed(self):
  b=bytearray(fixtures.panel_edid()); b[38]=0x81;b[39]=63;b[127]=0;b[127]=(-sum(b[:128]))%256
  with self.assertRaisesRegex(ValueError,'standard timing'): dp.candidate(bytes(b),120)
if __name__=='__main__': unittest.main()
