import Foundation
@main struct RecoveryTests {
 static func main() {
  let healthy=RecoveryPresentation(["state":"already-healthy"])
  guard healthy.title.contains("无需恢复"), !healthy.canUndo, healthy.canRecover else { fatalError("healthy is a no-op, not a successful repair") }
  guard healthy.title == "双屏在线 · 无需恢复", healthy.detail.isEmpty else { fatalError("healthy view must be one calm line without repeated safety exposition") }
  let pending=RecoveryPresentation(["state":"recovery-needed"])
  guard pending.canUndo, !pending.canRecover, pending.title.contains("需要处理") else { fatalError("pending must block another recovery and expose undo") }
  let restarted=RecoveryPresentation(["state":"recovery-needed","pending":[["error":"目标已重连，身份变化"]]])
  guard restarted.detail.contains("身份变化"), restarted.canUndo else { fatalError("restart must retain pending reason without hiding the undo action") }
  let restored=RecoveryPresentation(["state":"cg-restored-reset-verified"])
  guard restored.canAcceptPhysical, restored.detail.contains("实体"), !restored.physicalAccepted else { fatalError("CG recovery must not imply physical acceptance") }
  let unsupported=RecoveryPresentation(["state":"unsupported","error":"华为先接未验证"])
  guard !unsupported.canRecover, unsupported.detail.contains("华为先接") else { fatalError("unsupported must explain fail-closed") }
  guard RecoveryPresentation(["state":"physical-accepted","physicalInputConfirmed":true]).physicalAccepted else { fatalError("physical acceptance requires explicit record") }
  guard RecoveryPresentation(["progress":"polling","remainingSeconds":18,"stableSamples":1]).title.contains("18") else { fatalError("progress must show bounded poll") }
  let args = RecoveryClient.arguments(resources: URL(fileURLWithPath: "/copied app/Contents/Resources"), command: ["recover"])
  guard args == ["-B", "/copied app/Contents/Resources/backend/recovery.py", "recover"], !args.contains("--execute") else { fatalError("copied bundle paths and no-write default") }
  print("PASS: 9 recovery UI state/compact copy/pending reason/physical acceptance/progress/bundle argument checks")
 }
}
