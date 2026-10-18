"""Recovery tests: dynamic per-run identification, countdown auto-revert, no-fallback opt-in.

Public synthetic fixtures only; this file reads no private capture, real EDID or live
inventory. Every test injects an inventory and a setter, and the real subprocess path is
guarded: reaching a native display setter from a test is a hard failure.
"""
import contextlib, copy, io, json, os, pathlib, runpy, sys, unittest, uuid
from unittest.mock import patch
import synthetic_fixtures as fixtures
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
import displaypipe as dp
try:
    import recovery as r
except ImportError:
    r = None


class Harness(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / '.build' / 'recovery-tests' / uuid.uuid4().hex
        self.root.mkdir(parents=True)
        state = patch.dict(os.environ, {'DISPLAYPIPE_STATE': str(self.root)})
        state.start(); self.addCleanup(state.stop)
        self.assertIsNotNone(r, 'manual recovery orchestrator is missing')
        native = dp.subprocess.check_output

        def read_only_native(args, *a, **kw):
            if 'temporary-write' in args:
                self.fail('tests must never invoke a native display setter')
            return native(args, *a, **kw)
        guard = patch.object(dp.subprocess, 'check_output', side_effect=read_only_native)
        guard.start(); self.addCleanup(guard.stop)
        self.clock = [1000.0]
        self.calls = []

    def tick(self, seconds):
        self.clock[0] += seconds

    def now(self):
        return self.clock[0]

    def engine(self, snap, order='standard', apply_outcome='success', observe=None, reset_outcome='ok'):
        """Mutable synthetic snapshot + recording setter; observe(current,reads) may mutate."""
        current = copy.deepcopy(snap)
        target_port = fixtures.PEER_PORT if order == 'reverse' else fixtures.TARGET_PORT
        reads = [0]

        def setter(mode, run):
            self.calls.append(mode)
            if mode == 0 and reset_outcome == 'fail':
                raise ValueError('synthetic native reset failure')
            data = (pathlib.Path(run) / ('candidate.bin' if mode else 'original.bin')).read_bytes()
            for service in current['services']:
                if 'dispext%d:' % target_port in service.get('path', ''):
                    service['edid'] = data.hex()
            if mode and apply_outcome == 'success':
                recovered = fixtures.recovered_inventory(order=order)
                for service in recovered['services']:
                    if 'dispext%d:' % target_port in service.get('path', ''):
                        service['edid'] = data.hex()
                current.clear(); current.update(recovered)
            return dict(setterStatus=0, copyStatus=0, effectiveEDID=data.hex())

        def read():
            reads[0] += 1
            if observe:
                observe(current, reads[0])
            return copy.deepcopy(current)
        return r.Engine(self.root, read, setter, self.tick, self.now), current, reads

    def token(self, order='standard'):
        return r.analyze(fixtures.fault_inventory(order=order))['combinationToken']


class DynamicIdentification(Harness):
    def test_no_global_identity_or_digest_allowlist(self):
        source = (ROOT / 'backend/recovery.py').read_text()
        for banned in ('ORIGINAL_SHA', 'CANDIDATE_SHA', 'P275', 'QSN', 'HUAWEI', '0x3103', '0x907d', '0x22f6', '0x6346'):
            self.assertNotIn(banned, source, banned)
        self.assertFalse([n for n in dir(r) if 'SHA' in n.upper() or 'ALLOW' in n.upper()], 'no global digest/allowlist constant')
        for token in source.split():
            if len(token) == 64 and all(c in '0123456789abcdef' for c in token):
                self.fail('compiled-in 64-hex digest found: ' + token)

    def test_dry_run_uses_dynamic_target_and_records_per_run_digests(self):
        engine, _, _ = self.engine(fixtures.fault_inventory())
        out = engine.run()
        self.assertEqual(out['state'], 'dry-run')
        self.assertEqual(self.calls, [])
        run = pathlib.Path(out['runDirectory'])
        manifest = json.loads((run / 'manifest.json').read_text())
        original = fixtures.panel_edid()
        self.assertEqual(manifest['originalSHA256'], dp.sha(original))
        self.assertEqual(manifest['identity'], list(r.identity(original)))
        self.assertEqual(manifest['serviceID'], 'synthetic-service-1')
        self.assertTrue(manifest['path'].endswith('dispext1:dcpav-service-epic:0/DCPAVServiceProxy'))
        self.assertEqual(manifest['candidateSHA256'], dp.sha((run / 'candidate.bin').read_bytes()))
        self.assertEqual(dp.candidate(original, manifest['capHz'])['bytes'], (run / 'candidate.bin').read_bytes())
        self.assertEqual(manifest['auditUnsupported'], [])
        self.assertEqual(manifest['countdownSeconds'], r.COUNTDOWN_SECONDS)
        self.assertTrue(manifest['autoRevertOnTimeout'])
        self.assertFalse(manifest['noInternalFallback'])
        self.assertIn('SYNTHETIC', manifest['targetName'])
        backup = dp.load_backup(run / 'original.bin')
        self.assertEqual(backup['bytes'], original)
        self.assertEqual(backup['serviceID'], 'synthetic-service-1')
        self.assertFalse(out['physicalInputConfirmed'])
        self.assertFalse(out['setterCalled'])

    def test_target_is_the_double_pipe_external_not_a_fixed_row(self):
        view = r.analyze(fixtures.fault_inventory(order='reverse'))
        self.assertEqual(view['kind'], 'ready')
        self.assertEqual(view['target']['port'], 'DCPEXT0')
        self.assertEqual(view['target']['name'], fixtures.PEER_NAME)
        self.assertTrue(any(p['peerClass'] == 'empty-port' for p in view['peers']))
        three = fixtures.fault_inventory()
        three['crossbar'][0]['ConnectionMapping'].append(fixtures.port_row(2, 'THIRD', (), role=''))
        more = r.analyze(three)
        self.assertEqual(more['kind'], 'ready')
        self.assertEqual(len(more['peers']), 2)
        piped = fixtures.fault_inventory()
        piped['crossbar'][0]['ConnectionMapping'].append(fixtures.port_row(2, 'THIRD', (2,), role='DCPEXT2'))
        self.assertEqual(r.analyze(piped)['kind'], 'refused')

    def test_healthy_and_unrecoverable_states(self):
        self.assertEqual(r.analyze(fixtures.healthy_inventory())['kind'], 'already-healthy')
        no_peer = r.analyze(fixtures.fault_inventory(peer_port_row=False))
        self.assertEqual(no_peer['kind'], 'refused')
        self.assertTrue(any('证据' in problem for problem in no_peer['problems']))
        broken = fixtures.fault_inventory()
        broken['services'][0]['copyStatus'] = 7
        broken['services'][0]['edid'] = None
        self.assertEqual(r.analyze(broken)['kind'], 'refused')
        self.assertTrue(any('EDID' in problem for problem in r.analyze(broken)['problems']))
        duplicate = fixtures.fault_inventory()
        duplicate['services'].append(fixtures.service(fixtures.panel_edid(), fixtures.PEER_PORT, service_id='duplicate'))
        duplicate['crossbar'][0]['ConnectionMapping'][1].update(ProductName=fixtures.TARGET_NAME, role='DCPEXT0')
        self.assertEqual(r.analyze(duplicate)['kind'], 'refused')

    def test_refusal_and_not_recoverable_are_distinguishable(self):
        # A recognized double-Pipe target with a failing gate is a refusal...
        broken = fixtures.fault_inventory()
        broken['services'][0]['edid'] = None
        refused = r.analyze(broken)
        self.assertEqual(refused['kind'], 'refused')
        self.assertIsNotNone(refused['target'], 'the target was still selected')
        self.assertTrue(refused['refusals'])
        # ...while a shape that is not a recovery target stays unsupported.
        unsupported = r.analyze(fixtures.healthy_inventory())
        self.assertEqual(unsupported['kind'], 'already-healthy')
        no_hog_no_peer = fixtures.inventory([fixtures.port_row(fixtures.TARGET_PORT, fixtures.TARGET_NAME, (1,))],
                                            [fixtures.service(fixtures.panel_edid(), fixtures.TARGET_PORT)],
                                            [fixtures.online_display(builtin=True), fixtures.online_display(edid=fixtures.panel_edid())])
        self.assertEqual(r.analyze(no_hog_no_peer)['kind'], 'already-healthy')
        engine = r.Engine(self.root, lambda: copy.deepcopy(broken))
        self.assertEqual(engine.status()['state'], 'refused')
        with self.assertRaises(ValueError):
            engine.run(True, True)
        self.assertEqual(self.calls, [])

    def test_status_and_plan_payloads_are_json_serializable(self):
        for snap in (fixtures.healthy_inventory(), fixtures.fault_inventory(),
                     fixtures.fault_inventory(order='reverse'), fixtures.fault_inventory(internal=False)):
            with self.subTest(snapshot=snap['crossbar'][0]['ConnectionMapping'][0]['ProductName']):
                engine = r.Engine(self.root, lambda snap=snap: copy.deepcopy(snap))
                payload = engine.status()
                json.dumps(payload)                                   # must never raise on bytes handles
                self.assertNotIn('_slots', payload.get('analysis', {}))
                self.assertNotIn('_targetSlot', payload.get('analysis', {}))
        plan = r.Engine(self.root, lambda: copy.deepcopy(fixtures.fault_inventory())).run()
        json.dumps(plan)
        self.assertEqual(plan['state'], 'dry-run')

    def test_peer_must_be_of_the_supported_class_when_readable(self):
        readable = fixtures.fault_inventory(peer_service='readable', peer_port_row=False)
        self.assertEqual(r.analyze(readable)['kind'], 'ready')
        self.assertEqual(r.analyze(readable)['peers'][0]['peerClass'], 'audited-class')
        unreadable = fixtures.fault_inventory(peer_service='unreadable', peer_port_row=False)
        self.assertEqual(r.analyze(unreadable)['kind'], 'ready')
        self.assertEqual(r.analyze(unreadable)['peers'][0]['peerClass'], 'unreadable-edid')
        unsupported = fixtures.fault_inventory(peer_service='readable', peer_service_edid=fixtures.unsupported_edid(),
                                               peer_port_row=False)
        view = r.analyze(unsupported)
        self.assertEqual(view['kind'], 'refused')
        self.assertTrue(any('类别' in problem for problem in view['problems']))

    def test_status_exposes_dynamic_summary_and_analysis(self):
        healthy = r.Engine(self.root, lambda: copy.deepcopy(fixtures.healthy_inventory())).status()
        self.assertEqual(healthy['state'], 'already-healthy')
        self.assertIn('外接端口', healthy['summary'])
        self.assertTrue(healthy['analysis']['internalOnline'])
        fault = r.Engine(self.root, lambda: copy.deepcopy(fixtures.fault_inventory())).status()
        self.assertEqual(fault['state'], 'ready')
        self.assertIn('orderLabel', fault['analysis'])
        self.assertIn('orderVerified', fault['analysis'])
        self.assertIn('双 Pipe', fault['summary'])
        self.assertEqual(fault['analysis']['countdownSeconds'], r.COUNTDOWN_SECONDS)


class SymmetricOrders(Harness):
    def test_both_cable_orders_are_recoverable_without_an_extra_acknowledgement(self):
        for order in ('standard', 'reverse'):
            with self.subTest(order=order):
                self.calls = []
                engine, _, _ = self.engine(fixtures.fault_inventory(order=order), order=order)
                view = engine.inspect(fixtures.fault_inventory(order=order))
                self.assertEqual(view['kind'], 'ready')
                self.assertNotIn('requiresAcknowledgement', view, 'no extra gate beyond the normal confirmation')
                self.assertTrue(view['orderLabel'])
                out = engine.run(True, True)
                self.assertEqual(out['state'], 'cg-restored-reset-verified')
                self.assertEqual(self.calls, [1, 0])

    def test_target_selection_is_symmetric_and_the_order_label_is_honest(self):
        forward = self.engine(fixtures.fault_inventory(order='standard'))
        reverse = self.engine(fixtures.fault_inventory(order='reverse'), order='reverse')
        self.assertEqual(forward[0].inspect(fixtures.fault_inventory())['target']['port'], 'DCPEXT1')
        self.assertEqual(reverse[0].inspect(fixtures.fault_inventory(order='reverse'))['target']['port'], 'DCPEXT0')
        first = forward[0].inspect(fixtures.fault_inventory())
        self.assertFalse(first['orderVerified'])
        self.assertIn('尚未验证', first['orderLabel'])
        forward[0].record(first['combinationToken'], 'recovery-verified', self.root, first['combination'])
        later = forward[0].inspect(fixtures.fault_inventory())
        self.assertTrue(later['orderVerified'])
        self.assertIn('验证过', later['orderLabel'])
        # The other order stays labelled unverified; the label never blocks a write.
        other = reverse[0].inspect(fixtures.fault_inventory(order='reverse'))
        self.assertFalse(other['orderVerified'])
        self.assertNotEqual(other['combinationToken'], first['combinationToken'])

    def test_candidate_is_generated_from_the_targets_own_edid_in_both_orders(self):
        for order in ('standard', 'reverse'):
            with self.subTest(order=order):
                engine, _, _ = self.engine(fixtures.fault_inventory(order=order), order=order)
                out = engine.run()
                self.assertEqual(out['state'], 'dry-run')
                run = pathlib.Path(out['runDirectory'])
                manifest = json.loads((run / 'manifest.json').read_text())
                own = fixtures.target_edid(order)
                self.assertEqual(manifest['originalSHA256'], dp.sha(own))
                self.assertEqual(manifest['identity'], list(r.identity(own)))
                candidate = (run / 'candidate.bin').read_bytes()
                self.assertEqual(manifest['candidateSHA256'], dp.sha(candidate))
                self.assertNotEqual(candidate, own)
                self.assertEqual(candidate[8:18], own[8:18])
                self.assertEqual(dp.candidate(own, 120)['bytes'], candidate)
                self.assertIn(manifest['orderLabel'], ('已在本机验证过的接入顺序',
                                                       '本机尚未验证的接入顺序（实验性；写入依赖倒计时自动撤销）'))


class Countdown(Harness):
    def test_countdown_timeout_auto_reverts_and_verifies_original_bytes(self):
        engine, current, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout')
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'auto-reverted-cg-not-restored')
        self.assertTrue(out['autoReverted'])
        self.assertTrue(out['setterCalled'])
        self.assertEqual(self.calls, [1, 0])
        self.assertEqual(self.now() - 1000.0, r.COUNTDOWN_SECONDS)
        target = [s for s in current['services'] if 'dispext1:' in s['path']][0]
        self.assertEqual(bytes.fromhex(target['edid']), fixtures.panel_edid())
        self.assertEqual(engine.pending(), [])
        run = pathlib.Path(out['runDirectory'])
        events = [json.loads(p.read_text())['state'] for p in sorted(run.glob('event-*.json'))]
        self.assertIn('auto-reverting', events)
        self.assertEqual(events[-1], 'auto-reverted-cg-not-restored')

    def test_auto_reverted_verified_when_evidence_settles_after_the_countdown(self):
        # Reads 1-3 are the plan/preflight/readback; the 21 countdown samples follow, so the
        # displays only report the capped rate from read 25 on: the normal reset needs three
        # stable samples and never gets them, and the countdown revert does the work instead.
        def observe(current, reads):
            for display in current['online']:
                if not display.get('builtin'):
                    display['refreshHz'] = 60.0 if reads <= 24 else 120.0
        engine, _, _ = self.engine(fixtures.fault_inventory(), observe=observe)
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'auto-reverted-verified')
        self.assertTrue(out['autoReverted'])
        self.assertTrue(out['bothOnline'])
        self.assertEqual(self.calls, [1, 0])
        self.assertEqual(engine.pending(), [])

    def test_timeout_with_changed_service_identity_keeps_pending_without_writing(self):
        def observe(current, reads):
            if reads == 8:
                for service in current['services']:
                    service['path'] = service['path'].replace('dispext1:', 'dispext9:')
        engine, _, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', observe=observe)
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertEqual(self.calls, [1])
        self.assertTrue(out['pending'])
        self.assertEqual(len(engine.pending()), 1)
        self.assertEqual(engine.status()['state'], 'recovery-needed')

    def test_auto_revert_failure_keeps_pending_and_never_claims_a_revert(self):
        engine, current, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', reset_outcome='fail')
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertFalse(out['autoReverted'])
        self.assertEqual(self.calls, [1, 0])
        target = [s for s in current['services'] if 'dispext1:' in s['path']][0]
        self.assertNotEqual(bytes.fromhex(target['edid']), fixtures.panel_edid())
        self.assertEqual(len(engine.pending()), 1)

    def test_manual_undo_refuses_changed_registry_identity(self):
        engine, current, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', reset_outcome='fail')
        engine.run(True, True, self.token())
        current['services'][0]['serviceID'] = 'replacement'
        out = engine.undo(True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertEqual(self.calls, [1, 0])
        self.assertTrue(engine.pending())


class HealthyNoOp(Harness):
    def test_two_online_single_pipe_externals_never_write(self):
        engine, _, _ = self.engine(fixtures.healthy_inventory())
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'already-healthy')
        self.assertEqual(self.calls, [])
        self.assertFalse(out['setterCalled'])
        self.assertEqual(engine.status()['state'], 'already-healthy')

    def test_closed_lid_healthy_and_optin_are_still_noops(self):
        engine, _, _ = self.engine(fixtures.healthy_inventory(internal=False))
        out = engine.run(True, True, True)
        self.assertEqual(out['state'], 'already-healthy')
        self.assertEqual(self.calls, [])
        self.assertFalse(out['setterCalled'])


