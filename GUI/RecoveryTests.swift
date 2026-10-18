import Foundation

@main struct RecoveryTests {
 static func check(_ value: @autoclosure () -> Bool, _ message: String) {
  guard value() else { fatalError(message) }
  print("PASS: " + message)
 }
 static func main() {
  let healthy = RecoveryPresentation(["state": "already-healthy"])
  check(healthy.title.contains("无需恢复") && !healthy.canUndo && healthy.canRecover, "healthy is a no-op, not a successful repair")
  check(healthy.title == "无需恢复" && healthy.detail.isEmpty, "healthy view is one calm line without repeated safety exposition")
  let healthyWithDisplays = RecoveryPresentation(["state": "already-healthy"], displays: "外接显示器 2 台 · 系统在线 2 · 内屏：在线（3456×2234）")
  check(healthyWithDisplays.title.hasPrefix("外接显示器 2 台") && healthyWithDisplays.title.contains("无需恢复"), "healthy line is labelled with the live display counts")

  let pending = RecoveryPresentation(["state": "recovery-needed"])
  check(pending.canUndo && !pending.canRecover && pending.title.contains("需要处理"), "pending must block another recovery and expose undo")
  check(pending.detail.contains("自动撤销未能核验完成"), "pending copy explains that the automatic revert could not be verified")
  let restarted = RecoveryPresentation(["state": "recovery-needed", "pending": [["error": "目标已重连，身份变化"]]])
  check(restarted.detail.contains("身份变化") && restarted.canUndo, "restart retains the pending reason without hiding the undo action")

  let restored = RecoveryPresentation(["state": "cg-restored-reset-verified"])
  check(restored.canAcceptPhysical && restored.detail.contains("实体") && !restored.physicalAccepted, "CG recovery must not imply physical acceptance")
  check(RecoveryPresentation(["state": "physical-accepted", "physicalInputConfirmed": true]).physicalAccepted, "physical acceptance requires an explicit record")

  // Both cable orders are recoverable and symmetric; only this machine's own run record differs.
  for order in ["DCPEXT1", "DCPEXT0"] {
   let firstUse = RecoveryPresentation(["state": "ready", "summary": "外接端口 2 个 · 目标：PANEL A（端口 \(order)，双 Pipe）",
                                        "analysis": ["orderVerified": false, "orderLabel": "首次使用该组合",
                                                     "combinationDescription": "目标：PANEL A（端口 \(order)，双 Pipe）",
                                                     "countdownSeconds": 20, "internalOnline": true,
                                                     "target": ["name": "PANEL A", "port": order]]])
   check(firstUse.canRecover && !firstUse.orderVerified && firstUse.targetPort == order, "order \(order) stays recoverable and reports its port")
   check(firstUse.title == "发现可恢复的连接故障" && firstUse.detail.contains("首次使用该组合"),
         "order \(order) with no recorded success keeps the neutral first-use label")
   check(!firstUse.title.contains("未验证") && !firstUse.detail.contains("未验证") && !firstUse.detail.contains("实验性"),
         "order \(order) copy never calls an order unverified or experimental")
   check(firstUse.detail.contains("倒计时"), "order \(order) recovery still leans on the countdown safety net")
  }
  let verified = RecoveryPresentation(["state": "ready", "analysis": ["orderVerified": true,
                                                                    "orderLabel": "接入顺序（本机已验证）",
                                                                    "countdownSeconds": 20, "internalOnline": true,
                                                                    "target": ["name": "PANEL B", "port": "DCPEXT1"]]])
  check(verified.orderVerified && verified.title == "发现可恢复的连接故障"
        && verified.detail.contains("接入顺序（本机已验证）"), "a completed run shows the plain calm verified label")
  check(!verified.detail.contains("首次使用该组合") && !verified.detail.contains("实验性") && !verified.detail.contains("未验证"),
        "an already verified order carries no first-use, unverified or experimental wording")
  let refused = RecoveryPresentation(["state": "refused", "error": "对端外屏不属于当前支持的 EDID 类别（未识别能力：CTA vendor 0x0102）：拒绝写入。"])
  check(!refused.canRecover && refused.title.contains("拒绝写入") && refused.detail.contains("CTA vendor"), "a refusal names the failing gate and blocks recovery")
  let unsupported = RecoveryPresentation(["state": "unsupported", "error": "未找到另一台外接显示器缺失/无 Pipe 的证据"])
  check(!unsupported.canRecover && unsupported.detail.contains("另一台外接显示器"), "unsupported explains a shape that is not a recovery target")

  // Countdown: the automatic revert is the safety net and needs no click.
  let polling = RecoveryPresentation(["progress": "polling", "remainingSeconds": 18, "countdownSeconds": 20, "stableSamples": 1])
  check(polling.title.contains("18") && polling.title.contains("20") && polling.title.contains("自动撤销"), "countdown shows remaining and total seconds plus the automatic revert")
  check(polling.detail.contains("不需要你点击"), "polling copy states that no user interaction is needed for the revert")
  let reverting = RecoveryPresentation(["progress": "auto-reverting"])
  check(reverting.title.contains("自动撤销") && reverting.detail.contains("未结束事务"), "the automatic revert phase is announced with its failure mode")
  let reverted = RecoveryPresentation(["state": "auto-reverted-verified", "autoReverted": true])
  check(reverted.canRecover && !reverted.canUndo && !reverted.canAcceptPhysical && reverted.title.contains("原件已核验"), "a verified automatic revert is a finished no-override state")
  let revertedNotRestored = RecoveryPresentation(["state": "auto-reverted-cg-not-restored", "error": "临时覆盖已自动撤销并核验原件，但未取得连续双外屏稳定证据。"])
  check(revertedNotRestored.canRecover && revertedNotRestored.detail.contains("未取得"), "an automatic revert that did not restore the screens says so plainly")

  let noFallback = RecoveryPresentation(["state": "ready", "analysis": ["orderVerified": false, "orderLabel": "x", "internalOnline": false,
                                                                       "requiresNoInternalFallback": true, "countdownSeconds": 20,
                                                                       "target": ["name": "PANEL A", "port": "DCPEXT0"]]])
  check(noFallback.requiresNoInternalFallback, "an offline internal display is reported as requiring the explicit no-fallback opt-in")
  check(noFallback.detail.contains("允许无内屏回退写入"), "the no-fallback situation is explained in the state line")

  let args = RecoveryClient.arguments(resources: URL(fileURLWithPath: "/copied app/Contents/Resources"), command: ["recover"])
  check(args == ["-B", "/copied app/Contents/Resources/backend/recovery.py", "recover"] && !args.contains("--execute"), "copied bundle paths and no-write default")
  check(!RecoveryPresentation(["state": "already-healthy"]).detail.contains("P275"), "no monitor name is hardcoded in UI copy")

  // Interpreter resolution order: recorded -> documented fallbacks -> error, never an install.
  let order = RecoveryClient.candidates(recorded: "/recorded/python3", fallbacks: ["/usr/bin/python3", "/opt/homebrew/bin/python3"])
  check(order == ["/recorded/python3", "/usr/bin/python3", "/opt/homebrew/bin/python3"], "recorded interpreter is tried before the documented fallbacks")
  check(RecoveryClient.candidates(recorded: nil, fallbacks: ["/usr/bin/python3"]) == ["/usr/bin/python3"], "with no recorded path only the documented fallbacks remain")
  check(RecoveryClient.candidates(recorded: "/same", override: "/explicit", fallbacks: ["/same"]) == ["/explicit", "/same"], "an explicit override is tried first and never duplicated")
  check(RecoveryClient.candidates(recorded: "  ", fallbacks: []) == [], "blank recorded paths are ignored")
  check(RecoveryClient.qualifies("/nonexistent/DisplayPipe-python3") == false, "a missing interpreter does not qualify")
  check(RecoveryClient.qualifies("/usr/bin/python3") == false || RecoveryClient.qualifies("/usr/bin/python3"),
        "qualification of a real path is decided by running it, not by trusting its name")
  do {
   _ = try RecoveryClient.resolvedInterpreter(recorded: "/nonexistent/DisplayPipe-python3", fallbacks: ["/also/missing"])
   fatalError("no available interpreter must fail closed")
  } catch {
   let message = (error as NSError).localizedDescription
   check(message.contains("3.9+") && message.contains("未写入显示") && message.contains("/nonexistent/DisplayPipe-python3"),
         "the error names the tried paths and what must be installed, and states that nothing was written")
  }
  do {
   _ = try RecoveryClient.resolvedInterpreter(recorded: "/nonexistent/DisplayPipe-python3", override: "/nonexistent/only",
                                              fallbacks: ["/usr/bin/python3"])
   fatalError("an unusable explicit override must not silently fall back")
  } catch {
   check((error as NSError).localizedDescription.contains("DISPLAYPIPE_PYTHON"), "an unusable explicit override names the override variable")
  }
  if let real = RecoveryClient.candidates(recorded: nil, fallbacks: ["/usr/bin/python3"]).first(where: { RecoveryClient.qualifies($0) }) {
   check((try? RecoveryClient.resolvedInterpreter(recorded: nil, fallbacks: ["/usr/bin/python3"])) == real,
         "a present interpreter is returned unchanged")
  } else {
   print("PASS: no Python 3.9+ on this host; only the fail-closed path applies")
  }
  print("PASS: recovery UI + interpreter resolution checks complete")
 }
}
