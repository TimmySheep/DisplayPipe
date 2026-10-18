# Safety and acceptance / 安全与验收

DisplayPipe is an experimental manual-use workaround using private macOS IOAV interfaces. Read the [README](../README.md) and [user guide](USER_GUIDE.md) before use. Do not invoke an upstream watch/agent or direct helper to bypass the guarded workflow.

## Stop conditions

Refuse writes when the allowlisted hardware/fault is not matched, identity is missing/duplicated, the service ID or full registry path changes, EDID is unavailable, the original fingerprint/candidate does not match, an unsupported capability is found, or the internal fallback display is offline. Never retarget an old backup by name.

A persisted pending transaction is not proof that an override is active or removed. Keep uncertainty visible. Undo must verify the owned original/candidate and exact current service, not blindly write after a timeout. If identity changes, retain reports for investigation.

## Evidence layers

Setter success, immediate EDID readback, independent readback, Pipe allocation, CoreGraphics online state, physical image confirmation, and actual input timing are separate acceptance gates. `MaxPipes` is capacity, `PipeIDs` is assignment. HiDPI rendering dimensions are not wire resolution.

One controlled command-line recovery and reset succeeded on the reference setup. This does not establish real-fault packaged-GUI acceptance, repeated reconnect reliability, sleep/wake, closed-lid recovery, reverse connection order, or other monitor support.

## Scope and rollback

No monitor EEPROM/firmware writes, SIP changes, reboot, startup service or background forced override is part of the intended workflow. Manual recovery temporarily applies a candidate, observes bounded stability, then attempts a verified reset only after rechecking identity and evidence. Failure can leave a pending transaction requiring explicit undo.

Deleting or replacing the app does not undo a temporary override. Preserve runtime state until it has been reviewed and resolved. Source/build tests do not authorize arbitrary live writes. Preserve backups; never globally clean shared Cargo caches or unrelated state.

## 中文摘要

本工具使用私有接口且严格限制硬件。目标／服务身份、EDID、候选、内屏回退任一不满足即停止，不能按名称复用旧备份。恢复、字节回读、Pipe、系统在线、实体亮屏和输入时序分别验收。一次命令行成功不等于打包 GUI、反向顺序、闭盖或反复重连已经通过。异常时保留 pending 和报告，不盲目写入。删除 App 不等于撤销覆盖，不安装后台 Agent、不刷固件、不改 SIP、不重启。
