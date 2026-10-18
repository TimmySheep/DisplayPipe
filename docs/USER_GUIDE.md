# DisplayPipe 0.2.4 · User Guide

## Language and the compact home view

Open the app, review the external display names/status, and use **Recover Displays** only when recovery is needed. An already-healthy state is a no-write no-op. **Refresh** / Command-R is manual; there is no polling loop or added runtime/framework.

The native UI defaults to the first preferred system language: Chinese (`zh`, `zh-Hans`, or any `zh-*` variant) uses **Simplified Chinese**; other/unknown languages fall back to **English**. Open **Details → Language** to choose **System / English / 简体中文**. The language choice is saved separately from the explicit no-internal-fallback opt-in. Switching immediately redraws cached state, labels, actions and controls; it does not collect new display data or run any recovery/undo command. Names, IDs, ports and paths stay unchanged.

Home shows external display rows/counts and concise state/action messages only. Internal-display and lid context appears **only in Details**. A refusal, failure or pending override directs you to Details for the full reason instead of leaking technical paragraphs onto Home. **Undo This Override** remains visible when a pending transaction requires it.

Native buttons, menu items, confirmations, countdowns, display states and dependency-error messages are bilingual. **Raw technical diagnostics (original language)** is deliberately labeled: backend/collector prose may still be Chinese or English and is preserved without translation or filtering, alongside exact IDs/paths. This is not a claim that every diagnostic sentence has been translated. The detailed technical reference below is currently Chinese.

## Recovery and safety

Recovery uses the existing guarded backend: fresh exact-identity backup, audited conservative candidate, at most 20 seconds of stability observations, then verified original-byte reset. Without stable evidence, the countdown attempts verified automatic undo; changed identity, missing service or uncertain readback retains a pending transaction rather than retargeting a display. Do not unplug or quit during a transaction. Check the actual image and OSD yourself; system readings are not physical confirmation.

**Details → No-Internal-Fallback Authorization** explains the existing internal display/lid risks. **Allow writes without internal fallback (remembered)** is **default-off on a fresh install**. Checking or unchecking saves true or false until you change it, including across app restarts. Language changes, refresh and collapsing/reopening Details preserve the choice. Loading or toggling it neither collects displays nor calls the backend/setter. Only this opt-in is saved, never a service ID, old EDID or pending transaction as authorization. It does not trigger recovery on startup/status: every explicit Recover action still requires confirmation, current-identity preflight and a fresh backup. The 20-second countdown and backend gates are unchanged. The action confirmation still acknowledges private API risk, possible flicker/failure, the deadline and pending-transaction handling.

Python 3.9+ must already exist. Missing-runtime errors are localized and list attempted paths; no runtime is installed and no display is written. Runtime reports/backups stay in `~/Library/Application Support/DisplayPipe/`. Removing the app is not undo. Builds are ad-hoc signed, not Developer ID signed or notarized. This preference-only update does not expand hardware support or establish new real-fault recovery acceptance.

---

# 中文使用说明 · DisplayPipe 0.2.4

## 语言与首页

界面默认跟随系统首选语言：`zh`／`zh-Hans`／其它 `zh-*` 变体均使用简体中文，其它或未知语言回退英文。在 **详细信息 → 语言** 选择 **跟随系统／English／简体中文**。语言选择与主动选择的无内屏回退许可分别持久保存，切换即时重绘缓存数据，不重新采集、不执行恢复或撤销；设备名称、标识、端口与路径保持原文。

首页仅保留外接屏行、台数和结构化的简洁状态／操作提示，内屏与机盖文字全部位于详细信息。拒绝、失败与未结束覆盖会提示查看详细信息，完整原因保留在 **原始技术诊断（保留原文）**，此区明确可能仍为后端原始中英文，不声称所有诊断都已翻译。**允许无内屏回退写入（记住此选择）** 只在详细信息中显示，新安装默认不勾选；勾选或取消会保存开／关，直至再次改变，重启、刷新、切换语言和收起重开详情均保留。加载／切换此项不采集显示器、不调用后端或 setter；只保存许可布尔值，不保存服务 ID、旧 EDID 或 pending 事务作为授权。不会在启动／状态查询时自动恢复，每次仍需主动点击并确认，重新核对当前身份、新建备份。后端协议、20秒倒计时与其它安全门槛均未改变，不扩大既有实测范围。

