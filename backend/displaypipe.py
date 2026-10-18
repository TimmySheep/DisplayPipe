#!/usr/bin/env python3
"""DisplayPipe fail-closed orchestration. JSON stdout; no EEPROM writes."""
import argparse, hashlib, json, os, pathlib, subprocess, sys

def select(services, service_id, path):
    matches=[s for s in services if s['serviceID']==service_id and s['path']==path]
    if len(matches)!=1 or matches[0]['location']!='External':
        raise ValueError('target must be one exact External service ID + registry path')
    return matches[0]

def sha(b): return hashlib.sha256(b).hexdigest()

def validate(b):
    if len(b)<128 or len(b)%128 or b[:8]!=bytes.fromhex('00ffffffffffff00') or len(b)!=(b[126]+1)*128:
        raise ValueError('invalid EDID header/length/extension count')
    if any(sum(b[i:i+128])%256 for i in range(0,len(b),128)):
        raise ValueError('invalid EDID checksum')

class EDIDUnavailable(ValueError):
    def __init__(self,service,phase,reason):
        super().__init__('EDID unavailable: '+reason+'; refresh inventory before retrying')
        self.details=dict(code='edid-unavailable',phase=phase,reason=reason,
                          serviceID=service.get('serviceID'),path=service.get('path'),
                          copyStatus=service.get('copyStatus'),recoveryValidated=False)
        if phase=='preflight': self.details['setterCalled']=False

    def as_dict(self):
        return dict(self.details,error=str(self))

def service_edid(service,phase='preflight'):
    if service.get('copyStatus')!=0:
        raise EDIDUnavailable(service,phase,'copy-failed')
    text=service.get('edid')
    if not isinstance(text,str) or not text:
        raise EDIDUnavailable(service,phase,'missing-data')
    try:
        b=bytes.fromhex(text); validate(b)
    except ValueError as e:
        raise EDIDUnavailable(service,phase,'invalid-data') from e
    return b