class NoInternalFallback(Harness):
    def test_internal_offline_refuses_write_without_explicit_optin(self):
        engine, _, _ = self.engine(fixtures.fault_inventory(internal=False))
        with self.assertRaisesRegex(ValueError, '无内屏回退'):
            engine.run(True, True)
        self.assertEqual(self.calls, [])
        self.assertTrue(engine.status()['analysis']['requiresNoInternalFallback'])
        plan = engine.run()
        self.assertEqual(plan['state'], 'dry-run')
        self.assertFalse(plan['internalOnline'])
        self.assertEqual(self.calls, [])

    def test_internal_offline_with_optin_writes_records_mode_and_auto_reverts(self):
        engine, _, _ = self.engine(fixtures.fault_inventory(internal=False), apply_outcome='timeout')
        out = engine.run(True, True, True)
        self.assertEqual(out['state'], 'auto-reverted-cg-not-restored')
        self.assertEqual(self.calls, [1, 0])
        manifest = json.loads((pathlib.Path(out['runDirectory']) / 'manifest.json').read_text())
        self.assertTrue(manifest['noInternalFallback'])
        self.assertFalse(manifest['internalOnlineAtPlan'])
        self.assertTrue(manifest['orderLabel'])

    def test_backend_has_no_interactive_step_in_the_revert_path(self):
        source = (ROOT / 'backend/recovery.py').read_text()
        self.assertIn('auto-reverting', source)
        self.assertIn('autoRevertOnTimeout', source)
        self.assertNotIn('input(', source)
        client = (ROOT / 'GUI/RecoveryClient.swift').read_text() + (ROOT / 'GUI/App.swift').read_text()
        self.assertNotIn('--keep', client)