## 日常使用（不需要终端）

1. 将 MacBook Pro 放回支架，**打开机盖，让内屏在线**。接回 P275 的内置 HDMI 和华为的 USB-C→DP 两根线。
2. 打开 `~/Applications/DisplayPipe.app`（蓝紫双显示器、绿色连接图标）。App 启动只读检查；不自启、不后台监控、不自行应用覆盖。
3. 紧凑主界面按**实际枚举到的外接显示器数量**逐行显示真实名称（优先显示器自己的 EDID 描述符 0xFC 名称，其次 CoreGraphics 名称，再退回 vendor:model）、在线状态与系统报告刷新率，下方一行给出外接台数，以及一个 **恢复双屏** 主按钮。名字读不出来时明确写“名称不可读／未命名外接服务”，不会用固定产品名代替。**无需恢复** 时不用操作；主按钮即使点击，也会重新检查后直接返回，不调用 setter。右上角“刷新”或 Command-R 可手动更新，没有自动刷新。
4. 若显示“发现可恢复的连接故障”，点击 **恢复双屏**，阅读风险说明并确认一次（两个接入方向都可用且对称）。之后自动完成新备份 → 基于**该显示器自己的 EDID** 生成临时候选 → 最长20秒倒计时观察；一旦连续取得稳定双屏证据就立即核验撤销，**如果到点仍无稳定证据就自动执行可核验的撤销**，不需要你点击。忙碌时显示进度指示并禁用重复操作。请不要插拔、合盖、切换 OSD 或退出。

   接入顺序只是说明行：本机跑完过一次可核验的恢复+撤销的组合会标注 **接入顺序（本机已验证）**；没有这类记录的组合标中性提示 **首次使用该组合**。两者都只是提示，不阻止写入，也不代表“每次都可靠”。
5. 系统恢复后，亲自检查两个屏幕都有画面及显示器 OSD 输入。展开“详细信息”，可点“确认实体双屏与 OSD”记录你的确认；这与 CoreGraphics 的系统在线证据不同，不是恢复流程的第二个必需步骤。此项只在等待实体确认时出现。

“详细信息”默认折叠，按需创建诊断视图，收起后释放；其中包含 Pipe/EDID/逻辑与渲染尺寸、采集时间、记录和使用说明。“检查方案（不写入）”也在此处，是可选诊断，不是恢复前的必需步骤。它仅采集和保存备份/候选；真正恢复总是使用**本次新采集**的注册表 ID 和完整路径，绝不复用旧路径猜设备。主界面没有橙色提示行，风险说明保留在确认框与本指南。

## 支持边界：面向单一机型的用户态手动工具，不是通用驱动修复

- 唯一开发/实测机器：M2 Pro MacBook Pro `Mac14,10`（其它机型仍拒绝写入）。
- 识别完全运行时进行、不写死产品名：目标是**当前占用两个 Pipe 的在线外接显示器**，条件是对端外接端口/服务没有链路或没有 Pipe，且内屏在线（或你显式选择无内屏回退）。两个接入方向都支持；方向只作为**本机运行记录得出的标签**（有可核验运行＝“接入顺序（本机已验证）”，否则＝“首次使用该组合”），不会因此拒绝写入，也不会削弱任何门槛。标签只读运行记录，不需要你额外去点“确认实体双屏与 OSD”。
- 目标显示器自己的 EDID 必须通过 fail-closed 审核并能生成保守候选；范围描述符（0xFD）只有**垂直偏移位/保留位**才拒绝写入（错误文本给出确切字节），水平偏移位会被记录在审计与运行清单里；保留时序只允许落在其自身描述符量化误差内（远小于 0.1Hz），144/160Hz 仍会被移除。身份不明/重复、EDID 缺失、出现未知能力、服务ID或完整路径变化都会停止。
- 参考机上两个接入方向各已完成一次可核验恢复+撤销（双CG120Hz、独立单Pipe、mode0撤销后原件一致且双屏保持，用户确认实体两屏点亮）。**睡眠唤醒、重复重连、闭盖写入和多机型仍未测试**；每个方向只有一次成功，这不是“每次可靠”的承诺。
- 使用Apple私有临时IOAV接口；可能闪屏、失败或随系统版本失效。不写EEPROM/固件，不改SIP，不装自启，不重启，不绕过BetterDisplay许可证。

## 读懂结果