def exclusive(path,b):
    fd=os.open(str(path),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as f: f.write(b); f.flush(); os.fsync(f.fileno())

def backup(path,b,identity):
    validate(b); path=pathlib.Path(path)
    meta=dict(identity,sha256=sha(b),length=len(b),schema=1)
    # Refuse even a partially existing pair; never replace the trusted original.
    if path.exists() or pathlib.Path(str(path)+'.json').exists(): raise FileExistsError(str(path))
    exclusive(path,b); exclusive(str(path)+'.json',json.dumps(meta,sort_keys=True).encode())
    return meta

def load_backup(path):
    path=pathlib.Path(path); b=path.read_bytes(); meta=json.loads(pathlib.Path(str(path)+'.json').read_text())
    validate(b)
    if sha(b)!=meta['sha256'] or len(b)!=meta['length'] or meta['location']!='External': raise ValueError('backup integrity/identity failure')
    return dict(meta,bytes=b)

import pathlib, subprocess, json, tempfile, math
BASE=pathlib.Path(__file__).resolve().parent

def vic(n):
 if n not in (5,20): raise ValueError('unsupported VIC')
 hz=60 if n==5 else 50
 return dict(vic=n,width=1920,height=1080,interlaced=True,fieldHz=hz,frameHz=hz/2,pixelClockHz=74250000)

def core(b,action='parse',hz=120):
 root=pathlib.Path(os.environ.get('DISPLAYPIPE_STATE',str(pathlib.Path.home()/'Library/Application Support/DisplayPipe')))
 scratch=root/'scratch'; archive=root/'scratch-archive'
 scratch.mkdir(parents=True,exist_ok=True,mode=0o700); archive.mkdir(parents=True,exist_ok=True,mode=0o700)
 fd,name=tempfile.mkstemp(dir=str(scratch),suffix='.bin')
 try:
  with os.fdopen(fd,'wb') as f: f.write(b); f.flush(); os.fsync(f.fileno())
  args=[str(BASE/'edid-core/target/release/displaypipe-edid'),action,name]
  if action=='cap': args.append(str(hz))
  return json.loads(subprocess.check_output(args,timeout=5))
 finally:
  pathlib.Path(name).rename(archive/pathlib.Path(name).name)

def audit(b):
 validate(b); details=[]; unsupported=[]; ranges=[]; vrr=[]; info=core(b)
 if b[18:20] not in (b'\x01\x03',b'\x01\x04'): unsupported.append('base version')
 for o in range(54,126,18):
  d=b[o:o+18]
  if d[:2]==b'\0\0' and d[3]==0xfd:
   ranges.append(dict(offset=o,minHz=d[5],maxHz=d[6],formula=d[10],maxClockMHz=d[9]*10))
   if d[4] or d[10] not in (0,1): unsupported.append('range offsets/CVT/secondary GTF')
  elif d[:2]==b'\0\0' and d[3] not in (0x10,0xfc,0xff): unsupported.append('base descriptor '+hex(d[3]))
 for off in range(128,len(b),128):
  x=b[off:off+128]; record=dict(block=off//128,tag=x[0],items=[])
  if x[0]==2:
   end=x[2]
   if end<4 or end>127: unsupported.append('CTA boundary'); details.append(record); continue
   i=4
   while i<end:
    tag=x[i]>>5; n=x[i]&31; body=x[i+1:i+1+n]; item=dict(tag=tag,payload=body.hex(),offset=off+i); record['items'].append(item)
    if i+1+n>end: unsupported.append('CTA truncated data block'); break
    if tag==2:
     values=[v&127 if 1<=v&127<=64 else v for v in body]
     decoded={t['source']['vic'] for t in info['timings'] if t['source']['kind']=='cta_vic' and t['source']['block']==off//128}
     if any(v not in decoded for v in values): unsupported.append('CTA unknown VIC')
     item['vics']=values
    elif tag==3:
     oui=body[:3].hex(); item['oui']=oui
     if oui=='030c00':
      if n>8: unsupported.append('HDMI VSDB extended video/latency fields')
     elif oui=='d85dc4':
      if n<7 or n==9: unsupported.append('HDMI Forum malformed length')
      if n>=10: vrr.append(dict(kind='HDMI Forum',offset=off+i+9,minHz=body[8]&63,maxHz=((body[8]&192)<<2)|body[9]))
     else: unsupported.append('CTA vendor '+oui)
    elif tag==7:
     if not body or body[0] not in (0,5,6,15): unsupported.append('CTA extended tag '+(hex(body[0]) if body else 'empty'))
    elif tag not in (1,4): unsupported.append('CTA data block '+str(tag))
    i+=1+n
   record['nativeDTDCount']=x[3]&15
   j=end
   while j+18<=127 and x[j:j+2]!=b'\0\0': j+=18
   if any(x[j:127]): unsupported.append('CTA descriptor tail')
  elif x[0]==0x70:
   end=5+x[2]
   if end>126 or sum(x[1:end+1])%256: unsupported.append('DisplayID length/section checksum')
   if x[1]!=0x12 or x[4]!=0: unsupported.append('DisplayID version/chained sections')
   i=5
   while i+3<=min(end,126):
    tag,rev,n=x[i:i+3]
    if tag==0 and n==0:
     if any(x[i:end]): unsupported.append('DisplayID nonzero padding')
     break
    record['items'].append(dict(tag=tag,revision=rev,length=n,offset=off+i))
    if tag!=3 or rev!=1 or n%20 or i+3+n>end: unsupported.append('DisplayID data block '+hex(tag))
    i+=3+n
   if any(x[end+1:127]): unsupported.append('DisplayID trailing data')
  else: unsupported.append('extension '+hex(x[0]))
  details.append(record)
 return dict(valid=True,sha256=sha(b),identity=dict(vendor=int.from_bytes(b[8:10],'big'),product=int.from_bytes(b[10:12],'little'),serial=int.from_bytes(b[12:16],'little')),decoded=info,blockDetails=details,ranges=ranges,vrr=vrr,unsupported=unsupported)

def candidate(b,hz):
 if not math.isfinite(hz) or hz<100 or hz>120 or int(hz)!=hz: raise ValueError('unsupported cap: conservative range 100..120 integer Hz')
 a=audit(b)
 for o in range(38,54,2):
  if b[o:o+2]!=b'\x01\x01' and (b[o+1]&63)+60>hz: raise ValueError('unsupported standard timing above cap')
 if b[37]&127: raise ValueError('unsupported manufacturer established timing')
 if a['unsupported']: raise ValueError('unsupported: '+', '.join(a['unsupported']))
 if any(t['source']['kind']=='cta_vic' and t['refresh_hz']>hz for t in a['decoded']['timings']): raise ValueError('unsupported CTA SVD removal')
 r=core(b,'cap',hz); out=bytearray.fromhex(r['bytes'])
 for rg in a['ranges']:
  if rg['minHz']>hz: raise ValueError('unsupported range minimum')
  out[rg['offset']+6]=min(rg['maxHz'],int(hz))
 for vr in a['vrr']:
  if vr['maxHz']>hz: raise ValueError('unsupported VRR maximum exceeds cap')
 for i in range(0,len(out),128): out[i+127]=0; out[i+127]=(-sum(out[i:i+128]))%256
 out=bytes(out); after=audit(out)
 if after['unsupported']: raise ValueError('unsupported candidate: '+', '.join(after['unsupported']))
 if out[8:54]!=b[8:54] or len(out)!=len(b) or out[126]!=b[126]: raise ValueError('identity/extension preservation failure')
 if any(t['refresh_hz']>hz for t in after['decoded']['timings']): raise ValueError('unsupported retained timing above strict cap')
 return dict(bytes=out,sha256=sha(out),originalSHA256=sha(b),maxHz=hz,dropped=r['dropped'],audit=after,recoveryValidated=False)


def transact(action,original,proposed,execute,setter,reader,snapshot):
 if action not in ('apply','reset'): raise ValueError('invalid operation')
 r=dict(state='dry-run',setterStatus=None,readbackEqual=None,recoveryValidated=False)
 if not execute: return r
 status=setter(1,proposed) if action=='apply' else setter(0,None)
 r['setterStatus']=status; r['state']='setter-failed' if status else 'readback-mismatch'
 try:
  b=reader(); r['readbackEqual']=b==(proposed if action=='apply' else original); r['effectiveSHA256']=sha(b)
  if status==0 and r['readbackEqual']: r['state']='edid-verified'
 except Exception as e: r['readbackError']=str(e)
 try: r['observedAfter']=snapshot()
 except Exception as e: r['observationError']=str(e)
 # EDID match alone never establishes physical recovery or Pipe release.
 return r

def inventory():
 return json.loads(subprocess.check_output([str(BASE/'build/DisplayPipeIO'),'inventory'],timeout=5))

def recovery_evidence(before,after,target,peer,address):
 def mappings(s): return [m for c in s.get('crossbar',[]) for m in c.get('ConnectionMapping',[]) if m.get('Address')==address]
 a=mappings(before);b=mappings(after)
 released=len(a)==1 and len(b)==1 and len(a[0].get('PipeIDs',[]))>len(b[0].get('PipeIDs',[]))>0
 external=[d for d in after.get('online',[]) if not d.get('builtin',True)]
 both=all(sum((d['vendor'],d['product'])==identity for d in external)==1 for identity in (target,peer)) and target!=peer
 return dict(pipeReleased=released,bothOnline=both,physicalInputConfirmed=False,recoveryValidated=False,reason='Physical input timing and user-visible signal still require endpoint acceptance; CoreGraphics modes are not wire timing.')

def main():
 p=argparse.ArgumentParser(description='DisplayPipe safe backend. JSON output. All writes require explicit authorization.')
 sub=p.add_subparsers(dest='command',required=True)
 sub.add_parser('inventory')
 for name in ('inspect','limit'):
  q=sub.add_parser(name); q.add_argument('--input',required=True)
  if name=='limit': q.add_argument('--max-hz',type=int,default=120); q.add_argument('--output',required=True)
 q=sub.add_parser('backup'); q.add_argument('--service-id',required=True); q.add_argument('--path',required=True); q.add_argument('--output',required=True)
 for name in ('apply','reset'):
  q=sub.add_parser(name); q.add_argument('--backup',required=True); q.add_argument('--candidate',required=True); q.add_argument('--execute-temporary',action='store_true'); q.add_argument('--ack-private-api-unvalidated',action='store_true')
 a=p.parse_args()
 if a.command=='inventory': return inventory()
 if a.command=='inspect': return audit(pathlib.Path(a.input).read_bytes())
 if a.command=='limit':
  r=candidate(pathlib.Path(a.input).read_bytes(),a.max_hz); b=r.pop('bytes'); exclusive(a.output,b); exclusive(a.output+'.json',json.dumps(r,sort_keys=True).encode());return r
 if a.command=='backup':
  snap=inventory(); s=select(snap['services'],a.service_id,a.path)
  return backup(a.output,service_edid(s),{k:s[k] for k in ('serviceID','path','location')})
 m=load_backup(a.backup); proposed=pathlib.Path(a.candidate).read_bytes(); validate(proposed)
 manifest=json.loads(pathlib.Path(a.candidate+'.json').read_text())
 if manifest['sha256']!=sha(proposed) or manifest['originalSHA256']!=m['sha256']: raise ValueError('candidate provenance mismatch')
 # Independently reproduce candidate: editing the manifest cannot bypass the parser gates.
 if candidate(m['bytes'],manifest['maxHz'])['bytes']!=proposed: raise ValueError('candidate bytes not reproducible')
 before=inventory(); s=select(before['services'],m['serviceID'],m['path'])
 current=service_edid(s)
 expected=m['bytes'] if a.command=='apply' else proposed
 if current!=expected: raise ValueError('effective EDID does not match expected precondition; stop, do not overwrite original')
 if not any(x['builtin'] for x in before['online']): raise ValueError('built-in fallback display must be online')
 if a.execute_temporary and not a.ack_private_api_unvalidated: raise ValueError('explicit private-API risk acknowledgement required')
 def setter(mode,data):
  args=[str(BASE/'build/DisplayPipeIO'),'temporary-write',m['serviceID'],m['path'],str(pathlib.Path(a.backup if mode else a.candidate).resolve()),str(mode),str(pathlib.Path(a.candidate).resolve()),'I_ACCEPT_UNVALIDATED_PRIVATE_API']
  result=json.loads(subprocess.check_output(args)); native_result.update(result); return result['setterStatus']
 native_result={}
 def read():
  snap=inventory(); target=select(snap['services'],m['serviceID'],m['path']); return service_edid(target,'readback')
 # Per-target lock refuses parallel applications from this CLI; no background agent or auto-reset.
 lock_root=pathlib.Path(os.environ.get('DISPLAYPIPE_STATE',str(pathlib.Path.home()/'Library/Application Support/DisplayPipe')))/'legacy-locks'
 if a.execute_temporary: lock_root.mkdir(parents=True,exist_ok=True,mode=0o700)
 lock=lock_root/('target-'+sha(m['path'].encode())+'.lock')
 if a.execute_temporary:
  fd=os.open(str(lock),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.close(fd)
 try:
  r=transact(a.command,m['bytes'],proposed,a.execute_temporary,setter,read,inventory)
  r['observedBefore']=before; r['native']=native_result
  if a.execute_temporary:
   native_expected=proposed if a.command=='apply' else m['bytes']
   r['immediateReadbackEqual']=native_result.get('copyStatus')==0 and native_result.get('effectiveEDID')==native_expected.hex()
   if not r['immediateReadbackEqual'] and r['state']=='edid-verified': r['state']='readback-mismatch'
   info=audit(m['bytes'])['identity'];target=(info['vendor'],info['product'])
   peer=(0x22f6,0x6346) if target==(0x3103,0x907d) else (0x3103,0x907d)
   name=audit(m['bytes'])['decoded'].get('name')
   rows=[row for c in before['crossbar'] for row in c.get('ConnectionMapping',[]) if row.get('ProductName')==name]
   r['recoveryEvidence']=recovery_evidence(before,r.get('observedAfter',{}),target,peer,rows[0]['Address'] if len(rows)==1 else '')
  return r
 finally:
  if a.execute_temporary:
   released=lock_root/'released-locks'
   released.mkdir(exist_ok=True)
   import uuid
   lock.rename(released/(lock.name+"."+uuid.uuid4().hex))

if __name__=='__main__':
 try:
  result=main(); print(json.dumps(result,sort_keys=True))
  if result.get('state') in ('setter-failed','readback-mismatch'): sys.exit(3)
 except EDIDUnavailable as e:
  print(json.dumps(e.as_dict(),sort_keys=True),file=sys.stderr);sys.exit(2)
 except Exception as e:
  print(json.dumps(dict(error=str(e),recoveryValidated=False)),file=sys.stderr);sys.exit(2)
