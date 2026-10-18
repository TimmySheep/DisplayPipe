"""Public, deterministic EDID fixtures constructed from fields, never captures.

The 384-byte panel exercises a 4K60 preferred DTD, a 48..160 Hz range, CTA
video/HDMI Forum blocks and DisplayID 4K120/144/160 timings. Vendor codes,
product codes, serials, monitor names, registry paths and service IDs are all
invented here: the repository hardcodes no real monitor identity, and the
backend/recovery source is verified to contain none. These bytes are NOT a
validated monitor EDID and must never be applied to hardware.
No fixture is read from a local monitor, private reference or live inventory.
"""


# Byte positions in our explicitly constructed CTA block, not a captured layout.
HF_VRR_MIN_OFFSET = 128 + 8 + 1 + 8
HF_VRR_MAX_OFFSET = HF_VRR_MIN_OFFSET + 1
RANGE_MAX_OFFSET = 90 + 6

# Invented identities. Nothing below corresponds to a physical display.
TARGET_VENDOR, TARGET_PRODUCT, TARGET_SERIAL = 0x1a2b, 0x3001, 0x11
PEER_VENDOR, PEER_PRODUCT, PEER_SERIAL = 0x2b3c, 0x4002, 0x22
TARGET_NAME = 'SYNTHETIC'
PEER_NAME = 'SYNTHETIC-2'
INTERNAL_VENDOR, INTERNAL_PRODUCT, INTERNAL_SERIAL = 0x3c4d, 0x5003, 0x33

# Two external ports: index 1 carries the primary panel, index 0 the peer.
TARGET_PORT, PEER_PORT = 1, 0


def _checksum(block):
    block[127] = (-sum(block[:127])) % 256
    return bytes(block)


