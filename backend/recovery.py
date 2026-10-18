#!/usr/bin/env python3
"""Manual, single-target recovery. Never runs at login; CLI defaults to no display writes.

Identification is per run and device-agnostic: no product names, vendor:product IDs,
serials, EDID digests or fixed row counts are compiled in. The target is the online
external display that currently occupies TWO Pipes while another external port reports no
Pipe, and the internal display is online (or the operator explicitly accepts no internal
fallback). The temporary candidate is generated from that display's own freshly read EDID
through the unchanged fail-closed audit, and the run records its own original/candidate
digests in its own manifest; every later step verifies against that manifest instead of a
global constant.

The countdown is the primary safety net: after the verified mode1 apply the runner polls
for bounded stable evidence, and if that evidence never arrives it automatically attempts
a verified mode0 revert of the same run (same exact serviceID + full registry path, the
run's own original bytes, immediate and independent byte readback). The automatic revert
is attempted only while it can still be verified; if the target identity changed, the
service disappeared, or the readback is uncertain, the run keeps a pending record and
requires manual handling instead of writing blindly.
"""
import argparse, contextlib, fcntl, hashlib, json, os, pathlib, re, subprocess, sys, time, uuid
import displaypipe as dp

CAP_HZ = 120                    # Conservative candidate cap policy, not a device identity.
COUNTDOWN_SECONDS = 20          # Bounded wait before the automatic verified revert.
STABLE_SAMPLES = 3
PORT_IN_PATH = re.compile(r'dispext(\d+)')
PORT_ROLE = re.compile(r'^DCPEXT(\d+)$')
INTERNAL_PORT = re.compile(r'(?i)edp|internal|panel')
# A verified apply/revert cycle proves the device combination on this machine. This only
# labels an order as already verified here; it never gates a write, because both cable
# orders are treated symmetrically.
VERIFIED_STAGES = ('revert-verified', 'recovery-verified', 'physical-accepted')

NO_FALLBACK_NOTICE = ('内屏未在线，且未取得“无内屏回退”许可。写入后目标外屏将是唯一点亮的屏幕：它会短暂重新初始化/黑屏，'
 '期间看不到进度和“撤销本次覆盖”。倒计时到点会自动尝试撤销临时覆盖；但如果该显示器从注册表中消失、身份或路径变化、'
 '回读不确定，自动撤销会被拒绝并保留未结束事务，需要打开机盖人工处理。确认接受请在“详细信息”中勾选'
 '“允许无内屏回退写入”（不保存），或显式传 --ack-no-internal-fallback。')


def state_root():
    return pathlib.Path(os.environ.get('DISPLAYPIPE_STATE', str(pathlib.Path.home() / 'Library/Application Support/DisplayPipe')))


def identity(b):
    return (int.from_bytes(b[8:10], 'big'), int.from_bytes(b[10:12], 'little'), int.from_bytes(b[12:16], 'little'))


def monitor_name(b):
    """EDID base descriptor 0xFC (monitor name). Empty string when absent/undecodable."""
    if not isinstance(b, (bytes, bytearray)) or len(b) < 126:
        return ''
    for offset in range(54, 126, 18):
        d = b[offset:offset + 18]
        if d[0] or d[1] or d[3] != 0xfc:
            continue
        text = bytes(c for c in d[5:18] if 32 <= c < 127).decode('ascii', 'replace')
        return ' '.join(text.replace('\n', ' ').split())[:13]
    return ''


def port_label(path, role, address):
    """Read-only connector token derived from the snapshot: a port, never a product."""
    match = PORT_IN_PATH.search(path or '')
    if match:
        return 'DCPEXT' + match.group(1)
    if role and PORT_ROLE.match(role):
        return role
    return 'ADDR:' + (address or 'unknown')


def _rows(snap):
    rows = []
    for manager in snap.get('crossbar') or []:
        for row in manager.get('ConnectionMapping') or []:
            rows.append(dict(row))
    return rows


