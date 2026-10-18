#!/usr/bin/env python3
"""Losslessly refilter PNG payloads inside ICNS, using only the stdlib.

Packaging-time only. Keep every representation, pixel, ancillary chunk and
non-PNG payload. Unsupported PNG layouts stay byte-identical. No runtime code.
"""
import pathlib, struct, sys, zlib
SIGNATURE=b'\x89PNG\r\n\x1a\n'

def chunks(png):
    offset=8
    while offset<len(png):
        length=struct.unpack('>I',png[offset:offset+4])[0]
        tag=png[offset+4:offset+8]; payload=png[offset+8:offset+8+length]
        if zlib.crc32(tag+payload)&0xffffffff != struct.unpack('>I',png[offset+8+length:offset+12+length])[0]:
            raise ValueError('PNG checksum mismatch')
        yield tag,payload
        offset+=12+length
    if offset!=len(png): raise ValueError('PNG chunk length mismatch')

def chunk(tag,payload):
    return struct.pack('>I',len(payload))+tag+payload+struct.pack('>I',zlib.crc32(tag+payload)&0xffffffff)

def decode_png(png):
    entries=list(chunks(png))
    width,height,depth,color,compression,filtering,interlace=struct.unpack('>IIBBBBB',entries[0][1])
    if depth!=8 or color not in (0,2,4,6) or compression or filtering or interlace:
        raise ValueError('unsupported PNG layout')
    channels={0:1,2:3,4:2,6:4}[color]; stride=width*channels
    raw=zlib.decompress(b''.join(payload for tag,payload in entries if tag==b'IDAT'))
    if len(raw)!=(stride+1)*height: raise ValueError('PNG scanline length mismatch')
    previous=bytearray(stride); pixels=bytearray()
    for y in range(height):
        offset=y*(stride+1); kind=raw[offset]; row=bytearray(raw[offset+1:offset+1+stride])
        for x in range(stride):
            left=row[x-channels] if x>=channels else 0; above=previous[x]; upperleft=previous[x-channels] if x>=channels else 0
            if kind==0: predictor=0
            elif kind==1: predictor=left
            elif kind==2: predictor=above
            elif kind==3: predictor=(left+above)//2
            elif kind==4:
                p=left+above-upperleft; a=abs(p-left); b=abs(p-above); c=abs(p-upperleft)
                predictor=left if a<=b and a<=c else above if b<=c else upperleft
            else: raise ValueError('invalid PNG filter')
            row[x]=(row[x]+predictor)&255
        pixels.extend(row); previous=row
    return (width,height,channels),bytes(pixels)

def optimize_png(png):
    if not png.startswith(SIGNATURE): return png
    try: (width,height,channels),pixels=decode_png(png)
    except ValueError: return png
    stride=width*channels; previous=bytes(stride); filtered=bytearray()
    score=[min(x,256-x) for x in range(256)]
    for y in range(height):
        row=pixels[y*stride:(y+1)*stride]
        sub=bytes((value-(row[x-channels] if x>=channels else 0))&255 for x,value in enumerate(row))
        up=bytes((value-previous[x])&255 for x,value in enumerate(row))
        kind,best=min(enumerate([row,sub,up]),key=lambda pair:sum(score[v] for v in pair[1]))
        filtered.append(kind); filtered.extend(best); previous=row
    compressed=zlib.compress(bytes(filtered),9)
    output=bytearray(SIGNATURE); inserted=False
    for tag,payload in chunks(png):
        if tag==b'IDAT':
            if inserted: continue
            payload=compressed; inserted=True
        output.extend(chunk(tag,payload))
    result=bytes(output)
    if len(result)>=len(png): return png
    if decode_png(result)[1]!=pixels: raise ValueError('lossless pixel verification failed')
    return result

def optimize_icns(source):
    if source[:4]!=b'icns' or struct.unpack('>I',source[4:8])[0]!=len(source): raise ValueError('invalid ICNS header')
    offset=8; entries=bytearray(); cache={}
    while offset<len(source):
        tag,size=struct.unpack('>4sI',source[offset:offset+8])
        if size<8 or offset+size>len(source): raise ValueError('invalid ICNS entry')
        payload=source[offset+8:offset+size]
        if payload not in cache: cache[payload]=optimize_png(payload)
        payload=cache[payload]; entries.extend(struct.pack('>4sI',tag,len(payload)+8)+payload); offset+=size
    return b'icns'+struct.pack('>I',len(entries)+8)+entries

if __name__=='__main__':
    source=pathlib.Path(sys.argv[1]); target=pathlib.Path(sys.argv[2])
    before=source.read_bytes(); after=optimize_icns(before)
    with target.open('xb') as output: output.write(after)
    print('LOSSLESS_ICNS',len(before),'->',len(after),'bytes; all PNG pixels verified')
