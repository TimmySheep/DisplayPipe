import Foundation

/// Only this preference is persisted. Backend protocol, monitor names, IDs and paths are opaque.
enum LanguageChoice: String, CaseIterable { case system, english, simplifiedChinese }
enum L10n {
    static let preferenceKey = "DisplayPipe.uiLanguage"
    static var preferences: UserDefaults = .standard
    static var systemLanguages: () -> [String] = { Locale.preferredLanguages }
    static var choice: LanguageChoice { LanguageChoice(rawValue: preferences.string(forKey: preferenceKey) ?? "") ?? .system }
    static var language: LanguageChoice {
        if choice != .system { return choice }
        let first = systemLanguages().first?.lowercased() ?? ""
        return first == "zh" || first.hasPrefix("zh-") || first.hasPrefix("zh_") ? .simplifiedChinese : .english
    }
    static func select(_ choice: LanguageChoice) { preferences.set(choice.rawValue, forKey: preferenceKey) }
    /// English is the catalog key and guaranteed fallback. Interpolate opaque arguments once,
    /// after lookup; never perform translation or recursive replacement on user/device text.
    static func text(_ english: String, _ arguments: String...) -> String {
        let template = language == .simplifiedChinese ? catalog[english] ?? english : english
        var output = ""; var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let end = template[index...].firstIndex(of: "}"),
               let number = Int(template[template.index(after: index)..<end]), arguments.indices.contains(number) {
                output += arguments[number]; index = template.index(after: end)
            } else { output.append(template[index]); index = template.index(after: index) }
        }
        return output
    }
    static let catalog: [String: String] = [
        " Beijing time UTC+8": " 北京时间 UTC+8",
        " and ": " 与 ",
        " · Incomplete readings · See Details": " · 采集不完整 · 请查看详细信息",
        " · Refresh rate unknown": " · 刷新率未知",
        "(no candidate paths)": "（无可尝试的路径）",
        "Action required · Pending override": "需要处理 · 有未结束覆盖",
        "Additional Authorization Required": "需要额外授权",
        "Allow writes without internal fallback (this session only; not saved)": "允许无内屏回退写入（合盖；仅本次，不保存）",
        "Ambiguous identity; name unconfirmed": "同样身份的设备多于一台，无法确认名称",
        "Application resources are missing": "应用资源路径缺失",
        "Applying temporary candidate…": "正在应用临时候选…",
        "At the deadline, undo is attempted and original bytes verified automatically; no click is needed. Do not unplug or quit.": "到点未取得稳定双屏证据会自动撤销临时覆盖并核验原件，不需要你点击。请勿拔线或退出。",
        "Automatic operations stopped. See Details.": "已停止自动操作，请查看详细信息。",
        "Automatic recovery unavailable": "当前连接不支持自动恢复",
        "Automatic undo could not be verified. Use Undo This Override and see Details.": "自动撤销未能核验完成。请使用“撤销本次覆盖”，并查看详细信息。",
        "Automatically undone · Displays not restored": "已自动撤销临时覆盖 · 双屏未恢复",
        "Automatically undone · Original verified": "已自动撤销临时覆盖 · 原件已核验",
        "Backend interrupted or dependency unavailable (interpreter {0}, exit {1}). Preserve records and refresh to check for pending transactions.\n{2}": "后端中断或依赖不可用（解释器 {0}，退出 {1}）。若曾开始恢复，请保留记录并刷新检查未结束事务。\n{2}",
        "Backup and candidate saved for the current identity. Recovery checks again before applying.": "已按本次实时身份保存备份与候选；真正恢复时会重新检查。",
        "Both displays online · Undoing override…": "双屏已上线 · 正在撤销覆盖…",
        "Cancel": "取消",
        "Check Plan (No Writes)": "检查方案（不写入）",
        "Check connections": "请检查连接",
        "Check the image. Undo does not mean the connection fault was fixed.": "请检查画面；撤销不代表连接故障已解决。",
        "Check the physical image and OSD; record confirmation in Details.": "请检查实体画面及 OSD；可在详细信息中记录确认。",
        "Checking": "检查中",
        "Checking connections…": "正在检查连接…",
        "Checking identity and backup…": "正在检查身份与备份…",
        "Collected: ": "采集：",
        "Combination: ": "本次组合：",
        "Confirm Physical Displays & OSD": "确认实体双屏与 OSD",
        "Confirm Undo": "确认撤销",
        "Confirm and Recover": "确认并恢复",
        "Confirmed": "已确认",
        "Connected · EDID unreadable (possibly no signal)": "已连接但 EDID 不可读（可能无信号）",
        "Connected · Offline (name unreadable)": "已连接 · 系统未上线（名称不可读）",
        "Connected · Offline (no signal / no Pipe)": "已连接 · 系统未上线（无信号 / 无 Pipe）",
        "Connection order (verified on this Mac)": "接入顺序（本机已验证）",
        "Connection order: ": "接入顺序：",
        "Countdown ended · Automatically undoing…": "倒计时结束 · 正在自动撤销临时覆盖…",
        "DISPLAYPIPE_PYTHON is not executable or is older than 3.9; correct or unset it. ": "DISPLAYPIPE_PYTHON 指向的解释器不可执行或低于 3.9；请修正该变量或取消它。",
        "Details": "详细信息",
        "Do not unplug or quit.": "请勿拔线或退出。",
        "External display": "外接显示器",
        "External displays: enumeration failed": "外接显示器：枚举失败",
        "External displays: {0}": "外接显示器 {0} 台",
        "Fault detected · Write refused": "已识别故障 · 当前拒绝写入",
        "First use of this combination": "首次使用该组合",
        "Force quitting may leave a pending override. Reopening the app exposes manual undo.": "强制退出可能留下未结束覆盖；再次打开App会显示手动撤销。",
        "Incomplete readings · See Details": "采集不完整 · 请查看详细信息",
        "Language": "语言",
        "No external displays detected": "未检测到外接显示器",
        "No recovery needed": "无需恢复",
        "No stable dual-display evidence. See Details.": "未取得稳定双屏证据。请查看详细信息。",
        "No usable existing Python 3.9+. Tried: {0}. This app installs no runtime and does not modify the system. {1}No display writes occurred.": "缺少可用的现有 Python 3.9+。已尝试：{0}。本App不安装任何运行时、不修改系统；{1}未写入显示。",
        "No-Internal-Fallback Authorization": "无内屏回退授权",
        "OK": "好",
        "Online": "在线",
        "Only the one owned pending transaction with the same registry ID and full path is eligible. Mismatched original/candidate bytes or readback refuse writes; never retarget another device.": "只处理唯一未结束事务的同一注册表ID与完整路径。原件/候选或当前回读不一致时拒绝写入，不自动改选设备。",
        "Open Records": "打开记录",
        "Override removed · Displays did not stay online": "覆盖已撤销 · 双屏未保持",
        "Override removed · Original verified": "覆盖已撤销 · 原件已核验",
        "Personally confirm that {0} are lit and check the actual OSD input. This records your confirmation only; it does not measure wire timing or write to displays.": "请亲自确认 {0} 均点亮，并查看显示器 OSD 实际输入。此按钮只记录你的确认，不测量线缆时序、不写显示。",
        "Physical Displays Confirmed?": "实体屏幕已确认？",
        "Physical display confirmation recorded": "已记录实体双屏确认",
        "Plan checked · No display writes": "方案已检查 · 未写入显示",
        "Provide Python 3.9+ (for example /usr/bin/python3 from Xcode/command line tools, or an existing interpreter via DISPLAYPIPE_PYTHON). ": "请安装或提供 Python 3.9+（例如 Xcode/命令行工具自带 /usr/bin/python3，或用 DISPLAYPIPE_PYTHON 指定已有解释器）。",
        "Quit DisplayPipe": "退出 DisplayPipe",
        "Raw technical diagnostics (original language)": "原始技术诊断（保留原文）",
        "Read the technical risks in Details and explicitly authorize this session. No display write occurred.": "请在详细信息中阅读技术风险，并主动选择本次授权。未写入显示。",
        "Recover Displays": "恢复双屏",
        "Recover Displays?": "恢复双屏？",
        "Recoverable connection fault detected": "发现可恢复的连接故障",
        "Recovery is in progress. Please wait.": "恢复事务正在进行，请等待完成。",
        "Refresh": "刷新",
        "Run records: ": "本次记录：",
        "See Details and records before retrying recovery.": "请查看详细信息和记录，暂勿重复恢复。",
        "See Details for the exact refusal reason.": "请展开详细信息，查看具体拒绝原因。",
        "See Details for the supported scope and exact reason.": "请展开详细信息，查看支持范围及具体原因。",
        "Select the external display holding two Pipes by its current identity, back up its EDID, apply a conservative temporary candidate, and observe for up to {0} seconds. ": "将按本次实时身份选择占用双 Pipe 的外接显示器：备份它本次的 EDID，临时应用保守候选，并观察最多 {0} 秒；",
        "System": "跟随系统",
        "System displays restored · Override removed": "系统双屏已恢复 · 覆盖已撤销",
        "System readings do not measure physical input; check the display OSD. The countdown attempts verified automatic undo. A missing registry service can require manual handling. See the guide for scope, private API risks and stop conditions.": "系统读数不是实体输入测量；请查看显示器 OSD。倒计时自动撤销是主要安全网；若某台显示器从注册表彻底消失，仍可能需要人工处理。支持范围、私有接口风险及停止条件见使用说明。",
        "System readings show both displays and original bytes match. Check the physical image and OSD.": "系统读数已回到双屏且原件字节一致；请检查实体画面与 OSD。",
        "Target: ": "本次目标：",
        "Technical Information": "技术信息",
        "The countdown automatically attempts undo if no stable evidence arrives. Review Details before recovering.": "倒计时到点未取得稳定证据时会自动撤销临时覆盖。请查看详细信息后恢复。",
        "The diagnostics below retain their original backend language (Chinese or English), device names and paths. UI language does not rewrite them.": "以下诊断保留后端原文，可能包含中文或英文、设备名称和路径；界面语言不会改写它们。",
        "The internal display is offline: explicitly select the no-internal-fallback permission in Details. Opening the lid may change service identity. Unverifiable countdown undo retains a pending transaction.": "内屏未在线：请在详细信息中主动选择允许无内屏回退写入。打开机盖可能改变服务身份；倒计时无法核验撤销时保留未结束事务。",
        "Unable to complete check or operation": "无法完成检查或操作",
        "Undo This App’s Override?": "撤销本程序本次覆盖？",
        "Undo This Override": "撤销本次覆盖",
        "Unknown": "未知",
        "Unknown (enumeration failed)": "无法确认（枚举失败）",
        "Unknown / variable (no fixed API value)": "未知 / 可变（API 未给出固定值）",
        "Unknown identity": "身份未知",
        "Unknown time ({0})": "时间未知（{0}）",
        "Unnamed external display": "未命名外接显示器",
        "Unnamed external service": "未命名外接服务",
        "User Guide": "使用说明",
        "Verifying original bytes. Uncertain identity or readback retains a pending transaction. Please wait.": "正在核验原件；身份或回读不确定时保留未结束事务。请稍候。",
        "Verifying original data. Please wait.": "正在核验原始数据，请稍候。",
        "Waiting for displays… {0}s remaining (of {1}s); automatic undo at deadline": "正在等待双屏…还可等待 {0} 秒（共 {1} 秒）；到点将自动撤销临时覆盖",
        "Without an online internal display, the selected external display may be the only lit screen. It may go dark while reinitializing, hiding progress and undo. The countdown attempts an automatic revert; a missing service or changed identity prevents verified undo and retains a pending transaction. Opening the lid may change service identities. Manual handling may be needed.": "内屏未在线时代码只在“无内屏回退”许可下写入：目标外屏将是唯一点亮的屏幕，写入时会短暂重新初始化/黑屏，期间看不到进度和“撤销本次覆盖”；倒计时到点会自动撤销临时覆盖，但若该显示器从注册表中消失或身份变化，自动撤销会被拒绝并保留未结束事务。",
        "Without stable evidence, automatically undo and verify the original bytes at the deadline; no click is needed. Private APIs may flicker or fail. Uncertain identity/readback retains a pending transaction for manual handling. Healthy displays are not written. Do not unplug or quit.": "到点未取得连续稳定证据会自动撤销临时覆盖并核验原件字节，不需要你点击。私有接口可能闪屏或失败；身份/回读不确定时保留未结束事务，需人工处理。已健康不会写入。请勿拔线或退出。",
        "the external displays": "两个外接屏幕",
    ]
}