def audit_supported(b):
    """True when the display's own capability set is fully understood by the parser."""
    try:
        result = dp.audit(b)
        if result['unsupported']:
            return False, '未识别能力：' + ', '.join(result['unsupported'])
        return True, ''
    except ValueError as e:
        return False, str(e)


def analyze(snap):
    """Classify one read-only snapshot. Nothing here writes to a display.

    kind is 'ready' (one online external hogs two Pipes, another external port has no
    Pipe, internal online or explicitly waived), 'already-healthy' (no hog: no-op) or
    'unsupported' (ambiguous/insufficient evidence: refuse).
    """
    online = list(snap.get('online') or [])
    externals = [d for d in online if not d.get('builtin')]
    internals = [d for d in online if d.get('builtin')]
    problems = []

    def problem(text):
        if text not in problems:
            problems.append(text)

    slots = []
    for row in _rows(snap):
        role = (row.get('role') or '').strip()
        slots.append(dict(source='port', port=port_label(None, role, row.get('Address')), address=row.get('Address'),
                          role=role, name=(row.get('ProductName') or '').strip(),
                          pipeIDs=[int(p) for p in (row.get('PipeIDs') or [])], maxPipes=row.get('MaxPipes'),
                          service=None, edid=None, identity=None, edidError=None, cg=None))
    used = set()
    for service in (snap.get('services') or []):
        if service.get('location') != 'External':
            problem('外接服务位置不是 External：拒绝。')
            continue
        if not service.get('serviceID') or not service.get('path'):
            problem('外接服务缺少精确注册表身份：拒绝。')
            continue
        try:
            b = dp.service_edid(service); ident = identity(b); error = None
        except dp.EDIDUnavailable as e:
            b = None; ident = None; error = e.details.get('reason', 'unavailable')
            edid_fault = e
        else:
            edid_fault = None
        name = monitor_name(b) if b else ''
        port = port_label(service.get('path'), None, None)
        matches = [i for i, slot in enumerate(slots) if i not in used and slot['source'] == 'port'
                   and ((port != 'ADDR:unknown' and slot['port'] == port) or (name and slot['name'] == name))]
        exact = [i for i in matches if port != 'ADDR:unknown' and slots[i]['port'] == port]
        chosen = exact or matches
        if len(chosen) > 1:
            problem('外接服务与端口对应不唯一：拒绝。')
        if chosen:
            slot = slots[chosen[0]]; used.add(chosen[0])
            if slot['service'] is not None:
                problem('同一端口出现多个外接服务：拒绝。')
            slot.update(service=service, edid=b, identity=ident, edidError=error, edidUnavailable=edid_fault,
                        name=slot['name'] or name)
        else:
            slots.append(dict(source='service', port=port, address=None, role='', name=name, pipeIDs=[],
                              maxPipes=None, service=service, edid=b, identity=ident, edidError=error,
                              edidUnavailable=edid_fault, cg=None))

    seen = {}
    for slot in slots:
        if slot['identity'] is None:
            continue
        if slot['identity'] in seen:
            problem('多个端口报告相同外屏身份：拒绝。')
        seen[slot['identity']] = slot
    for slot in slots:
        matches = [d for d in externals if slot['identity'] is not None
                   and slot['identity'] == (d.get('vendor'), d.get('product'), d.get('serial'))]
        if len(matches) > 1:
            problem('同一身份在 CoreGraphics 在线列表中重复：拒绝。')
        if len(matches) == 1:
            slot['cg'] = matches[0]
    for display in externals:
        if not any(slot.get('cg') is display for slot in slots):
            problem('CoreGraphics 在线外屏与任何外接端口/EDID 服务无法对应：拒绝写入。')

    hogs = [s for s in slots if len(s['pipeIDs']) > 1 and not INTERNAL_PORT.search(s['role'] or '')]
    if any(len(s['pipeIDs']) > 2 for s in slots):
        problem('存在占用两个以上 Pipe 的端口：拒绝。')
    target, peers = None, []
    if len(hogs) == 1:
        target = hogs[0]
        if any(s['pipeIDs'] and s is not target for s in slots):
            problem('除目标以外还有端口占用 Pipe：分配歧义，拒绝。')
        if target.get('cg') is None:
            problem('占用双 Pipe 的端口当前没有对应的 CoreGraphics 在线外屏：拒绝写入。')
        if target.get('service') is None:
            problem('占用双 Pipe 的端口没有可精确对应的外接 EDID 服务：拒绝写入。')
        elif target.get('edid') is None:
            problem('占用双 Pipe 的目标 EDID 当前不可读（%s）：拒绝写入。' % (target.get('edidError') or 'unavailable'))
        peers = [s for s in slots if s is not target and not s['pipeIDs'] and s['port'] != target['port']
                 and not INTERNAL_PORT.search(s['role'] or '')]
        for peer in peers:
            if peer.get('service') is not None and peer.get('edid') is not None:
                ok, why = audit_supported(peer['edid'])
                peer['peerClass'] = 'audited-class' if ok else 'unsupported-class'
                if peer['identity'] == target['identity']:
                    problem('对端端口与目标身份相同：拒绝写入。')
                if not ok:
                    problem('对端外屏不属于当前支持的 EDID 类别（%s）：拒绝写入。' % why)
            elif peer.get('service') is not None:
                peer['peerClass'] = 'unreadable-edid'
            else:
                peer['peerClass'] = 'empty-port'
        if not peers:
            problem('未找到另一台外接显示器缺失/无 Pipe 的证据：拒绝写入。')
    elif len(hogs) > 1:
        problem('多个端口同时占用双 Pipe：无法确定唯一目标，拒绝写入。')

    combination, token = None, ''
    if target is not None and not problems:
        combination = dict(shape='dual-pipe-hog', targetPort=target['port'], targetName=target['name'] or '',
                           peerPorts=sorted(p['port'] for p in peers),
                           peerNames=sorted(p['name'] or '' for p in peers),
                           peerClass=sorted(p.get('peerClass', '') for p in peers))
        token = hashlib.sha256(json.dumps(combination, sort_keys=True).encode()).hexdigest()[:16]

    def view(slot):
        return dict(port=slot['port'], name=slot['name'], role=slot['role'], address=slot['address'],
                    pipeIDs=list(slot['pipeIDs']), maxPipes=slot['maxPipes'], online=slot.get('cg') is not None,
                    edidReadable=slot.get('edid') is not None, edidError=slot.get('edidError'),
                    edidUnavailable=(slot['edidUnavailable'].as_dict() if slot.get('edidUnavailable') is not None else None),
                    peerClass=slot.get('peerClass'),
                    serviceID=(slot.get('service') or {}).get('serviceID'))

    description = ''
    if target is not None:
        description = ('目标：%s（端口 %s，双 Pipe）；缺失/无 Pipe 的对端端口：%s'
                       % (target['name'] or monitor_name(target.get('edid') or b'') or '未命名显示器',
                          target['port'], ', '.join(sorted(p['port'] for p in peers)) or '无'))
    # 'refused' is a recognized target that a gate rejected; 'unsupported' means the shape
    # itself is not a recovery target. They must stay distinguishable in the UI and records.
    if problems:
        kind = 'refused' if target is not None else 'unsupported'
    else:
        kind = 'ready' if target is not None else 'already-healthy'
    summary = ('外接端口 %d 个 · CoreGraphics 在线外屏 %d 台 · 内屏%s'
               % (len([s for s in slots if not INTERNAL_PORT.search(s['role'] or '')]), len(externals),
                  '在线' if internals else '未在线'))
    if target is not None:
        summary += ' · ' + description
    if problems:
        summary += ' · ' + '；'.join(problems)
    return dict(kind=kind, problems=problems, refusals=list(problems), reason='；'.join(problems), summary=summary,
                slots=[view(s) for s in slots], target=view(target) if target else None,
                peers=[view(p) for p in peers], combination=combination, combinationToken=token,
                combinationDescription=description, internalOnline=bool(internals),
                internalDisplay=(internals[0] if internals else None), externalOnlineCount=len(externals),
                externalSlotCount=len([s for s in slots if not INTERNAL_PORT.search(s['role'] or '')]),
                hogDetected=bool(hogs), _slots=slots, _targetSlot=target, _peers=peers)


