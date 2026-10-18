"""Static guard: operational sources must stay device-agnostic.

Mentions of the reference hardware belong in documentation, not in code that decides
which display to touch. This test fails if an identity, a digest allowlist or a fixed
two-row assumption creeps back into the GUI, the backend, the probes or the fixtures.
"""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
CODE = ['backend/recovery.py', 'backend/displaypipe.py', 'backend/DisplayPipeIO.m', 'EDIDProbe.m',
        'DisplayProbe.swift', 'GUI/App.swift', 'GUI/Diagnostics.swift', 'GUI/DiagnosticCore.swift',
        'GUI/Presentation.swift', 'GUI/RecoveryClient.swift', 'GUI/RecoveryPresentation.swift',
        'tests/backend/synthetic_fixtures.py']
# Reference-hardware identifiers and friendly names of the one observed setup.
BANNED = ['P275', 'QSN', 'HUAWEI', 'Huawei', '华为', 'HWV', '0x3103', '0x907d', '0x22f6', '0x6346',
          '3103:907d', '22f6:6346', 'ORIGINAL_SHA', 'CANDIDATE_SHA']
# A compiled-in EDID digest or a hardcoded vendor:product table.
DIGEST = re.compile(r'\b[0-9a-f]{64}\b')


class IdentityAgnostic(unittest.TestCase):
    def test_no_hardcoded_display_identity_in_operational_code(self):
        for relative in CODE:
            path = ROOT / relative
            if not path.exists():
                continue
            text = path.read_text()
            for banned in BANNED:
                self.assertNotIn(banned, text, '%s must not hardcode %s' % (relative, banned))
            for match in DIGEST.finditer(text):
                self.fail('%s contains a compiled-in digest %s' % (relative, match.group(0)))

    def test_recovery_discovers_the_target_instead_of_looking_it_up(self):
        source = (ROOT / 'backend/recovery.py').read_text()
        for signal in ('def analyze(', 'def monitor_name(', 'def port_label(', 'originalSHA256',
                       'candidateSHA256', 'combinationToken', 'noInternalFallback', 'autoRevertOnTimeout'):
            self.assertIn(signal, source)
        self.assertNotIn('NAMES=', source)

    def test_gui_builds_rows_from_the_live_snapshot(self):
        presentation = (ROOT / 'GUI/Presentation.swift').read_text()
        app = (ROOT / 'GUI/App.swift').read_text()
        self.assertIn('externalCards', presentation)
        self.assertNotIn('HWV', app)
        self.assertNotIn('P275', app)
        self.assertNotIn('targetCards(', app)
        probe = (ROOT / 'EDIDProbe.m').read_text()
        self.assertIn('0xfc', probe, 'the read-only probe must expose EDID descriptor 0xFC monitor names')


if __name__ == '__main__':
    unittest.main()