def _preferred_dtd():
    """Invented 3840x2160/60 timing: 4400*2250*60 = 594 MHz."""
    d = bytearray(18)
    d[:2] = (594000000 // 10000).to_bytes(2, 'little')
    for start, active, blank in ((2, 3840, 560), (5, 2160, 90)):
        d[start] = active & 255
        d[start + 1] = blank & 255
        d[start + 2] = ((active >> 8) << 4) | (blank >> 8)
    d[8:12] = bytes((176, 88, 0x8a, 0))
    d[17] = 0x1e
    return d


def _displayid_timing(hz, stored_bias=0):
    """Type I descriptor, with an exactly integral synthetic refresh rate by default.

    ``stored_bias`` adds one 10 kHz unit to the stored pixel clock, which is how real firmware
    rounding pushes a nominal 120 Hz mode a few thousandths of a hertz above the cap.
    """
    d = bytearray(20)
    d[:3] = (4400 * 2250 * hz // 10000 - 1 + stored_bias).to_bytes(3, 'little')
    for offset, value in ((4, 3840), (6, 560), (8, 176), (10, 88),
                          (12, 2160), (14, 90), (16, 8), (18, 10)):
        d[offset:offset + 2] = (value - 1).to_bytes(2, 'little')
    return d


def _name_descriptor(name):
    """Base descriptor 0xFC. Exactly 13 bytes of payload plus newline padding."""
    text = (name + '\n')[0:13]
    return b'\x00\x00\x00\xfc\x00' + text.ljust(13).encode('ascii')


def panel_edid(vendor=None, product=None, serial=None, name=None, range_offset_bits=0,
               range_formula=1, displayid_stored_bias=0):
    """Build from zeroed blocks; no copied EDID payload or private file I/O."""
    vendor = TARGET_VENDOR if vendor is None else vendor
    product = TARGET_PRODUCT if product is None else product
    serial = TARGET_SERIAL if serial is None else serial
    name = TARGET_NAME if name is None else name
    base = bytearray(128)
    base[:8] = bytes.fromhex('00ffffffffffff00')
    base[8:10] = vendor.to_bytes(2, 'big')
    base[10:12] = product.to_bytes(2, 'little')
    base[12:16] = serial.to_bytes(4, 'little')
    base[16:20] = bytes((1, 30, 1, 4))
    base[20] = 0x80
    base[38:54] = b'\x01\x01' * 8
    base[54:72] = _preferred_dtd()
    base[72:90] = b'\x00\x00\x00\xff\x000000000000000'
    base[90:108] = bytes((0, 0, 0, 0xfd, range_offset_bits, 48, 160, 30, 250, 200, range_formula)) + bytes(7)
    base[108:126] = _name_descriptor(name)
    base[126] = 2

    cta = bytearray(128)
    cta[:4] = bytes((2, 3, 19, 0))
    cta[4:8] = bytes((0x43, 16, 97, 118))  # Video: 1080p60, 4K60, 4K120.
    cta[8:19] = bytes((0x6a, 0xd8, 0x5d, 0xc4, 1, 120, 0, 0, 0, 48, 120))

    payload = b''.join(_displayid_timing(hz, displayid_stored_bias if hz == 120 else 0)
                       for hz in (120, 144, 160))
    displayid = bytearray(128)
    displayid[:8] = bytes((0x70, 0x12, 3 + len(payload), 0, 0, 3, 1, len(payload)))
    displayid[8:8 + len(payload)] = payload
    end = 5 + displayid[2]
    displayid[end] = (-sum(displayid[1:end])) % 256
    return _checksum(base) + _checksum(cta) + _checksum(displayid)


def peer_edid():
    """A second, distinct display of the same supported class."""
    return panel_edid(vendor=PEER_VENDOR, product=PEER_PRODUCT, serial=PEER_SERIAL, name=PEER_NAME)


def unsupported_edid():
    """Checksummed unknown extension, for fail-closed audit/candidate tests."""
    blocks = bytearray(panel_edid())
    extension = bytearray(blocks[128:256])
    extension[0] = 0x99
    blocks[128:256] = _checksum(extension)
    return bytes(blocks)


def quantized_120_edid():
    """A panel whose stored DisplayID pixel clock decodes its 4K120 mode ~0.001 Hz above 120.

    Real firmware rounds the stored clock, so a nominal 120 Hz mode can decode as
    120.001-120.006 Hz. The candidate must keep that nominal mode (see cap_allowance) while a
    genuinely above-cap mode is still dropped.
    """
    return panel_edid(displayid_stored_bias=1)


# ---- synthetic snapshot builders (invented registry identifiers) ----

def port_path(index):
    return 'SYNTHETIC:/displaypipe-test/dispext%d:dcpav-service-epic:0/DCPAVServiceProxy' % index


def service(edid, index, service_id=None, copy_status=0):
    item = dict(serviceID=service_id or 'synthetic-service-%d' % index, path=port_path(index),
                location='External', copyStatus=copy_status)
    item['edid'] = edid.hex() if edid is not None else None
    return item


def port_row(index, name='', pipes=(), max_pipes=1, address=None, role=None):
    row = dict(Address=address if address else '0.%d.0' % (index + 2), ProductName=name,
               PipeIDs=list(pipes), MaxPipes=max_pipes)
    row['role'] = role if role is not None else ('DCPEXT%d' % index if name else '')
    return row


def online_display(edid=None, builtin=False, refresh_hz=120.0, display_id=None, vendor=None, product=None, serial=None):
    if edid is not None:
        vendor, product = int.from_bytes(edid[8:10], 'big'), int.from_bytes(edid[10:12], 'little')
        serial = int.from_bytes(edid[12:16], 'little')
    elif builtin:
        vendor, product, serial = INTERNAL_VENDOR, INTERNAL_PRODUCT, INTERNAL_SERIAL
    return dict(id=display_id if display_id is not None else (1 if builtin else 3),
                builtin=int(bool(builtin)), vendor=vendor or 0, product=product or 0,
                serial=serial or 0, refreshHz=refresh_hz, pixelWidth=3840, pixelHeight=2160)


def inventory(rows, services, online):
    return dict(schema=1, readOnly=True, services=list(services), online=list(online),
                crossbar=[{'IOClass': 'AppleDisplayConnectionManager', 'ConnectionMapping': list(rows)}])


def healthy_inventory(hz=120.0, internal=True):
    """Both externals online with exactly one Pipe each: no recovery wanted."""
    online = [online_display(edid=panel_edid()), online_display(edid=peer_edid())]
    if internal:
        online.insert(0, online_display(builtin=True))
    return inventory([port_row(TARGET_PORT, TARGET_NAME, (1,), max_pipes=1),
                      port_row(PEER_PORT, PEER_NAME, (0,), max_pipes=1)],
                     [service(panel_edid(), TARGET_PORT), service(peer_edid(), PEER_PORT)], online)


def fault_inventory(order='standard', internal=True, hz=120.0, peer_port_row=True,
                    peer_service=None, peer_service_edid=None, peer_pipes=(), target_pipes=(1, 0)):
    """Fault: one online external occupies two Pipes while the peer port has none.

    order='standard'  -> the primary port (1) hogs; peer port (0) is missing.
    order='reverse'   -> the peer port (0) hogs; the primary port (1) is missing.
    peer_service      -> 'readable' or 'unreadable' synthetic service on the peer port.
    peer_port_row=False removes the empty peer port row, i.e. no peer evidence at all.
    """
    target_port = PEER_PORT if order == 'reverse' else TARGET_PORT
    missing_port = TARGET_PORT if order == 'reverse' else PEER_PORT
    target_edid = peer_edid() if order == 'reverse' else panel_edid()
    rows = [port_row(target_port, peer_name(target_port), target_pipes, max_pipes=2)]
    if peer_port_row:
        if peer_pipes:
            rows.append(port_row(missing_port, peer_name(missing_port), peer_pipes, max_pipes=2))
        else:
            rows.append(port_row(missing_port, '', (), role=''))
    services = [service(target_edid, target_port)]
    if peer_service == 'readable':
        services.append(service(peer_service_edid if peer_service_edid is not None else other_edid(order),
                                missing_port, service_id='synthetic-peer-service'))
    elif peer_service == 'unreadable':
        services.append(service(None, missing_port, service_id='synthetic-peer-service', copy_status=7))
    online = [online_display(edid=target_edid)]
    if internal:
        online.insert(0, online_display(builtin=True))
    return inventory(rows, services, online, )


def peer_name(port):
    return PEER_NAME if port == PEER_PORT else TARGET_NAME


def other_edid(order):
    """The EDID of the display that is NOT the target for a given order."""
    return peer_edid() if order == 'standard' else panel_edid()


def target_edid(order='standard'):
    return panel_edid() if order == 'standard' else peer_edid()


def target_identity(order='standard'):
    edid = target_edid(order)
    return (int.from_bytes(edid[8:10], 'big'), int.from_bytes(edid[10:12], 'little'),
            int.from_bytes(edid[12:16], 'little'))


def peer_identity(order='standard'):
    edid = other_edid(order)
    return (int.from_bytes(edid[8:10], 'big'), int.from_bytes(edid[10:12], 'little'),
            int.from_bytes(edid[12:16], 'little'))


def recovered_inventory(order='standard', internal=True, hz=120.0, missing_port_row=False):
    """Post-recovery snapshot: both externals online, one distinct Pipe each."""
    target_port = PEER_PORT if order == 'reverse' else TARGET_PORT
    peer_port = TARGET_PORT if order == 'reverse' else PEER_PORT
    rows = [port_row(target_port, peer_name(target_port), (1,), max_pipes=1),
            port_row(peer_port, peer_name(peer_port), (0,), max_pipes=1)]
    online = [online_display(edid=target_edid(order)), online_display(edid=other_edid(order))]
    if internal:
        online.insert(0, online_display(builtin=True))
    return inventory(rows, [service(target_edid(order), target_port), service(other_edid(order), peer_port)], online)