class TransactionSafety(Harness):
    def test_pending_survives_restart_and_is_reported(self):
        engine, current, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', reset_outcome='fail')
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        fresh = r.Engine(self.root, lambda: copy.deepcopy(current))
        self.assertEqual(fresh.status()['state'], 'recovery-needed')
        self.assertEqual(len(fresh.status()['pending']), 1)

    def test_bad_immediate_readback_keeps_pending_without_reset(self):
        engine, _, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout')
        original = engine.setter

        def bad(mode, run):
            result = original(mode, run)
            result['effectiveEDID'] = 'bad'
            return result
        engine.setter = bad
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertEqual(self.calls, [1])
        self.assertTrue(engine.pending())

    def test_non_mapping_native_result_is_an_explicit_refusal_not_a_traceback(self):
        engine, _, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout')

        def malformed(mode, run):                    # a malformed native result
            self.calls.append(mode)
            return 7
        engine.setter = malformed
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertIn('未返回映射结果', out['error'])
        self.assertEqual(self.calls, [1])
        self.assertTrue(engine.pending())

    def test_missing_readback_stops_the_run_before_the_countdown_ends(self):
        def observe(current, reads):
            if reads == 5:
                for service in current['services']:
                    if 'dispext1:' in service['path']:
                        service['edid'] = None
        engine, _, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', observe=observe)
        out = engine.run(True, True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertEqual(self.calls, [1])

    def test_manifest_tampering_blocks_the_write(self):
        engine, _, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', reset_outcome='fail')
        out = engine.run(True, True)
        run = pathlib.Path(out['runDirectory'])
        manifest = json.loads((run / 'manifest.json').read_text())
        manifest['originalSHA256'] = dp.sha(fixtures.peer_edid())
        (run / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True))
        out = engine.undo(True)
        self.assertEqual(out['state'], 'recovery-needed')
        self.assertEqual(self.calls, [1, 0])

    def test_missing_write_confirmation_never_writes(self):
        engine, _, _ = self.engine(fixtures.fault_inventory())
        with self.assertRaises(ValueError):
            engine.run(True, False)
        self.assertEqual(self.calls, [])

    def test_global_lock_refuses_second_operation(self):
        engine, _, _ = self.engine(fixtures.fault_inventory())
        with engine.locked():
            with self.assertRaises(ValueError):
                engine.run(True, True, self.token())
        self.assertEqual(self.calls, [])

    def test_physical_acceptance_is_a_separate_explicit_record(self):
        engine, _, _ = self.engine(fixtures.fault_inventory())
        run = self.root / 'runs' / 'accept-test'; run.mkdir(parents=True)
        engine.event(run, 'cg-restored-reset-verified', False, bothOnline=True)
        with self.assertRaises(ValueError):
            engine.accept(False)
        self.assertFalse(engine.status()['physicalInputConfirmed'])
        self.assertTrue(engine.accept(True)['physicalInputConfirmed'])
        self.assertFalse(engine.status()['physicalInputConfirmed'])

    def test_undo_records_already_original_without_writing(self):
        engine, current, _ = self.engine(fixtures.fault_inventory(), apply_outcome='timeout', reset_outcome='fail')
        engine.run(True, True, self.token())
        for service in current['services']:
            if 'dispext1:' in service['path']:
                service['edid'] = fixtures.panel_edid().hex()
        out = engine.undo(True)
        self.assertEqual(out['state'], 'undo-verified')
        self.assertFalse(out['setterCalled'])
        self.assertEqual(self.calls, [1, 0])

    def test_native_write_rejects_unvalidated_mac_model(self):
        engine = r.Engine(self.root, lambda: copy.deepcopy(fixtures.fault_inventory()))
        with patch.object(r.subprocess, 'check_output', return_value=b'Mac99,1\n') as command:
            with self.assertRaisesRegex(ValueError, 'Mac14,10'):
                engine.write(1, self.root)
            self.assertEqual(command.call_count, 1)

    def test_core_uses_external_recoverable_scratch(self):
        original = fixtures.panel_edid()
        before = set((self.root / 'scratch-archive').glob('*.bin'))
        dp.core(original)
        archived = list(set((self.root / 'scratch-archive').glob('*.bin')) - before)
        self.assertEqual(len(archived), 1, 'core scratch must be archived outside application, not deleted')
        self.assertEqual(archived[0].read_bytes(), original)

    def test_legacy_cli_lock_is_archived_outside_resources(self):
        original = fixtures.panel_edid(); run = self.root / 'legacy'; run.mkdir()
        backup = run / 'original.bin'; candidate = run / 'candidate.bin'
        identity = {'serviceID': 'synthetic-service-1', 'path': fixtures.port_path(fixtures.TARGET_PORT),
                    'location': 'External'}
        dp.backup(backup, original, identity)
        proposed = dp.candidate(original, 120); candidate.write_bytes(proposed.pop('bytes'))
        pathlib.Path(str(candidate) + '.json').write_text(json.dumps(proposed))
        argv = ['displaypipe', 'apply', '--backup', str(backup), '--candidate', str(candidate),
                '--execute-temporary', '--ack-private-api-unvalidated']
        snap = fixtures.inventory([fixtures.port_row(fixtures.TARGET_PORT, fixtures.TARGET_NAME, (1,))],
                                  [fixtures.service(original, fixtures.TARGET_PORT)], [fixtures.online_display(builtin=True)])
        with patch('sys.argv', argv), patch.object(dp, 'inventory', return_value=snap), patch.object(dp, 'transact', return_value={'state': 'dry-run'}):
            dp.main()
        self.assertEqual(len(list((self.root / 'legacy-locks/released-locks').glob('*'))), 1,
                         'legacy lock must not mutate bundled Resources/build')


