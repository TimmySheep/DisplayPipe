#!/usr/bin/env python3
"""Read-only contract and live scoped/full mapping equivalence, never a setter."""
import pathlib, plistlib, subprocess, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Scope(unittest.TestCase):
 def test_collector_scopes_ioreg_to_connection_manager(self):
  source=(ROOT/'GUI/Diagnostics.swift').read_text()
  self.assertIn('"-r", "-c", "AppleDisplayConnectionManager"',source,'avoid materializing the whole IORegistry in the GUI')
  self.assertIn('run("/usr/sbin/ioreg", registryArguments)',source,'actual collector must use the scoped query')
 def test_scoped_query_retains_all_current_pipe_mappings(self):
  def mappings(value):
   if isinstance(value,dict):
    return value.get('ConnectionMapping',[])+[row for k,v in value.items() if k!='ConnectionMapping' for row in mappings(v)]
   if isinstance(value,list): return [row for v in value for row in mappings(v)]
   return []
  scoped=subprocess.check_output(['/usr/sbin/ioreg','-a','-l','-w0','-r','-c','AppleDisplayConnectionManager'],timeout=15)
  full=subprocess.check_output(['/usr/sbin/ioreg','-a','-l','-w0'],timeout=15)
  import json
  key=lambda row:json.dumps(row,sort_keys=True)
  self.assertEqual(sorted(mappings(plistlib.loads(scoped)),key=key),sorted(mappings(plistlib.loads(full)),key=key))
  self.assertLess(len(scoped),len(full)//10)
  print('IOREG_PLIST_BYTES full=',len(full),'scoped=',len(scoped))
if __name__=='__main__': unittest.main()
