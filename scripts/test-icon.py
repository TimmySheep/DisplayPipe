#!/usr/bin/env python3
"""Exercise real icon files; preserve all artifacts for inspection."""
import importlib.util, pathlib, struct, subprocess, unittest, uuid, zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Icon(unittest.TestCase):
 def test_lossless_png_compression(self):
  script=ROOT/'scripts/optimize-icon.py'
  self.assertTrue(script.is_file(),'lossless icon encoding optimizer must exist')
  spec=importlib.util.spec_from_file_location('optimize_icon',script); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
  def chunk(tag,payload): return struct.pack('>I',len(payload))+tag+payload+struct.pack('>I',zlib.crc32(tag+payload)&0xffffffff)
  pixels=bytes([20,40,80,255])*64
  png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',64,64,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+pixels)*64,0))+chunk(b'IEND',b'')
  optimized=module.optimize_png(png)
  self.assertLess(len(optimized),len(png)//2)
  self.assertEqual(module.decode_png(optimized)[1],pixels*64)
  self.assertEqual(module.optimize_png(b'not PNG'),b'not PNG')
 def test_real_icns_pixels_and_representations(self):
  self.assertTrue((ROOT/'scripts/optimize-icon.py').exists(),'lossless icon encoding optimizer must exist')
  output=ROOT/'.build'/('icon-lossless-'+uuid.uuid4().hex); output.mkdir()
  originals=list((ROOT/'.build').glob('DisplayPipe-uncompressed-*.icns'))
  original=max(originals,key=lambda p:p.stat().st_mtime) if originals else ROOT/'.build/DisplayPipe.app/Contents/Resources/DisplayPipe.icns'
  optimized=output/'DisplayPipe.icns'
  subprocess.run(['/usr/bin/python3','-B',str(ROOT/'scripts/optimize-icon.py'),str(original),str(optimized)],check=True)
  subprocess.run(['/usr/bin/iconutil','-c','iconset','-o',str(output/'before.iconset'),str(original)],check=True)
  subprocess.run(['/usr/bin/iconutil','-c','iconset','-o',str(output/'after.iconset'),str(optimized)],check=True)
  subprocess.run(['xcrun','swiftc',str(ROOT/'scripts/TestIconPixels.swift'),'-o',str(output/'pixel-tests')],check=True)
  subprocess.run([str(output/'pixel-tests'),str(output/'before.iconset'),str(output/'after.iconset')],check=True)
  self.assertLessEqual(optimized.stat().st_size,original.stat().st_size)
if __name__=='__main__': unittest.main()