- **已在线，无需恢复**：新采集已看到两目标CG在线，**没有调用setter**。这不是本软件修复成功的证据。
- **检查方案完成**：只保存文件，没有显示写入。
- **应用临时120Hz候选**：单一精确服务被授权尝试mode1；接口返回0本身不代表成功。要求即时和重新枚举的EDID均逐字节相同。
- **正在等待双屏**：界面显示剩余秒数；最多20秒，连续3次样本要求两外屏CG约120Hz、各一个不同Pipe。即刻尚未上线不直接判定失败；轮询同时保存CG和资源映射。
- **系统双屏恢复 · 原件撤销已核验**：同一目标仍存在且候选一致时才mode0，之后即时与独立枚举回读原件精确一致。还需用户检查实体画面/OSD。
- **已自动撤销临时覆盖 · 原件已核验 / 双屏未恢复**：倒计时到点仍无稳定证据时自动执行的可核验撤销。原件字节已一致；第一种表示系统已回到双屏，第二种表示系统仍未给出稳定双屏证据。两者都不留未结束事务。
- **已识别故障 · 当前拒绝写入**：故障形态肯定，但某道门失败（例如目标 EDID 不可读、对端类别不支持、分配歧义）。错误文本给出**确切字段**；这不是“不支持该显示器”的含糊说法。
- **当前连接不支持自动恢复**：当前状态不是可恢复目标（例如没有任何外屏占用双 Pipe、缺少对端缺失证据、枚举失败）。
- **原件已撤销，但双屏未保持**：不宣称恢复成功，不自动再写。
- **需要处理 · 有未结束覆盖事务**：出现超时、身份变化、读回不确定或进程中断。不会盲目定时reset，不会把事务悄悄标为完成。
- **不支持/失败**：查看具体原因。失败与不支持不同，不能反复点击绕过。

## 未结束事务与手动撤销

正常路径不需要手动撤销：稳定即核验撤销，超时则自动撤销；只有在**自动撤销无法核验**（目标消失、身份/路径变化、回读不确定）时才保留未结束事务。此时主界面会醒目显示 **撤销本次覆盖**，同时禁用再次恢复；没有未结束覆盖时完全隐藏此按钮。点击并确认，仅处理恰好一个本程序拥有的pending事务。原备份校验、当前候选、同一注册表ID和完整路径都必须匹配，才执行mode0并核验原件。已经是原件时只记录已撤销，不调用setter。

**无法自动撤销的情况请照实处理**：如果那台显示器从注册表里彻底消失（例如线缆/供电问题），自动撤销会被拒绝并留下 pending 记录；请恢复连接后重新打开App，让它按同一注册表ID与完整路径执行撤销。永远不要为了“清掉 pending”而删除状态目录。

如果拔线/重接导致注册表ID改变、目标消失、EDID读不到或出现未知内容，App会停止并显示仍需处理，**不会按名称换目标强写**。请保留记录供人工排查；不要删除pending状态来强行开始新事务。强制退出或断电后再次打开App仍能看到未结束事务。普通退出在写入流程中会被阻止。

“打开记录”和“使用说明”位于“详细信息”内。所有备份、候选、事务事件和每次观察保存在：

`~/Library/Application Support/DisplayPipe/`

`runs/<新UUID>/`：本次original.bin及身份/SHA元数据、candidate.bin及审计、操作前快照、每次轮询、native结果和只追加event文件。状态**不在App或源代码内**，复制/升级App不会清除。单一用户级文件锁防止本App/新恢复CLI并发操作。不要并行使用旧实验CLI或直接native helper。锁随进程释放，无常驻守护进程。

离线EDID解析的临时字节保存后移入`scratch-archive/`，不永久删除。记录含本机路径、显示器标识/序列，分享前应审阅隐私。测试输出、旧App和图标生成目录也保留；本工具不自动清理或清空废纸篓。

## 诊断区的证据边界

采集完成不等于两屏在线。PipeIDs是实际映射，MaxPipes只是容量；EDID可读不等于CG在线；CG逻辑/渲染尺寸不等于线缆时序；系统报告120Hz不等于仪器或OSD实测。各源顺序采集，不是原子快照。刷新按Command-R；没有自动恢复或自动刷新循环。

