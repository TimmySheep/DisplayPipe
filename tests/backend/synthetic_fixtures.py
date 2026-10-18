"""Public, deterministic EDID fixtures constructed from fields, never captures.

The 384-byte panel exercises a 4K60 preferred DTD, a 48..160 Hz range,
CTA video/HDMI Forum blocks and DisplayID 4K120/144/160 timings. Product
codes intentionally match the backend's public model selectors, but every
other field, registry path and service ID below is invented. These bytes
are NOT a validated monitor EDID and must never be applied to hardware.
Recovery tests temporarily substitute only their SHA allowlist constants;
production hashes, parsing, identity checks and transaction gates stay intact.
No fixture is read from a local monitor, private reference or live inventory.
"""


# Byte positions in our explicitly constructed CTA block, not a captured layout.
HF_VRR_MIN_OFFSET = 128 + 8 + 1 + 8
HF_VRR_MAX_OFFSET = HF_VRR_MIN_OFFSET + 1
RANGE_MAX_OFFSET = 90 + 6


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


def _displayid_timing(hz):
    """Type I descriptor, with an exactly integral synthetic refresh rate."""
    d = bytearray(20)
    d[:3] = (4400 * 2250 * hz // 10000 - 1).to_bytes(3, 'little')
    for offset, value in ((4, 3840), (6, 560), (8, 176), (10, 88),
                          (12, 2160), (14, 90), (16, 8), (18, 10)):
        d[offset:offset + 2] = (value - 1).to_bytes(2, 'little')
    return d


def panel_edid():
    """Build from zeroed blocks; no copied EDID payload or private file I/O."""
    base = bytearray(128)
    base[:8] = bytes.fromhex('00ffffffffffff00')
    # Public model identifier, not a device-specific captured identity.
    base[8:10] = (0x3103).to_bytes(2, 'big')
    base[10:12] = (0x907d).to_bytes(2, 'little')
    base[16:20] = bytes((1, 30, 1, 4))
    base[20] = 0x80
    base[38:54] = b'\x01\x01' * 8
    base[54:72] = _preferred_dtd()
    base[72:90] = b'\x00\x00\x00\xfc\x00SYNTHETIC\n   '
    base[90:108] = bytes((0, 0, 0, 0xfd, 0, 48, 160, 30, 250, 200, 1)) + bytes(7)
    base[108:126] = bytes((0, 0, 0, 0x10)) + bytes(14)
    base[126] = 2

    cta = bytearray(128)
    cta[:4] = bytes((2, 3, 19, 0))
    cta[4:8] = bytes((0x43, 16, 97, 118))  # Video: 1080p60, 4K60, 4K120.
    cta[8:19] = bytes((0x6a, 0xd8, 0x5d, 0xc4, 1, 120, 0, 0, 0, 48, 120))

    payload = b''.join(_displayid_timing(hz) for hz in (120, 144, 160))
    displayid = bytearray(128)
    displayid[:8] = bytes((0x70, 0x12, 3 + len(payload), 0, 0, 3, 1, len(payload)))
    displayid[8:8 + len(payload)] = payload
    end = 5 + displayid[2]
    displayid[end] = (-sum(displayid[1:end])) % 256
    return _checksum(base) + _checksum(cta) + _checksum(displayid)


def unsupported_edid():
    """Checksummed unknown extension, for fail-closed audit/candidate tests."""
    blocks = bytearray(panel_edid())
    extension = bytearray(blocks[128:256])
    extension[0] = 0x99
    blocks[128:256] = _checksum(extension)
    return bytes(blocks)


def inventory():
    """Fresh fictional supported-fault state; no real registry identifiers."""
    return {
        'readOnly': True,
        'services': [{
            'serviceID': 'synthetic-service-1',
            'path': 'SYNTHETIC:/displaypipe-test/panel',
            'location': 'External',
            'copyStatus': 0,
            'edid': panel_edid().hex(),
        }],
        'online': [
            {'builtin': 1},
            {'builtin': 0, 'vendor': 0x3103, 'product': 0x907d,
             'serial': 0, 'refreshHz': 120},
        ],
        'crossbar': [{'ConnectionMapping': [
            {'ProductName': 'P275MV PLUS', 'Address': 'synthetic-panel-port',
             'PipeIDs': [1, 0]},
        ]}],
    }