class AlreadyHealthy(Exception):
    pass


def public_view(view):
    """The persisted, reviewable part of an analysis: no private runtime handles."""
    return {k: v for k, v in view.items() if not k.startswith('_')}


class Engine(object):
    def __init__(self, root=None, inventory=None, setter=None, sleep=time.sleep, clock=time.monotonic, cap_hz=CAP_HZ):
        self.root = pathlib.Path(root or state_root()); self.inventory = inventory or dp.inventory
        self.setter = setter; self.sleep = sleep; self.clock = clock; self.setter_attempted = False
        self.cap_hz = int(cap_hz)

    def pending(self):
        result = []
        for run in sorted((self.root / 'runs').glob('*')):
            events = sorted(run.glob('event-*.json'))
            if events:
                event = json.loads(events[-1].read_text())
                if event.get('pending'):
                    result.append(dict(event, runDirectory=str(run)))
        return result

    def event(self, run, state, pending, **fields):
        value = dict(state=state, pending=pending, runDirectory=str(run), physicalInputConfirmed=False, recoveryValidated=False)
        value.update(fields)
        dp.exclusive(pathlib.Path(run) / ('event-%020d-%s.json' % (time.time_ns(), uuid.uuid4().hex)),
                     json.dumps(value, sort_keys=True).encode())
        print(json.dumps(dict(progress=state, **fields), sort_keys=True), file=sys.stderr, flush=True)
        return value

    @contextlib.contextmanager
    def locked(self):
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        with open(self.root / 'operation.lock', 'a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('已有操作进行中；拒绝并发。')
            yield

    # ---- append-only local record of the device combinations this machine verified ----
    def patterns(self):
        path = self.root / 'patterns.jsonl'; out = {}
        if path.exists():
            for line in path.read_text().splitlines():
                try:
                    item = json.loads(line)
                except ValueError:
                    continue
                if item.get('token'):
                    out[item['token']] = item
        return out

    def pattern_stage(self, token):
        return (self.patterns().get(token) or {}).get('stage')

    def verified(self, token):
        """True when this machine already completed a verified cycle for that order."""
        return bool(token) and self.pattern_stage(token) in VERIFIED_STAGES

    def record(self, token, stage, run, combination=None):
        if not token:
            return None
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        entry = dict(token=token, stage=stage, runDirectory=str(run), at=time.time(), combination=combination or {})
        with open(self.root / 'patterns.jsonl', 'a') as handle:
            handle.write(json.dumps(entry, sort_keys=True) + '\n')
        return entry

    def inspect(self, snap=None):
        """Analysis of one snapshot plus this machine's local verification label."""
        view = analyze(snap if snap is not None else self.inventory())
        view['orderVerified'] = self.verified(view['combinationToken'])
        view['orderLabel'] = ('已在本机验证过的接入顺序' if view['orderVerified']
                              else '本机尚未验证的接入顺序（实验性；写入依赖倒计时自动撤销）')
        view['requiresNoInternalFallback'] = view['kind'] == 'ready' and not view['internalOnline']
        view['patternStage'] = self.pattern_stage(view['combinationToken'])
        view['countdownSeconds'] = COUNTDOWN_SECONDS
        return view

    # ---- per-run manifest: the run's own digests, never a global constant ----
    def manifest(self, run):
        path = pathlib.Path(run) / 'manifest.json'
        return json.loads(path.read_text()) if path.exists() else None

    def _manifest(self, run, view, target, original, proposed, candidate_bytes, no_internal_fallback):
        service = target['service']
        return dict(schema=1, createdAt=time.time(), capHz=self.cap_hz, countdownSeconds=COUNTDOWN_SECONDS,
                    stabilitySamples=STABLE_SAMPLES, combination=view['combination'],
                    combinationToken=view['combinationToken'], targetName=target['name'] or monitor_name(original),
                    targetPort=target['port'], identity=list(identity(original)),
                    serviceID=service['serviceID'], path=service['path'], location=service['location'],
                    originalSHA256=dp.sha(original), candidateSHA256=proposed['sha256'],
                    originalLength=len(original), candidateLength=len(candidate_bytes),
                    internalOnlineAtPlan=bool(view['internalOnline']),
                    noInternalFallback=bool(no_internal_fallback),
                    orderVerified=bool(view['orderVerified']), orderLabel=view['orderLabel'],
                    auditUnsupported=list(dp.audit(original)['unsupported']),
                    peerClass=sorted(p.get('peerClass', '') for p in view['_peers']), autoRevertOnTimeout=True)

    def checked(self, snap, run, expected):
        """Fail-closed re-verification against this run's manifest, not a global digest."""
        manifest = self.manifest(run)
        if not manifest:
            raise ValueError('缺少本次运行的 manifest；拒绝写入。')
        if not any(d.get('builtin') for d in (snap.get('online') or [])) and not manifest.get('noInternalFallback'):
            raise ValueError('写入与回读期间内屏必须在线；本次未取得“无内屏回退”许可。')
        backup = dp.load_backup(pathlib.Path(run) / 'original.bin')
        if dp.sha(backup['bytes']) != manifest['originalSHA256']:
            raise ValueError('原件与本次 manifest 的 SHA256 不一致；拒绝写入。')
        if list(identity(backup['bytes'])) != list(manifest['identity']):
            raise ValueError('原件身份与本次 manifest 不一致；拒绝写入。')
        if backup['serviceID'] != manifest['serviceID'] or backup['path'] != manifest['path']:
            raise ValueError('本次 manifest 的精确注册表身份与备份不一致；拒绝写入。')
        proposed = (pathlib.Path(run) / 'candidate.bin').read_bytes()
        if dp.sha(proposed) != manifest['candidateSHA256'] or dp.candidate(backup['bytes'], manifest['capHz'])['bytes'] != proposed:
            raise ValueError('候选完整性失败：与本次 manifest 或独立重算不一致。')
        if any(len(s['pipeIDs']) > 2 for s in analyze(snap)['_slots']):
            raise ValueError('存在占用两个以上 Pipe 的端口；停止。')
        service = dp.select(snap.get('services') or [], manifest['serviceID'], manifest['path'])
        live = dp.service_edid(service)
        if live != expected or list(identity(live)) != list(manifest['identity']):
            raise ValueError('同一目标 EDID 回读不一致；停止，不盲目写入。')
        return backup

    def write(self, mode, run):
        if self.setter:
            return self.setter(mode, run)
        model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], timeout=3).decode().strip()
        if model != 'Mac14,10':
            raise ValueError('仅允许已验证 Mac14,10；其它Mac型号尚未验收。')
        backup = dp.load_backup(pathlib.Path(run) / 'original.bin')
        args = [str(dp.BASE / 'build/DisplayPipeIO'), 'temporary-write', backup['serviceID'], backup['path'],
                str(pathlib.Path(run) / ('original.bin' if mode else 'candidate.bin')), str(mode),
                str(pathlib.Path(run) / 'candidate.bin'), 'I_ACCEPT_UNVALIDATED_PRIVATE_API']
        return json.loads(subprocess.check_output(args, timeout=12))

    def verified_write(self, mode, run, require_stable=False):
        backup = dp.load_backup(pathlib.Path(run) / 'original.bin')
        proposed = (pathlib.Path(run) / 'candidate.bin').read_bytes()
        current = self.inventory()
        if mode and analyze(current)['kind'] == 'already-healthy':
            raise AlreadyHealthy()
        self.checked(current, run, backup['bytes'] if mode else proposed)
        if require_stable and not self.stable(current):
            raise ValueError('撤销前双屏稳定证据已变化；等待倒计时结束后的自动撤销。')
        self.event(run, 'applying' if mode else 'resetting', True)
        self.setter_attempted = True
        result = self.write(mode, run)
        if not isinstance(result, dict):
            raise ValueError('原生 setter 未返回映射结果（%s）；结果不可解释，拒绝继续。' % type(result).__name__)
        dp.exclusive(pathlib.Path(run) / ('native-%s-%s.json' % (mode, uuid.uuid4().hex)), json.dumps(result, sort_keys=True).encode())
        expected = proposed if mode else backup['bytes']
        if result.get('setterStatus') != 0 or result.get('copyStatus') != 0 or result.get('effectiveEDID') != expected.hex():
            raise ValueError('私有接口结果或即时字节回读不确定。')
        snap = self.inventory()
        self.checked(snap, run, expected)
        dp.exclusive(pathlib.Path(run) / ('verified-%s-%s.json' % (mode, uuid.uuid4().hex)), json.dumps(snap, sort_keys=True).encode())
        return snap

    def stable(self, snap):
        """Bounded dual-screen evidence: two externals, one distinct Pipe each, at cap Hz."""
        view = analyze(snap)
        externals = [d for d in (snap.get('online') or []) if not d.get('builtin')]
        if view['kind'] != 'already-healthy' or view['problems']:
            return False
        piped = [tuple(s['pipeIDs']) for s in view['_slots'] if s['pipeIDs']]
        if len(piped) < 2 or any(len(p) != 1 for p in piped) or len(set(piped)) != len(piped):
            return False
        return len(externals) >= 2 and all(abs((d.get('refreshHz') or 0) - self.cap_hz) < 1 for d in externals)

    def latest(self):
        files = list((self.root / 'runs').glob('*/event-*.json'))
        return json.loads(max(files, key=lambda p: p.name).read_text()) if files else None

    def status(self):
        pending = self.pending(); last = self.latest()
        if pending:
            return dict(state='recovery-needed', pending=pending, lastTransaction=last,
                        physicalInputConfirmed=False, setterCalled=False)
        try:
            snap = self.inventory(); view = self.inspect(snap)
        except Exception as e:
            return dict(state='unsupported', error=str(e), snapshot=None, pending=[], lastTransaction=last,
                        physicalInputConfirmed=False, setterCalled=False)
        # Only the public part is returned: the analysis keeps runtime handles (bytes, service
        # records) that must never reach json.dumps or the client.
        return dict(state=view['kind'], error=view['reason'], summary=view['summary'], snapshot=snap, pending=[],
                    lastTransaction=last, physicalInputConfirmed=False, setterCalled=False,
                    analysis=public_view(view))

    def accept(self, confirmed=False):
        if not confirmed:
            raise ValueError('必须由用户明确确认两个屏幕实际点亮及 OSD 输入。')
        with self.locked():
            last = self.latest()
            if self.pending() or not last or last['state'] != 'cg-restored-reset-verified':
                raise ValueError('只有已完成原件撤销的系统双屏恢复事务可以记录实体确认。')
            run = pathlib.Path(last['runDirectory'])
            self.record(last.get('combinationToken', ''), 'physical-accepted', run, (self.manifest(run) or {}).get('combination'))
            return self.event(run, 'physical-accepted', False, physicalInputConfirmed=True,
                              acceptanceSource='explicit-user-action', setterCalled=False)

    def undo(self, confirmed=False):
        if not confirmed:
            raise ValueError('手动撤销必须明确确认。')
        with self.locked():
            pending = self.pending()
            if len(pending) != 1:
                raise ValueError('必须恰好存在一个本程序拥有的未结束事务。')
            run = pathlib.Path(pending[0]['runDirectory'])
            try:
                backup = dp.load_backup(run / 'original.bin'); snap = self.inventory()
                service = dp.select(snap.get('services') or [], backup['serviceID'], backup['path'])
                if dp.service_edid(service) == backup['bytes']:
                    self.checked(snap, run, backup['bytes'])
                    return self.event(run, 'undo-verified', False, setterCalled=False, alreadyOriginal=True)
                self.checked(snap, run, (run / 'candidate.bin').read_bytes())
                self.verified_write(0, run)
                return self.event(run, 'undo-verified', False, setterCalled=True)
            except Exception as e:
                return self.event(run, 'recovery-needed', True, error=str(e))

    def run(self, execute=False, confirmed=False, no_internal_fallback=False):
        with self.locked():
            return self._run(execute, confirmed, no_internal_fallback)

    def _run(self, execute, confirmed, no_internal_fallback=False):
        self.setter_attempted = False
        if execute and not confirmed:
            raise ValueError('必须明确确认临时 EDID 私有接口风险。')
        pending = self.pending()
        if pending:
            return dict(state='recovery-needed', pending=pending, setterCalled=False, physicalInputConfirmed=False)
        snap = self.inventory(); view = self.inspect(snap)
        if view['kind'] == 'already-healthy':
            return dict(state='already-healthy', setterCalled=False, physicalInputConfirmed=False,
                        summary=view['summary'], analysis=public_view(view))
        if view['kind'] != 'ready':
            # A missing/unreadable target EDID keeps the structured preflight contract.
            if (view['_targetSlot'] or {}).get('edidUnavailable') is not None:
                raise view['_targetSlot']['edidUnavailable']
            raise ValueError(view['reason'] or '当前连接状态不在可恢复的故障范围内；拒绝写入。')
        if execute and not view['internalOnline'] and not no_internal_fallback:
            raise ValueError(NO_FALLBACK_NOTICE)
        target = view['_targetSlot']; service = target['service']
        original = dp.service_edid(service)
        ok, why = audit_supported(original)
        if not ok:
            raise ValueError('目标 EDID 未通过 fail-closed 审核（%s）；拒绝写入。' % why)
        proposed = dp.candidate(original, self.cap_hz)
        run = self.root / 'runs' / uuid.uuid4().hex
        run.mkdir(parents=True, mode=0o700)
        dp.backup(run / 'original.bin', original, {k: service[k] for k in ('serviceID', 'path', 'location')})
        candidate_bytes = proposed.pop('bytes')
        dp.exclusive(run / 'candidate.bin', candidate_bytes)
        dp.exclusive(run / 'candidate.bin.json', json.dumps(proposed, sort_keys=True).encode())
        manifest = self._manifest(run, view, target, original, proposed, candidate_bytes,
                                  no_internal_fallback)
        dp.exclusive(run / 'manifest.json', json.dumps(manifest, sort_keys=True).encode())
        dp.exclusive(run / 'before.json', json.dumps(dict(snapshot=snap, analysis=public_view(view)), sort_keys=True).encode())
        if not execute:
            return self.event(run, 'dry-run', False, setterCalled=False, combinationToken=view['combinationToken'],
                              combinationDescription=view['combinationDescription'],
                              orderVerified=bool(view['orderVerified']), orderLabel=view['orderLabel'],
                              noInternalFallback=bool(no_internal_fallback), internalOnline=bool(view['internalOnline']),
                              countdownSeconds=COUNTDOWN_SECONDS, targetName=target['name'], targetPort=target['port'])
        try:
            self.verified_write(1, run)
            deadline = self.clock() + COUNTDOWN_SECONDS; consecutive = 0
            while self.clock() <= deadline:
                observed = self.inventory()
                self.checked(observed, run, (run / 'candidate.bin').read_bytes())
                dp.exclusive(run / ('poll-%s.json' % uuid.uuid4().hex), json.dumps(observed, sort_keys=True).encode())
                consecutive = consecutive + 1 if self.stable(observed) else 0
                self.event(run, 'polling', True, stableSamples=consecutive,
                           remainingSeconds=max(0, round(deadline - self.clock())),
                           countdownSeconds=COUNTDOWN_SECONDS, autoRevertOnTimeout=True)
                if consecutive >= STABLE_SAMPLES:
                    try:
                        final = self.verified_write(0, run, require_stable=True)
                    except ValueError as e:
                        if '稳定证据' not in str(e):
                            raise
                        consecutive = 0
                    else:
                        self.record(view['combinationToken'], 'recovery-verified', run, view['combination'])
                        restored = self.stable(final)
                        return self.event(run, 'cg-restored-reset-verified' if restored else 'reset-verified-cg-not-restored',
                                          False, bothOnline=restored, setterCalled=True, autoReverted=False)
                if self.clock() >= deadline:
                    break
                self.sleep(1)
            # Countdown expired without confirmed stable evidence: verified automatic revert.
            self.event(run, 'auto-reverting', True, remainingSeconds=0, countdownSeconds=COUNTDOWN_SECONDS)
            try:
                final = self.verified_write(0, run)
            except Exception as e:
                return self.event(run, 'recovery-needed', True, autoReverted=False, setterCalled=True,
                                  error='倒计时到点后无法核验地自动撤销：%s。未结束事务保留，请打开机盖后人工处理。' % str(e))
            self.record(view['combinationToken'], 'revert-verified', run, view['combination'])
            restored = self.stable(final)
            return self.event(run, 'auto-reverted-verified' if restored else 'auto-reverted-cg-not-restored', False,
                              bothOnline=restored, autoReverted=True, setterCalled=True,
                              error='' if restored else '临时覆盖已自动撤销并核验原件，但未取得连续双外屏稳定证据。')
        except AlreadyHealthy:
            return self.event(run, 'already-healthy', False, setterCalled=False)
        except Exception as e:
            return self.event(run, 'recovery-needed' if self.setter_attempted else 'unsupported',
                              self.setter_attempted, error=str(e), setterCalled=self.setter_attempted)


