#!/usr/bin/env python3
"""Read-only readiness check against the live inventory. Never calls a display setter.

Run this on the machine that is currently showing a fault. It classifies the live snapshot,
proves the candidate pipeline can handle the selected display's own EDID, plans a dry run and
asserts that no setter was invoked anywhere.
"""
import json, os, pathlib, sys, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DISPLAYPIPE_STATE', str(ROOT / '.build' / 'live-readiness'))
import displaypipe as dp
import recovery as r


class LiveReadiness(unittest.TestCase):
    def test_live_inventory_is_classified_and_never_written(self):
        calls = []

        def forbidden(*args, **kw):
            calls.append(args)
            raise AssertionError('the readiness check must never touch a setter')

        engine = r.Engine(setter=forbidden)
        snapshot = dp.inventory()                      # read-only enumeration
        view = engine.inspect(snapshot)
        print('LIVE_READINESS', json.dumps(dict(kind=view['kind'], summary=view['summary'], problems=view['problems'],
                                                target=view['target'], peers=view['peers'],
                                                internalOnline=view['internalOnline'], orderLabel=view['orderLabel'],
                                                countdownSeconds=view['countdownSeconds']),
                                           ensure_ascii=False, sort_keys=True))
        self.assertEqual(calls, [], 'no setter may be called')
        self.assertIn(view['kind'], ('already-healthy', 'ready'),
                      'the live state must be classified as healthy or ready, not refused')
        if view['kind'] == 'ready':
            target = view['_targetSlot']
            edid = dp.service_edid(target['service'])   # this display's own freshly read EDID
            candidate = dp.candidate(edid, r.CAP_HZ)
            self.assertEqual(candidate['bytes'][8:18], edid[8:18], 'identity must be preserved')
            self.assertEqual(candidate['audit']['unsupported'], [], 'the candidate must audit clean')
            print('LIVE_CANDIDATE_OK', json.dumps(dict(sha256=candidate['sha256'], maxHz=candidate['maxHz'],
                                                       dropped=candidate['dropped'],
                                                       retainedAboveCap=candidate['retainedAboveCap'],
                                                       capAllowanceRule=candidate['capAllowanceRule']),
                                                  ensure_ascii=False, sort_keys=True))
            plan = engine.run()                          # dry run: backup + candidate, no write
            self.assertEqual(plan['state'], 'dry-run')
            self.assertFalse(plan['setterCalled'])
            self.assertEqual(calls, [], 'a dry run must not call a setter')


if __name__ == '__main__':
    unittest.main()
