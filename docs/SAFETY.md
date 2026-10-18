# Safety and acceptance / 安全与验收

DisplayPipe is a narrowly scoped, hardware-specific manual-use workaround for one dual-external-display initialization fault, using private macOS IOAV interfaces. Read the [README](../README.md) and [user guide](USER_GUIDE.md) before use. Do not invoke an upstream watch/agent or direct helper to bypass the guarded workflow.

## Stop conditions

Refuse writes when no identity-free target and peer can be selected, identity is missing/duplicated, the service ID or full registry path changes, EDID is unavailable, the run's own original/candidate digest or its independent recomputation does not match, an unsupported capability is found, or the internal fallback display is offline without the explicit no-fallback opt-in. Never retarget an old backup by name.

Neither cable order is privileged: the target is whichever online external currently holds TWO Pipes while another external port or service has no link/Pipe. The order is only a *label* derived from this machine's own completed run records (`接入顺序（本机已验证）` once that combination has a verified recovery + reset, otherwise the neutral `首次使用该组合`): it never blocks a write and never weakens a gate, and it does not depend on the optional physical-acceptance click. A refusal names the exact failing field instead of pretending support, and a shape that is not a recovery target is reported as unsupported rather than as a fault.

A persisted pending transaction is not proof that an override is active or removed. Keep uncertainty visible. Undo must verify the owned original/candidate and exact current service, not blindly write after a timeout. If identity changes, retain reports for investigation.

## The countdown is the safety net

After the verified mode1 apply, the runner polls for bounded stable evidence and, if that evidence never arrives, it **automatically attempts a verified mode0 revert of the same run** (same exact serviceID + full registry path, the run's own original bytes, immediate and independent byte readback). No user click is required, which is what makes writing while the internal display is offline or out of sight survivable. If the target identity changed, the service disappeared, or the readback is uncertain, the automatic revert is refused and a pending record is kept for manual handling: never revert to a state you cannot verify. A display that disappears from the registry entirely can therefore still need manual handling.

## Evidence layers

Setter success, immediate EDID readback, independent readback, Pipe allocation, CoreGraphics online state, physical image confirmation, and actual input timing are separate acceptance gates. `MaxPipes` is capacity, `PipeIDs` is assignment. HiDPI rendering dimensions are not wire resolution.

## Candidate audit precision

The candidate rewrites one byte (the maximum vertical rate) of a Display Range Limits descriptor, so the audit only refuses when that byte's meaning is affected. Byte 4 vertical offset bits and reserved bits still fail closed and are named in the error; horizontal-only offset bits are recorded in the audit and manifest and no longer block a vertical-rate cap. A retained timing may sit above the cap only inside its own descriptor quantization (derived from that timing's totals, well under 0.1 Hz here), never inside the upstream +0.5 Hz mode tolerance: a real 144/160 Hz mode is still refused. Unknown vendors, VICs, extensions and DisplayID blocks still fail closed.

Both connection orders have each completed one verified recovery and reset on the reference setup, with the user confirming the physical result. That single run per order does not establish repeated-reconnect reliability, sleep/wake or closed-lid acceptance, or support for other monitor models; the private interfaces may still change between releases.

## Scope and rollback

No monitor EEPROM/firmware writes, SIP changes, reboot, startup service or background forced override is part of the intended workflow. Manual recovery temporarily applies a candidate, observes bounded stability, then attempts a verified reset — automatically on timeout, or immediately once stability is confirmed. Failure can leave a pending transaction requiring explicit undo.

Deleting or replacing the app does not undo a temporary override. Preserve runtime state until it has been reviewed and resolved. Source/build tests do not authorize arbitrary live writes. Preserve backups; never globally clean shared Cargo caches or unrelated state.

## 中文摘要

本工具使用私有接口、身份全部运行时发现，两个接入方向对称处理，不因方向硬拒绝；方向只作为“本机运行记录”得出的标签（“接入顺序（本机已验证）”／“首次使用该组合”），绝不削弱任何门槛，也不依赖可选的实体确认点击。倒计时是主要安全网：应用候选后取不到稳定证据就自动执行可核验的 mode0 撤销；一旦目标身份变化、服务消失或回读不确定，自动撤销会被拒绝并保留未结束事务（彻底消失的显示器仍可能需人工处理）。范围描述符只有垂直偏移位／保留位才失败关闭，水平偏移位记录在审计与清单中、不再阻止垂直上限；保留时序只允许落在其自身描述符量化误差内，绝不套用上游 +0.5Hz 容差。恢复、字节回读、Pipe、系统在线、实体亮屏和输入时序分别验收。异常时保留 pending 和报告，不盲目写入。删除 App 不等于撤销覆盖，不安装后台 Agent、不刷固件、不改 SIP、不重启。