为减少内存，GUI只查询提供映射的 `AppleDisplayConnectionManager` 子树，不再加载整机 IORegistry；若该子树或映射缺失，会明确显示诊断不完整，不把缺失当作健康，也不回退到高内存整树扫描。诊断详情只在展开时创建。

## 安装、依赖与卸载

- 可直接从`.build/DisplayPipe.app`复制到任意目录使用；推荐`~/Applications/DisplayPipe.app`。App内只包含Swift GUI、独立IOAV/EDID/CG探针、Rust EDID解析二进制、Python运行脚本、说明和MIT许可证及资源哈希清单；不再复制构建/测试脚本或原生源码。没有源目录运行依赖，不增加框架、第三方资源或运行时。图标保留所有尺寸，打包时仅无损重编码PNG，像素不变。
- **Python并未打包**：App包内`python-path.txt`记录的是**构建机**路径（本机为`/Applications/Xcode.app/Contents/Developer/usr/bin/python3`，Python 3.9.6），它现在只是一个提示。运行时按下面的顺序解析，每个候选都必须是可执行文件且报告 Python 3.9+：
  1. `DISPLAYPIPE_PYTHON`（显式指定；若不可用则直接报错，不会静默换用别的解释器）
  2. 包内记录的路径（存在且合格时）
  3. `/usr/bin/python3`、`/usr/local/bin/python3`、`/opt/homebrew/bin/python3`
  4. `/Library/Frameworks/Python.framework/Versions/*/bin/python3`
  5. `DISPLAYPIPE_PYTHON_CANDIDATES`（冒号分隔，**替换**第 3 步的候选列表，供自定义安装与测试使用）
  都不合格时会给出明确错误，列出已尝试的路径并说明需要安装 Python 3.9+，且明确写出**未写入显示**。不安装Python、pip或第三方包，不修改系统，不自动下载。Finder不依赖shell PATH。
- 使用本机ad-hoc签名，仅证明该包内容完整；没有Developer ID或Apple公证，不承诺其它Mac上Gatekeeper自动放行。不修改系统安全策略。
- 更新前将旧App**重命名备份**，再复制新App；不删除旧版。卸载可将App移入废纸篓，状态目录另行保留。若有未结束事务，先安全处理，不能把删除App当作撤销覆盖。

## 给开发/验收者

正式源码：`~/src/DisplayPipe`。`scripts/build-gui.sh`执行Rust/Python/Swift测试、构建、生成并无损压缩本地图标、签名和打包后只读测试，不启动/退出GUI事件循环。`scripts/test-gui.sh`包括实际AppKit视图层级的紧凑尺寸、默认隐藏诊断、pending撤销和安全禁用测试；它不代表真实窗口的截图/交互验收。`scripts/test-icon.py`通过AppKit独立解码验证无损压缩前后所有图标尺寸逐像素相同。`scripts/test-package.py`检查精确运行资源清单和哈希，并测试真实复制后的包、图标、签名、解释器和健康无写入路径；实际健康主按钮契约使用**禁止真实setter的注入**核验，不能意外改显示。

包内`--smoke-json`只读诊断；`--recovery-smoke-json`通过与GUI相同的客户端执行默认dry-run（健康与故障状态都只做只读计划，`setterCalled=false`）。恢复CLI为`Resources/backend/recovery.py`：默认`status`；`recover`默认dry-run，显示写入必须同时传`--execute --confirm-private-api-risk`；内屏不在线时还必须显式传 `--ack-no-internal-fallback`（GUI 在“详细信息”里用“允许无内屏回退写入（记住此选择）”表达，新安装默认关闭，仅保存用户选择的布尔值；后端本身不读取此偏好，只在显式恢复时接收该参数）。`status` 永远输出可 JSON 序列化的结果（`already-healthy`/`ready`/`refused`/`unsupported`）。普通用户不需要终端命令。构建/测试脚本只保留在正式源码；重新构建需正式源目录、已有Xcode和Rust工具链。

只读联调（不写显示、不改用户状态）：`python3 scripts/check-live-readiness.py -v` 会枚举当前真实显示器、打印分类与目标/对端，能生成候选时打印候选的 SHA、被移除与保留的时序，并用**禁止调用 setter** 的方式跑一次 dry-run。在真机故障现场用它确认“会走恢复路径”而不是“会被拒绝”。

GUI视觉/交互由主控CUA另行验收。编译、离线故障模拟、健康只读smoke都不能替代真实故障下的打包GUI恢复验收。
