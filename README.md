# DisplayPipe

A small native macOS utility investigating—and narrowly working around—dual-external-display initialization failures on Apple Silicon.

**English first · [中文说明](#中文说明)**

> **Experimental, hardware-specific recovery tool.** A controlled command-line experiment restored both physical displays and verified removal of the temporary override. The packaged GUI has not yet passed a real-fault end-to-end recovery test. This is not a universal monitor fix or an Apple-supported API.

## 1. The problem

On the tested 16-inch M2 Pro MacBook Pro, connecting two independent high-refresh-rate monitors can leave the second monitor reporting **No Signal**, even though the same hardware can drive both after a manual capability-changing workaround.

Test setup:

| Component | Tested configuration |
| --- | --- |
| Mac | MacBook Pro, M2 Pro, hardware identifier `Mac14,10` |
| macOS during the experiment | 27.0.1, build `26A434` |
| Display A | HUAWEI QSN-CAB, USB-C → DisplayPort, DP 1.4 |
| Display B | P275MV PLUS, Mac's built-in HDMI → HDMI |
| Safety fallback | Built-in display online, lid open during recovery |

The two cables are independent: this experiment does not involve an MST hub or a shared dock video link. The failure has been observed in either connection order. Rapidly connecting both cables sometimes helped; deliberately waiting for the first monitor to initialize made the failure reproducible.

A known manual workaround is to change the Huawei monitor to DP 1.2, wait for both displays, and return to DP 1.4. That is inconvenient when repeatedly docking a laptop.

## 2. Working hypothesis and evidence

The central distinction is **current output mode versus advertised maximum capability**.

- EDID describes what a display claims to support. Selecting 120 Hz in macOS does not remove 144/160 Hz modes from that capability description.
- In a captured fault, the first display's Crossbar mapping had `PipeIDs: [1, 0]`, while the other display could not establish an output.
- Lowering the current refresh rate to 60 Hz or changing scaling did **not** release that allocation in the observed fault.
- A carefully limited temporary EDID changed the first display to a single Pipe; the second display then obtained the other Pipe.

`PipeIDs` records allocation. `MaxPipes` is a capability limit, **not** the count currently consumed. A healthy display may still have `MaxPipes: 2` while using only one Pipe.

An [Apple Developer Forums discussion](https://developer.apple.com/forums/thread/814201) describes related maximum-capability-based allocation behavior. Its hardware and refresh thresholds must not be copied to M2 Pro as specifications. Our evidence points toward display-stack allocation/rebalancing behavior; it does **not** isolate a particular Apple driver/DCP component or prove a standards violation in either monitor's EDID.

In particular, this is **not established as a Huawei-only firmware defect**: the successful experiment modified the HDMI-connected P275's temporary capability description, not the Huawei's firmware.

## 3. What we are building—and what we are not

A manual, local **user-space workaround** for a narrowly verified fault:

1. Connect the two displays and open DisplayPipe.
2. Read the compact connection state.
3. Press **Recover Displays** (the current UI is in Chinese: `恢复双屏`) and confirm once.
4. The guarded backend creates a fresh backup, applies a temporary 120 Hz capability limit, waits for stable allocation/online evidence, removes the override, and verifies the original bytes.

This does **not** patch macOS system files or flash monitor firmware. It is not a generic EDID editor, a driver, or a guarantee that every high-refresh display combination is supported. There is no startup agent, background recovery loop, network service, browser shell, or additional Python package dependency.

The UI uses native AppKit: one state, two concise monitor rows, one main action, and optional details. Raw EDID/Pipe diagnostics are hidden by default; the details views are created only when opened and released on collapse. Pending-transaction undo remains prominent when needed.

## 4. What actually worked

One controlled run on **2026-10-18**:

| Stage | Observation |
| --- | --- |
| Before | Internal display online; P275 reported 120 Hz and occupied `[1,0]`; Huawei missing from the online list |
| Prepare | Fresh exact-service EDID backup, checksum/SHA verification, audited/reproducible 120 Hz candidate |
| Temporary apply | Private IOAV mode 1 returned success; immediate and independently enumerated EDID matched the candidate byte-for-byte |
| Convergence | The earliest transaction sample still omitted the peer; the next enumeration showed both external displays online |
| Stable observations | Huawei `[0]`, P275 `[1]`, both reported 120 Hz; approximately 20 seconds of observations remained stable |
| Physical check | The user confirmed both monitors actually displayed an image |
| Remove override | IOAV mode 0; immediate and independent readback matched the original EDID byte-for-byte |
| After removal | Both external displays stayed online, each with one Pipe and a reported 120 Hz; the user subsequently confirmed normal operation |

No DP-version switch, replug, reboot, WindowServer restart, or “Detect Displays” operation was performed by the software during this run. Earlier experiments had ambiguous activation and are **not** counted as equivalent successful controlled recoveries.

**Evidence limits:** CoreGraphics online state is not physical bright-screen confirmation. HiDPI render dimensions are not wire timing. This run did not independently re-accept both OSD input timings as 3840×2160 at 120 Hz. Repeated reconnects, sleep/wake, closed-lid recovery, and reverse-order recovery remain unverified.

## 5. Strict supported scope

The current recovery implementation deliberately fails closed:

- Only the allowlisted P275/QSN-CAB identities and the previously verified P275 EDID fingerprint/candidate are accepted.
- Supported fault: **P275 online and occupying two Pipes; Huawei missing and without an allocated Pipe; internal display online.**
- Huawei-first reverse-order faults are diagnosed but not automatically repaired.
- Unknown or duplicate identities, unsupported EDID capabilities, missing EDID, changed service ID/path, and uncertain readback stop the operation.
- Backups are per-run and never silently overwritten. Reconnecting changes service identities; an old backup must not be retargeted by monitor name.
- An already-online pair is a no-write no-op, including a healthy closed-lid session. This does **not** validate recovery while closed-lid.

Changing a fingerprint or widening an allowlist is not a safe way to add monitor support. New hardware needs a separate audit and controlled apply/reset validation.

## 6. Safety and transaction lifecycle

The native IOAV helper uses **private Apple interfaces**. They can change or fail across macOS releases. It is not sufficient for a setter to return zero: the backend requires immediate and independently enumerated byte readback.

The workflow rechecks the supported fault before applying; then polls for two approximately 120 Hz online displays, each assigned a distinct single Pipe. Before automatic reset, it rechecks stable evidence and exact service identity. Reset must restore the original bytes, and post-reset online state is checked separately.

A pending transaction is persisted before dispatching a write. On a timeout, identity change, or uncertain result, the app retains that record and exposes **Undo This Override** rather than blindly writing to another service. The low-level helper is an internal implementation detail; use the guarded app, not direct helper invocations. Do not run the old experimental CLI concurrently.

Runtime backups and reports live in:

```text
~/Library/Application Support/DisplayPipe/
```

They may contain device identifiers and local paths. Review before sharing. Deleting the app is **not** a way to remove an active override. Build artifacts, old app backups, and scratch archives are retained rather than automatically deleted.

## 7. Build and run

### Requirements

- Apple Silicon macOS and an existing Xcode toolchain: Swift/AppKit, clang, `iconutil`, and ad-hoc `codesign`.
- Existing Rust/Cargo toolchain for building the EDID parser.
- Existing Python **3.9+**, standard library only.

Packaging resolves `/usr/bin/python3` to the actual executable, validates it, and records its absolute path in the app. On the development machine this was Xcode's Python 3.9.6. **Python is not bundled**: copying the app to another Mac does not make it self-contained. A missing configured interpreter produces an explicit error; the app does not install one. A developer-tool shim may prompt for tools on an unprepared machine, so prepare and verify the toolchain yourself before building.

```sh
# From the repository root, intentionally fetch locked dependencies first:
cargo fetch --locked --manifest-path backend/edid-core/Cargo.toml

# Build, test, generate/recompress icon, bundle resources and ad-hoc sign:
./scripts/build-gui.sh

# Open the build artifact:
open .build/DisplayPipe.app
```

The build does not install a startup agent or apply an EDID override. It runs device-dependent read-only packaging checks; some checks expect the already-healthy reference monitor pair and will not pass on unrelated hardware. A build/test failure must not be interpreted as permission to remove safety gates. The output may already exist even if a later hardware-dependent check fails—check the complete output before using it.

Copy `.build/DisplayPipe.app` into your user Applications folder if desired. Preserve a previous installation before replacing it. The app is **ad-hoc signed, not Developer ID signed or notarized**; this is not a promise of Gatekeeper acceptance on other Macs. Do not disable macOS security protections to run it.

## 8. Tests and measured size

```sh
./scripts/test-gui.sh
sh scripts/backend-test.sh
python3 scripts/test-icon.py -v
python3 scripts/test-package.py -v

# Test a specific installed bundle:
DISPLAYPIPE_TEST_APP="$HOME/Applications/DisplayPipe.app" \
  python3 scripts/test-package.py -v
```

Recorded checks for 0.2.1: Rust 14; backend Python 39; Swift parser 11, recovery presentation 9, AppKit hierarchy 15; scoped registry equivalence 2; icon 2; packaging 8. These are local test results, **not hosted CI or proof of real-fault GUI recovery**. Native hierarchy tests are not screenshots or actual button-interaction acceptance.

| Measurement | 0.2 | 0.2.1 |
| --- | ---: | ---: |
| App file payload | 2,264,300 bytes / 27 files | 1,849,109 bytes / 17 files |
| Sequential fresh-launch idle RSS, mean | 163,360 KiB | 90,923 KiB |

The RSS readings used the same `ps rss` method at 15/16/17 seconds after separate launches, with one initial refresh and no interaction. The approximately 44% reduction was observed in that run; it is not a general memory guarantee and excludes transient helper processes. File payload is not allocated filesystem size and excludes preserved builds/backups and runtime state. A scoped IORegistry query reduced the sampled input from about 43 MB to 3,213 bytes while retaining the current Pipe mappings. ICNS recompression preserved all ten representations pixel-for-pixel.

## 9. Source map and provenance

- `GUI/`: native AppKit interface, diagnostic collector, state presentation and tests.
- `backend/recovery.py`: guarded manual transaction orchestration.
- `backend/displaypipe.py`: EDID validation, candidate checks and readback logic.
- `backend/DisplayPipeIO.m`: native IOAV/CoreGraphics helper.
- `backend/edid-core/`: parser adapted from pipecap, with its MIT notice retained.
- `pipecap-review/`: selected upstream source snapshot, **not** the recommended runtime recovery entry point.
- `scripts/`: build, icon generation/recompression and artifact tests.

Upstream: [pipecap](https://github.com/a1678991/pipecap), pinned source `d045192de888188783b4da74b10ab05f4229c868`. Third-party MIT notices are retained in their source directories and packaged resources. This repository does not contain BetterDisplay's implementation or bypass its licensing.

**License:** DisplayPipe's original code is released under the **MIT License** — see [`LICENSE`](LICENSE), Copyright (c) 2026 TimmySheep. Vendored upstream components (pipecap, `backend/edid-core`) keep their own included MIT notices, retained both in the source tree and in packaged builds. Third-party trademarks and Apple private interfaces are not licensed by this project.

This public repository starts from a reviewed source snapshot. Private development history, personal workspace instructions, raw local EDID captures, transaction backups, and machine-specific audit logs are intentionally not published.

### References

- [Apple Developer Forums: related display allocation discussion](https://developer.apple.com/forums/thread/814201)
- [Apple Community: M2 Pro high-refresh dual-monitor report](https://discussions.apple.com/thread/255965989)
- [Apple external-display specifications](https://support.apple.com/en-us/101571)
- [BetterDisplay EDID discussion](https://github.com/waydabber/BetterDisplay/discussions/1491)—related mechanism, not a promise that a specific paid feature fixes this setup

---

# 中文说明

DisplayPipe 是一个轻量的原生 macOS 工具，用于调查并针对特定组合绕行 Apple Silicon 双外屏初始化故障。

> **实验性、严格限定硬件的恢复工具。** 已有一次受控命令行实验实现两台实体屏亮起，并验证撤销临时覆盖后继续正常；打包 GUI 仍未通过真实故障下的完整恢复验收。它不是通用显示器修复器，也不是 Apple 支持的公开接口方案。

## 一、为什么做这个工具

测试机器是 16 英寸 M2 Pro MacBook Pro（`Mac14,10`），实验时 macOS 27.0.1／`26A434`。华为 QSN-CAB 通过 USB-C→DP、DP1.4 连接；P275MV PLUS 通过内置 HDMI 连接。恢复期间开盖，内屏作为安全回退。

两条独立连接不涉及 MST 扩展坞。故障可在两种先后顺序中发生：第一台亮，第二台无信号；快速插入有时可以，但等第一台初始化后再接第二台容易复现。

已知人工绕行是华为 DP1.2→1.4 切换，等双屏建立后再恢复高能力。笔记本经常带出门时，每次回桌都要操作 OSD 很麻烦，因此尝试封装为手动恢复工具。

## 二、根因假说和证据

**当前输出模式不等于显示器宣告的最高能力。** 在 macOS 里选 120 Hz，不会删除 EDID 中的 144／160 Hz 时序。

实机故障曾见第一台占用 `PipeIDs: [1,0]`，另一台没有可用输出。仅改缩放或降当前刷新率到 60 Hz 未释放资源；临时限制最高宣告能力后，第一台只占一个 Pipe，另一台获得释放的资源。

`PipeIDs` 才是分配情况，`MaxPipes` 是能力上限；健康状态可以是 `MaxPipes=2`、实际只分到一个 Pipe。Apple 开发者论坛有相关机制说明，但其他芯片／刷新组合的阈值不能当成 M2 Pro 规格。

**现有证据更指向 Apple 显示栈资源分配／重新平衡行为，不足以锁定具体驱动或 DCP 内部组件。也没有证据证明华为或 P275 的 EDID 违反规范。** 成功一轮限制的是 P275，不是华为固件，所以不能把它定性为华为独有故障。

## 三、已经真正成功的流程

2026-10-18 受控实验：

1. P275 先接，报告 120 Hz、占两个 Pipe；华为未上线；内屏在线。
2. 精确匹配本轮 External 服务 ID 和完整路径，新建备份，校验 SHA／checksum，独立生成可重现的 120 Hz 候选。
3. 临时移除 P275 的 144／160 Hz 宣告并调整已审核范围，保留 4K120 和相关已审核能力；不盲删扩展块，不刷固件。
4. IOAV mode1 返回成功，即时和重新枚举的 EDID 均逐字节等于候选。
5. 最早快照尚未双屏上线，下一次枚举即出现双外屏，随后约 20 秒保持；华为 `[0]`、P275 `[1]`，均报告 120 Hz。
6. 用户确认两台实体屏实际都有画面。
7. mode0 撤销临时覆盖，原始 EDID 即时和独立回读逐字节恢复；两台继续在线、各一个 Pipe，用户随后确认功能正常。

软件在本轮没有切 DP、拔插线、重启或调用“检测显示器”。更早受状态变化干扰的实验不冒充为同样的受控成功。

**边界：** CG 在线不等于实体亮屏，HiDPI 渲染尺寸不等于线缆时序。本轮没有再次独立验收双 OSD 的 3840×2160／120 Hz 输入；重复重连、睡眠唤醒、闭盖恢复和反向顺序仍未验收。

## 四、日常操作与严格支持范围

目标体验：接回两条线 → 开 App 看状态 → 点击“恢复双屏”并确认一次 → 自动备份、临时限制、等待双屏稳定、撤销并核验。

原生 AppKit 首页只展示状态、两台屏的在线／刷新率和一个主按钮。详细诊断默认折叠、按需创建并释放；有未结束覆盖时才突出撤销入口。无浏览器外壳、启动 Agent、常驻恢复轮询、网络服务或额外 Python 包。

当前只允许：**P275 在线占两个 Pipe、华为缺失且没有 Pipe、内屏在线**，并且身份及 P275 原始 EDID／候选指纹与已验收组合一致。未知／重复设备、EDID 缺失、未知能力、服务 ID／路径变化、读回不确定都会停止。华为先接的反向故障暂不自动处理。

两台已经在线时直接不写入，包括正常闭盖会话；这不是闭盖恢复验收。不要通过改硬编码指纹、改旧备份或删除 pending 状态来绕过门槛。新增型号需独立审查和 apply／reset 实测。

## 五、安全与记录

使用 Apple 私有 IOAV 接口，系统更新后可能失效。接口返回 0 不代表恢复：必须校验 EDID 字节，再看 Pipe、系统在线和用户实际画面。

写前重查故障，应用后有限轮询；两台约 120 Hz 且各独立单 Pipe 稳定后，重新核对同一目标和候选，才能撤销。撤销需读回原件，再单独检查双屏是否保持。操作意图会先写入 pending 事务；超时或身份变化时保留记录、允许针对自己事务安全撤销，不盲目换服务写入。

备份与报告在 `~/Library/Application Support/DisplayPipe/`，可能有设备标识与本地路径，分享前审阅。删除 App 不等于撤销覆盖。底层 helper 是内部实现，不建议直接调用或与旧实验 CLI 并发。

## 六、构建、依赖和测试

需要现有 Apple Silicon macOS／Xcode 工具链、Rust／Cargo、Python3.9+（仅标准库）。构建有意使用锁文件；先显式获取依赖，再构建：

```sh
cargo fetch --locked --manifest-path backend/edid-core/Cargo.toml
./scripts/build-gui.sh
open .build/DisplayPipe.app
```

Python **没有内置**。打包时解析现有 `/usr/bin/python3` 的真实可执行路径并记录，开发机是 Xcode Python3.9.6；复制给其他 Mac 不代表自带运行时。缺失时明确报错、不自动安装。未准备的机器上 developer-tool shim 可能要求安装工具，应先自行准备并验证工具链。

构建中的只读打包测试有部分依赖测试机上已经正常工作的双屏，陌生硬件不保证通过；不要因此删掉安全检查。后续硬件测试失败时，构建产物可能已经存在，要检查完整输出。App 是 ad-hoc 签名，**没有 Developer ID 和公证**，不承诺其他 Mac 的 Gatekeeper 自动放行，不应关闭系统安全保护。

测试命令见英文第八节。0.2.1 记录的本地检查：Rust14、后端 Python39、Swift11＋9＋15、范围查询2、图标2、打包8。不是线上 CI，不代替真实窗口按钮或故障验收。

优化前后应用文件体积约 2.26 MB→1.85 MB（减少18.34%）；相同启动后15／16／17秒采样的空闲 RSS 均值约160 MiB→89 MiB。本轮内存约低44%，不是所有状态的保证，不含临时辅助进程。体积统计是文件逻辑长度，不含保留的旧版／构建／运行记录；不是总磁盘占用。IORegistry 读取范围缩小后，实测约43 MB→3,213字节且保留当前所有 Pipe 映射；图标十种表示均逐像素一致。

## 七、源码、许可和公开范围

源码结构见英文第九节。EDID 处理复用 MIT 项目 [pipecap](https://github.com/a1678991/pipecap) 固定提交 `d045192de888188783b4da74b10ab05f4229c868`，保留原许可与打包声明，不含 BetterDisplay 实现或授权绕过。

**许可证：原创 DisplayPipe 代码采用 MIT 许可证**，见 [`LICENSE`](LICENSE)，版权归 2026 TimmySheep。复用的上游组件（pipecap、`backend/edid-core`）继续沿用各自自带的 MIT 声明，源码树与打包产物中均保留。第三方商标与 Apple 私有接口不在本项目授权范围内。

公开仓库从审核后的源码快照开始，不包含私人开发历史、内部 Agent 指令、原始本机 EDID、事务备份或机器维护日志。当前仍是特定硬件的用户态 workaround，不是对 macOS 根因的系统补丁。