def main():
    if sys.version_info < (3, 9):
        raise ValueError('需要现有 Python3.9+；本App不会安装运行时。')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['status', 'recover', 'undo', 'accept'], nargs='?', default='status')
    parser.add_argument('--execute', action='store_true', help='Explicit temporary display-write permission; recover otherwise dry-runs.')
    parser.add_argument('--confirm-private-api-risk', action='store_true')
    parser.add_argument('--confirm-physical', action='store_true')
    parser.add_argument('--ack-no-internal-fallback', action='store_true', help='Explicitly accept writing with the internal display offline; the countdown still auto-reverts.')
    args = parser.parse_args(); engine = Engine()
    if args.command == 'status':
        return engine.status()
    if args.command == 'recover':
        return engine.run(args.execute, args.confirm_private_api_risk, args.ack_no_internal_fallback)
    if args.command == 'undo':
        if not args.execute:
            return dict(state='dry-run', pending=engine.pending(), setterCalled=False)
        return engine.undo(args.confirm_private_api_risk)
    return engine.accept(args.confirm_physical)


if __name__ == '__main__':
    try:
        result = main(); print(json.dumps(result, sort_keys=True), flush=True)
        if result['state'] in ('unsupported', 'refused', 'recovery-needed', 'reset-verified-cg-not-restored',
                               'auto-reverted-cg-not-restored'):
            sys.exit(3)
    except dp.EDIDUnavailable as e:
        print(json.dumps(dict(e.as_dict(), state='unsupported')), flush=True); sys.exit(2)
    except Exception as e:
        # Write-phase failures are converted into events inside the engine, so every uncaught
        # exception here is a pre-write refusal that provably never called the setter.
        print(json.dumps(dict(state='failure', error=str(e), setterCalled=False,
                              physicalInputConfirmed=False, recoveryValidated=False)), flush=True); sys.exit(2)