class Cli(Harness):
    def run_cli(self, argv, snap, expect_exit=True):
        stdout = io.StringIO()
        with patch('sys.argv', argv), patch.object(dp, 'inventory', return_value=snap), contextlib.redirect_stdout(stdout):
            if expect_exit:
                with self.assertRaises(SystemExit):
                    runpy.run_path(str(ROOT / 'backend/recovery.py'), run_name='__main__')
            else:
                runpy.run_path(str(ROOT / 'backend/recovery.py'), run_name='__main__')
        return json.loads(stdout.getvalue())

    def test_cli_missing_edid_preflight_structured_no_setter(self):
        broken = fixtures.fault_inventory()
        broken['services'][0]['edid'] = None
        value = self.run_cli(['recovery', 'recover', '--execute', '--confirm-private-api-risk'], broken)
        self.assertEqual(value['state'], 'unsupported')
        self.assertEqual(value['code'], 'edid-unavailable')
        self.assertFalse(value['setterCalled'])

    def test_cli_internal_offline_without_optin_reports_no_setter(self):
        snap = fixtures.fault_inventory(internal=False)
        value = self.run_cli(['recovery', 'recover', '--execute', '--confirm-private-api-risk'], snap)
        self.assertEqual(value['state'], 'failure')
        self.assertFalse(value['setterCalled'])
        self.assertIn('无内屏回退', value['error'])

    def test_cli_reverse_order_is_not_refused_and_needs_no_extra_flag(self):
        snap = fixtures.fault_inventory(order='reverse')
        value = self.run_cli(['recovery', 'recover', '--confirm-private-api-risk'], snap, expect_exit=False)
        self.assertEqual(value['state'], 'dry-run')
        self.assertEqual(value['targetPort'], 'DCPEXT0')
        self.assertFalse(value['orderVerified'])
        self.assertIn('尚未验证', value['orderLabel'])
        self.assertFalse(value['setterCalled'])
        self.assertNotIn('ack-unverified-combination', (ROOT / 'backend/recovery.py').read_text(),
                         'no duplicate gate for the other cable order')

    def test_cli_status_is_always_json_and_reports_the_kind(self):
        for snap, expected in ((fixtures.healthy_inventory(), 'already-healthy'),
                               (fixtures.fault_inventory(), 'ready'),
                               (fixtures.fault_inventory(order='reverse'), 'ready')):
            with self.subTest(expected=expected):
                value = self.run_cli(['recovery', 'status'], snap, expect_exit=False)
                self.assertEqual(value['state'], expected)
                self.assertIn('summary', value)
                json.dumps(value)

    def test_cli_requires_both_write_confirmations(self):
        value = self.run_cli(['recovery', 'recover', '--execute'], fixtures.fault_inventory())
        self.assertFalse(value['setterCalled'])

    def test_cli_undo_without_execute_is_a_dry_run(self):
        value = self.run_cli(['recovery', 'undo'], fixtures.fault_inventory(), expect_exit=False)
        self.assertEqual(value['state'], 'dry-run')
        self.assertFalse(value['setterCalled'])


if __name__ == '__main__':
    unittest.main()
